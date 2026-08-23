import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Obsługiwane źródła powiadomień: pakiet Androida → etykieta.
///
/// Portfel Google jest tu kluczowy: przy płatności zbliżeniowej to ON
/// pokazuje push („Zapłacono 23,50 zł w Biedronka"), a pushe transakcyjne
/// banków bywają domyślnie wyłączone. Dublet z powiadomieniem banku o tej
/// samej płatności wyłapuje anty-dublet w [BankSuggestionsNotifier.add].
const kBankPackages = <String, String>{
  'pl.pkobp.iko': 'PKO BP',
  'pl.ing.mojeing': 'ING',
  'com.revolut.revolut': 'Revolut',
  'com.google.android.apps.walletnfcrel': 'Portfel Google',
};

/// Propozycja wydatku/wpływu wyłuskana z powiadomienia banku.
class BankSuggestion {
  const BankSuggestion({
    required this.id,
    required this.bank,
    required this.merchant,
    required this.amountCents,
    required this.type,
    required this.capturedAt,
  });

  factory BankSuggestion.fromJson(Map<String, dynamic> json) {
    return BankSuggestion(
      id: json['id'] as String,
      bank: json['bank'] as String,
      merchant: json['merchant'] as String,
      amountCents: json['amount_cents'] as int,
      type: TransactionType.fromDbValue(json['type'] as String),
      capturedAt: DateTime.parse(json['captured_at'] as String),
    );
  }

  final String id;
  final String bank;
  final String merchant;
  final int amountCents;
  final TransactionType type;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'bank': bank,
        'merchant': merchant,
        'amount_cents': amountCents,
        'type': type.toDbValue(),
        'captured_at': capturedAt.toIso8601String(),
      };
}

/// Wyłuskuje kwotę/typ/sklep z tekstu powiadomienia bankowego.
///
/// Formaty powiadomień różnią się między bankami i wersjami aplikacji,
/// więc nie parsujemy „na sztywno": bierzemy pierwszą kwotę w PLN,
/// heurystycznie rozpoznajemy wpływy po słowach kluczowych, a jako sklep
/// pokazujemy tekst za kwotą. To tylko PROPOZYCJA — użytkownik i tak
/// zatwierdza wpis w formularzu.
class BankNotificationParser {
  const BankNotificationParser._();

  static final _amountRe = RegExp(
    r'(\d{1,3}(?:[\s.]\d{3})*|\d+)[,.](\d{2})\s*(?:zł|PLN)',
    caseSensitive: false,
  );

  static const _incomeMarkers = [
    'przelew przychodz',
    'otrzym',
    'wpłyn',
    'wplyn',
    'wpływ',
    'wplyw',
    'zasilenie',
    'zwrot',
  ];

  static BankSuggestion? parse({
    required String bank,
    required String? title,
    required String? content,
  }) {
    final text = [title, content]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    if (text.isEmpty) return null;

    final match = _amountRe.firstMatch(text);
    if (match == null) return null;
    final whole = match.group(1)!.replaceAll(RegExp(r'[\s.]'), '');
    final cents = int.parse(whole) * 100 + int.parse(match.group(2)!);
    if (cents <= 0) return null;

    final lower = text.toLowerCase();
    final isIncome = _incomeMarkers.any(lower.contains);

    // Sklep: tekst za kwotą (tam banki zwykle wstawiają odbiorcę),
    // z fallbackiem na tekst przed kwotą i nazwę banku.
    var merchant = text
        .substring(match.end)
        .replaceAll(RegExp(r'^[\s,;:·\-–—]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (merchant.isEmpty) {
      merchant =
          text.substring(0, match.start).replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if (merchant.isEmpty) merchant = bank;
    if (merchant.length > 80) merchant = merchant.substring(0, 80);

    return BankSuggestion(
      id: const Uuid().v4(),
      bank: bank,
      merchant: merchant,
      amountCents: cents,
      type: isIncome ? TransactionType.income : TransactionType.expense,
      capturedAt: DateTime.now(),
    );
  }
}

/// Kolejka propozycji — trzymana lokalnie na telefonie (SharedPreferences),
/// max [BankSuggestionsNotifier.maxSuggestions] najnowszych. Propozycja
/// znika po dodaniu wpisu albo ręcznym odrzuceniu.
final bankSuggestionsProvider =
    NotifierProvider<BankSuggestionsNotifier, List<BankSuggestion>>(
  BankSuggestionsNotifier.new,
);

class BankSuggestionsNotifier extends Notifier<List<BankSuggestion>> {
  static const _prefsKey = 'bank_suggestions';
  static const maxSuggestions = 20;

  @override
  List<BankSuggestion> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? const [];
      final loaded = [
        for (final s in raw)
          BankSuggestion.fromJson(jsonDecode(s) as Map<String, dynamic>),
      ];
      // Merge zamiast nadpisania — nasłuch mógł dorzucić propozycję,
      // zanim skończył się odczyt z dysku; nie wolno jej zgubić.
      final knownIds = {for (final s in state) s.id};
      state = [
        ...state,
        ...loaded.where((s) => !knownIds.contains(s.id)),
      ].take(maxSuggestions).toList();
    } on Object catch (e) {
      debugPrint('bank_suggestions load: $e');
    }
  }

  Future<void> add(BankSuggestion suggestion) async {
    // Anty-dublet: ta sama kwota w oknie 10 minut = jedna propozycja.
    // Celowo BEZ porównywania sklepu — o jednej płatności zbliżeniowej
    // potrafią powiadomić dwie aplikacje naraz (bank i Portfel Google),
    // każda innym tekstem. Koszt kompromisu: dwie RÓŻNE płatności na
    // identyczną kwotę w 10 minut dadzą jedną propozycję — drugą można
    // dodać ręcznie; podwójny wpis w budżecie byłby gorszy.
    final duplicate = state.any(
      (s) =>
          s.amountCents == suggestion.amountCents &&
          suggestion.capturedAt.difference(s.capturedAt).inMinutes.abs() < 10,
    );
    if (duplicate) return;
    state = [suggestion, ...state].take(maxSuggestions).toList();
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsKey,
        [for (final s in state) jsonEncode(s.toJson())],
      );
    } on Object catch (e) {
      debugPrint('bank_suggestions persist: $e');
    }
  }
}

/// Włącznik nasłuchu powiadomień bankowych (beta). Domyślnie WYŁĄCZONY —
/// wymaga świadomej zgody + systemowego dostępu do powiadomień.
final bankListenerEnabledProvider =
    NotifierProvider<BankListenerEnabledNotifier, bool>(
  BankListenerEnabledNotifier.new,
);

class BankListenerEnabledNotifier extends Notifier<bool> {
  static const _prefsKey = 'bank_listener_enabled';

  @override
  bool build() {
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_prefsKey) ?? false;
    } on Object {
      state = false;
    }
    await ref.read(bankListenerControllerProvider).syncWithSettings();
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, enabled);
    } on Object {
      // brak persystencji = przełącznik wróci po restarcie; nie blokujemy
    }
    await ref.read(bankListenerControllerProvider).syncWithSettings();
  }
}

/// Kontroler subskrypcji strumienia powiadomień — startuje/zatrzymuje
/// nasłuch zgodnie z przełącznikiem i systemowym pozwoleniem.
final bankListenerControllerProvider = Provider<BankListenerController>((ref) {
  final controller = BankListenerController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

class BankListenerController {
  BankListenerController(this._ref);

  final Ref _ref;
  StreamSubscription<ServiceNotificationEvent>? _sub;

  /// Czy systemowy dostęp do powiadomień jest nadany.
  Future<bool> isPermissionGranted() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await NotificationListenerService.isPermissionGranted();
    } on Object {
      return false;
    }
  }

  /// Otwiera systemowy ekran nadawania dostępu do powiadomień.
  Future<bool> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await NotificationListenerService.requestPermission();
    } on Object {
      return false;
    }
  }

  Future<void> syncWithSettings() async {
    final enabled = _ref.read(bankListenerEnabledProvider);
    if (!enabled) {
      await _sub?.cancel();
      _sub = null;
      return;
    }
    if (_sub != null) return;
    if (!await isPermissionGranted()) return;
    _sub = NotificationListenerService.notificationsStream.listen(
      _onEvent,
      // Zerwany kanał nie może ubić apki — nasłuch to bonus.
      onError: (Object e, StackTrace _) => debugPrint('bank listener: $e'),
    );
  }

  void _onEvent(ServiceNotificationEvent event) {
    if (event.hasRemoved) return;
    final bank = kBankPackages[event.packageName];
    if (bank == null) return;
    final suggestion = BankNotificationParser.parse(
      bank: bank,
      title: event.title,
      content: event.content,
    );
    if (suggestion == null) return;
    unawaited(_ref.read(bankSuggestionsProvider.notifier).add(suggestion));
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
