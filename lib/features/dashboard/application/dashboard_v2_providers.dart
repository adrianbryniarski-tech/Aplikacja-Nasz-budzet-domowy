import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/features/settings/application/theme_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Przełącznik „Nowy pulpit" (Ustawienia → Pulpit).
///
/// Świeży układ pulpitu w stylu bento (2026): karta-bohater „zostało do
/// wydania" z podpowiedzią dzienną, pary małych kafli, ring budżetów,
/// trend, top kategorie, nadchodzące płatności i ostatnie transakcje.
/// Domyślnie WYŁĄCZONY — klasyczny pulpit zostaje, każdy wybiera sam.
///
/// Włączenie przełącza też motyw na „Neo" (zaprojektowany w parze
/// z nowym pulpitem), zapamiętując poprzedni wybór — wyłączenie go
/// przywraca. Motyw można potem normalnie zmienić w sekcji Motyw.
final dashboardV2EnabledProvider =
    NotifierProvider<DashboardV2EnabledNotifier, bool>(
  DashboardV2EnabledNotifier.new,
);

class DashboardV2EnabledNotifier extends Notifier<bool> {
  static const _prefsKey = 'dashboard_v2_enabled';

  /// Motyw sprzed włączenia nowego pulpitu — do przywrócenia.
  static const _prevThemeKey = 'dashboard_v2_prev_theme';

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
      await _syncTheme(prefs, enabled: enabled);
    } on Object {
      // Brak persystencji — wybór wróci po restarcie; nie blokujemy.
    }
  }

  /// Nowy pulpit chodzi w parze z motywem „Neo": przy włączeniu
  /// zapamiętujemy dotychczasowy motyw i przełączamy na Neo, przy
  /// wyłączeniu przywracamy zapamiętany. Gdy użytkownik w międzyczasie
  /// wybrał ręcznie inny motyw — szanujemy jego wybór i nic nie ruszamy.
  Future<void> _syncTheme(
    SharedPreferences prefs, {
    required bool enabled,
  }) async {
    final themeNotifier = ref.read(themeVariantProvider.notifier);
    final current = ref.read(themeVariantProvider);
    if (enabled) {
      if (current != AppThemeVariant.neo) {
        await prefs.setString(_prevThemeKey, current.name);
        await themeNotifier.set(AppThemeVariant.neo);
      }
    } else {
      final prevName = prefs.getString(_prevThemeKey);
      await prefs.remove(_prevThemeKey);
      if (current == AppThemeVariant.neo && prevName != null) {
        final prev = AppThemeVariant.values.firstWhere(
          (v) => v.name == prevName,
          orElse: () => AppThemeVariant.spokojny,
        );
        await themeNotifier.set(prev);
      }
    }
  }
}
