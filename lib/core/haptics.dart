import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Delikatna haptyka przy kluczowych akcjach (zapis, usunięcie, zmiana
/// zakładki). Nowoczesny „namacalny" feel — do wyłączenia w Ustawieniach
/// (sekcja Animacje), bo nie każdy lubi wibracje.
final hapticsEnabledProvider = NotifierProvider<HapticsEnabledNotifier, bool>(
  HapticsEnabledNotifier.new,
);

class HapticsEnabledNotifier extends Notifier<bool> {
  static const _prefsKey = 'haptics_enabled';

  @override
  bool build() {
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_prefsKey) ?? true;
    } on Object {
      state = true;
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, enabled);
    } on Object {
      // Brak persystencji — przełącznik wróci po restarcie; nie blokujemy.
    }
  }
}

/// Fasada na [HapticFeedback] respektująca przełącznik użytkownika.
final hapticsProvider = Provider<Haptics>(Haptics.new);

class Haptics {
  const Haptics(this._ref);

  final Ref _ref;

  bool get _on => !kIsWeb && _ref.read(hapticsEnabledProvider);

  /// Lekki „klik" — zmiana zakładki, wybór chipa.
  void tap() {
    if (_on) unawaited(HapticFeedback.selectionClick());
  }

  /// Potwierdzenie akcji — zapis transakcji, przywrócenie.
  void success() {
    if (_on) unawaited(HapticFeedback.lightImpact());
  }

  /// Mocniejsze zdarzenie — usunięcie wpisu.
  void impact() {
    if (_on) unawaited(HapticFeedback.mediumImpact());
  }
}
