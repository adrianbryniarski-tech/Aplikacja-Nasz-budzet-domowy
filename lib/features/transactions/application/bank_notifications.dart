import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
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

/// Surowe powiadomienie — wejście dla logiki (ze strumienia na żywo
/// ALBO z panelu powiadomień przy wejściu do apki). Wydzielone, żeby
/// filtrowanie i deduplikację można było testować bez Androida.
class RawBankNotification {
  const RawBankNotification({
    required this.packageName,
    required this.id,
    required this.postTimeMs,
    required this.title,
    required this.content,
  });

  final String packageName;
  final int id;

  /// Kiedy system POKAZAŁ powiadomienie (ms epoch). Używamy tego jako
  /// godziny płatności — inaczej wpis dociągnięty wieczorem z panelu
  /// dostałby datę wejścia do apki, nie zakupu.
  final int postTimeMs;
  final String? title;
  final String? content;

  DateTime get postedAt => postTimeMs > 0
      ? DateTime.fromMillisecondsSinceEpoch(postTimeMs)
      : DateTime.now();
}

/// Klucz „to powiadomienie już przetworzyliśmy": pakiet + id + czas.
///
/// KLUCZOWE dla dociągania z panelu: powiadomienie o płatności wisi
/// w panelu godzinami, a apka zagląda tam przy każdym wejściu — bez
/// tego klucza ta sama płatność wracałaby jako nowa propozycja.
String seenKeyFor(RawBankNotification n) =>
    '${n.packageName}|${n.id}|${n.postTimeMs}';

/// Filtruje surowe powiadomienia do obsługiwanych banków, pomija już
/// przetworzone i parsuje na propozycje (z godziną z powiadomienia).
List<BankSuggestion> suggestionsFromRaw(
  List<RawBankNotification> raws,
  Set<String> seenKeys,
) {
  final out = <BankSuggestion>[];
  for (final raw in raws) {
    final bank = kBankPackages[raw.packageName];
    if (bank == null) continue;
    if (seenKeys.contains(seenKeyFor(raw))) continue;
    final suggestion = BankNotificationParser.parse(
      bank: bank,
      title: raw.title,
      content: raw.content,
      capturedAt: raw.postedAt,
    );
    if (suggestion != null) out.add(suggestion);
  }
  return out;
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

  /// Ogony powiadomień, które NIE są nazwą sklepu — ucinamy wszystko od
  /// nich w prawo („…, dostępne środki: 1 234,00 PLN").
  static const _tailMarkers = [
    'dostępne środki',
    'dostepne srodki',
    'dostępny limit',
    'dostepny limit',
    'dostępne',
    'saldo',
    'available balance',
    'nr transakcji',
    'numer transakcji',
    'nr ref',
    'referencja',
    'blokada',
  ];

  /// Maska karty w treści: „Karta ••1234", „•••• 1234", „nr karty 1234".
  static final _cardMask = RegExp(
    r'(?:karta|kartą|karty|card)?\s*(?:[•·*×]{2,}|\.{3,})\s*\d{0,4}'
    r'|nr\s+karty\s*\d+',
    caseSensitive: false,
  );

  /// Jakakolwiek kwota (druga kwota w treści to zwykle saldo).
  static final _anyAmount = RegExp(
    r'-?\d{1,3}(?:[\s.]\d{3})*[,.]\d{2}\s*(?:zł|PLN)?',
    caseSensitive: false,
  );

  static final _dateRe = RegExp(r'\b\d{1,2}[./-]\d{1,2}(?:[./-]\d{2,4})?\b');
  static final _timeRe = RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b');

  /// Czasownik/nagłówek płatności na początku — „Płatność kartą",
  /// „Zapłacono", „Zakup", „Payment", „Przelew przychodzący".
  static final _leadingVerb = RegExp(
    '^(?:zapłacono|zaplacono|płatność|platnosc|zakup|transakcja|payment|'
    r'przelew(?:\s+(?:przychodzący|przychodzacy|wychodzący|wychodzacy))?|'
    'wpłynęło|wplynelo|otrzymano|zwrot)'
    r'(?:\s+(?:kartą|karta|blik|mobilna|internetowa|zbliżeniowa|'
    'zblizeniowa|online))?',
    caseSensitive: false,
  );

  /// Przyimek/łącznik przed nazwą sklepu: „w Biedronce", „at Tesco",
  /// „od GMINA", „u fryzjera".
  static final _leadingConnector = RegExp(
    r'^(?:[\s,;:·•\-–—*/|]+|\b(?:w|we|at|in|od|do|u|dla|na|for|from)\b)+',
    caseSensitive: false,
  );

  /// Kod sklepu/terminala: „Z8134", „K.1", „T12", same cyfry.
  static final _storeCode = RegExp(
    r'^(?:[a-z]{1,2}[.]?\d{1,6}|\d+|[a-z]\.\d+)$',
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

  /// Czyści kandydata na nazwę sklepu: ucina ogon z saldem, wywala maski
  /// kart, kwoty, daty, godziny, wiodące czasowniki i przyimki oraz kody
  /// terminali. Zwraca `null`, gdy nie zostało nic sensownego.
  ///
  /// Publiczna, bo to najbardziej „zgadywana" część i chcemy ją testować
  /// na prawdziwych formatach powiadomień (IKO / ING / Wallet / Revolut).
  static String? cleanMerchant(String raw) {
    var s = raw;

    // Ogon: „…, dostępne środki: 1 234,00 PLN" → obcięty.
    final lower = s.toLowerCase();
    var cut = s.length;
    for (final marker in _tailMarkers) {
      final idx = lower.indexOf(marker);
      if (idx >= 0 && idx < cut) cut = idx;
    }
    s = s.substring(0, cut);

    s = s
        .replaceAll(_cardMask, ' ')
        .replaceAll(_anyAmount, ' ')
        .replaceAll(_dateRe, ' ')
        .replaceAll(_timeRe, ' ')
        .replaceAll(RegExp(r'\b(?:zł|PLN)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Wiodące „Płatność kartą" / „Zapłacono", potem przyimki („w", „at").
    s = s.replaceFirst(_leadingVerb, '');
    s = s.replaceFirst(_leadingConnector, '');

    // Kody terminali i osierocone cyfry (BIEDRONKA 1234 KRAKOW).
    // Interpunkcję z brzegów tokenu zdejmujemy PRZED sprawdzeniem, bo
    // w treści kody bywają przyklejone do przecinka („K.1,"). Kropek
    // w środku nie ruszamy — „SP. Z O.O." ma zostać sobą.
    final words = <String>[];
    for (final w in s.split(RegExp(r'\s+'))) {
      final bare = w.replaceAll(RegExp(r'^[,;:·•|*/-]+|[,;:·•|*/-]+$'), '');
      if (bare.isEmpty || _storeCode.hasMatch(bare)) continue;
      words.add(bare);
    }
    s = words
        .join(' ')
        .replaceAll(RegExp(r'^[\s,;:·•\-–—*/|]+|[\s,;:·•\-–—*/|]+$'), '')
        .trim();

    if (s.length < 2) return null;
    return s.length > 80 ? s.substring(0, 80) : s;
  }

  static BankSuggestion? parse({
    required String bank,
    required String? title,
    required String? content,
    DateTime? capturedAt,
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

    // Sklep: banki wstawiają odbiorcę zwykle ZA kwotą („23,50 PLN,
    // BIEDRONKA KRAKOW"), ale Portfel Google potrafi odwrotnie
    // („Biedronka · 23,50 zł"). Bierzemy pierwszego kandydata, z którego
    // po oczyszczeniu zostaje coś sensownego.
    final merchant = cleanMerchant(text.substring(match.end)) ??
        cleanMerchant(text.substring(0, match.start)) ??
        cleanMerchant(content ?? '') ??
        cleanMerchant(title ?? '') ??
        bank;

    return BankSuggestion(
      id: const Uuid().v4(),
      bank: bank,
      merchant: merchant,
      amountCents: cents,
      type: isIncome ? TransactionType.income : TransactionType.expense,
      capturedAt: capturedAt ?? DateTime.now(),
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
  static const _seenPrefsKey = 'bank_seen_notifications';
  static const maxSuggestions = 20;

  /// Ile kluczy przetworzonych powiadomień pamiętamy. 200 to z zapasem
  /// kilka dni płatności — starsze i tak wypadły już z panelu.
  static const maxSeenKeys = 200;

  /// Klucze powiadomień, z których propozycja już powstała (albo została
  /// odrzucona). Trzyma je dysk, więc dociąganie z panelu nie tworzy
  /// duplikatów po restarcie apki.
  final _seenKeys = <String>[];

  Set<String> get seenKeys => _seenKeys.toSet();

  @override
  List<BankSuggestion> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _seenKeys
        ..clear()
        ..addAll(prefs.getStringList(_seenPrefsKey) ?? const []);
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

  /// Zwraca `true` gdy propozycja faktycznie doszła (nie była dubletem).
  Future<bool> add(BankSuggestion suggestion) async {
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
    if (duplicate) return false;
    state = [suggestion, ...state].take(maxSuggestions).toList();
    await _persist();
    return true;
  }

  /// Wrzuca surowe powiadomienia (ze strumienia albo z panelu):
  /// filtruje do banków, pomija już przetworzone, dodaje propozycje.
  /// Zwraca liczbę NOWYCH propozycji — Ustawienia pokazują ją w toaście.
  Future<int> ingest(List<RawBankNotification> raws) async {
    if (raws.isEmpty) return 0;
    final fresh = suggestionsFromRaw(raws, seenKeys);
    // Klucze oznaczamy dla WSZYSTKICH powiadomień z obsługiwanych apek —
    // także tych bez kwoty (np. „Zaloguj się") — żeby nie próbować ich
    // parsować przy każdym wejściu do apki.
    for (final raw in raws) {
      if (kBankPackages.containsKey(raw.packageName)) {
        _markSeen(seenKeyFor(raw));
      }
    }
    var added = 0;
    for (final suggestion in fresh) {
      if (await add(suggestion)) added++;
    }
    await _persistSeen();
    return added;
  }

  void _markSeen(String key) {
    if (_seenKeys.contains(key)) return;
    _seenKeys.add(key);
    if (_seenKeys.length > maxSeenKeys) {
      _seenKeys.removeRange(0, _seenKeys.length - maxSeenKeys);
    }
  }

  Future<void> _persistSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenPrefsKey, _seenKeys);
    } on Object catch (e) {
      debugPrint('bank_seen persist: $e');
    }
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

/// Czy propozycja jest już zaksięgowana w budżecie gospodarstwa.
///
/// Anty-dublet MIĘDZY telefonami: o jednej płatności (wspólne konto,
/// Portfel Google) powiadomienie dostają oba telefony — każdy trzyma
/// propozycję lokalnie. Gdy jedna osoba doda wpis, u drugiej propozycja
/// ma zniknąć. `occurred_at` w bazie to sama data, więc porównujemy
/// dzień + kwotę + typ (dokładniejsze dopasowanie nie jest możliwe).
bool suggestionAlreadyBooked(BankSuggestion s, List<Transaction> txs) {
  return txs.any(
    (t) =>
        t.amountCents == s.amountCents &&
        t.type == s.type &&
        t.occurredAt.year == s.capturedAt.year &&
        t.occurredAt.month == s.capturedAt.month &&
        t.occurredAt.day == s.capturedAt.day,
  );
}

/// Propozycje z powiadomień, których NIE ma jeszcze w budżecie —
/// to je pokazuje baner i arkusz na liście transakcji.
final visibleBankSuggestionsProvider = Provider<List<BankSuggestion>>((ref) {
  final suggestions = ref.watch(bankSuggestionsProvider);
  if (suggestions.isEmpty) return const [];
  final txs = ref.watch(transactionsProvider).value ?? const <Transaction>[];
  return [
    for (final s in suggestions)
      if (!suggestionAlreadyBooked(s, txs)) s,
  ];
});

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

  /// Ten sam kanał, którego używa plugin — sięgamy po metody, których
  /// nie wystawia w Darcie (stan połączenia usługi z systemem).
  static const _channel = MethodChannel('x-slayer/notifications_channel');

  final Ref _ref;
  StreamSubscription<ServiceNotificationEvent>? _sub;

  /// Czy nasłuch jest aktywny w tej instancji apki (żywa subskrypcja).
  bool get isListening => _sub != null;

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

  /// Czy systemowa usługa nasłuchu jest PODŁĄCZONA do Androida.
  /// Dostęp nadany ≠ usługa działa: po aktualizacji apki albo po
  /// „wyczyść pamięć" system czasem nie podłącza jej z powrotem.
  Future<bool> isServiceConnected() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isServiceConnected');
      return result ?? false;
    } on Object {
      return false;
    }
  }

  /// Prosi system o ponowne podłączenie usługi (gdy dostęp jest nadany,
  /// ale usługa rozłączona).
  Future<void> reconnectService() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('reconnectService');
    } on Object catch (e) {
      debugPrint('bank listener reconnect: $e');
    }
  }

  /// DOCIĄGANIE Z PANELU POWIADOMIEŃ — sedno działania przy zamkniętej
  /// apce. Strumień na żywo działa tylko wtedy, gdy apka siedzi
  /// w pamięci (system rozgłasza powiadomienie, a odbiornik żyje razem
  /// z apką). Płatności zrobione przy zamkniętej apce przepadłyby więc
  /// bezpowrotnie — dlatego przy każdym wejściu/powrocie do apki
  /// zaglądamy do panelu powiadomień i zbieramy to, co jeszcze w nim
  /// wisi (Portfel Google i banki trzymają tam pushe do zmiecenia).
  ///
  /// Zwraca liczbę nowych propozycji.
  Future<int> catchUpFromShade() async {
    if (kIsWeb || !Platform.isAndroid) return 0;
    if (!_ref.read(bankListenerEnabledProvider)) return 0;
    if (!await isPermissionGranted()) return 0;
    try {
      final active = await NotificationListenerService.getActiveNotifications();
      final raws = [
        for (final e in active)
          RawBankNotification(
            packageName: e.packageName,
            id: e.id,
            postTimeMs: e.timestamp,
            title: e.title,
            content: e.content,
          ),
      ];
      return _ref.read(bankSuggestionsProvider.notifier).ingest(raws);
    } on Object catch (e) {
      // Usługa może być chwilowo nierozłączona/niepodłączona — to bonus,
      // nie wolno tym wywalić apki.
      debugPrint('bank listener catch-up: $e');
      return 0;
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
    // Od razu zbierz to, co wpadło, gdy apka nie działała.
    unawaited(catchUpFromShade());
  }

  void _onEvent(ServiceNotificationEvent event) {
    if (event.hasRemoved) return;
    if (!kBankPackages.containsKey(event.packageName)) return;
    // Przez `ingest`, żeby powiadomienie dostało klucz „widziane" —
    // inaczej to samo wpadłoby drugi raz przy dociąganiu z panelu.
    unawaited(
      _ref.read(bankSuggestionsProvider.notifier).ingest([
        RawBankNotification(
          packageName: event.packageName,
          id: event.id,
          postTimeMs: event.timestamp,
          title: event.title,
          content: event.content,
        ),
      ]),
    );
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
