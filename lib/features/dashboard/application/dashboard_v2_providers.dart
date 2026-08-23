import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Przełącznik „Nowy pulpit" (Ustawienia → Pulpit).
///
/// Świeży układ pulpitu w stylu bento (2026): karta-bohater „zostało do
/// wydania" z podpowiedzią dzienną, pary małych kafli, ring budżetów,
/// trend, top kategorie, nadchodzące płatności i ostatnie transakcje.
/// Domyślnie WYŁĄCZONY — klasyczny pulpit zostaje, każdy wybiera sam.
final dashboardV2EnabledProvider =
    NotifierProvider<DashboardV2EnabledNotifier, bool>(
  DashboardV2EnabledNotifier.new,
);

class DashboardV2EnabledNotifier extends Notifier<bool> {
  static const _prefsKey = 'dashboard_v2_enabled';

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
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, enabled);
    } on Object {
      // Brak persystencji — wybór wróci po restarcie; nie blokujemy.
    }
  }
}
