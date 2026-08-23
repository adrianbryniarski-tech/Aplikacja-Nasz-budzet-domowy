# Nasz budżet domowy — wskazówki dla Claude

## Zasady pracy

- **Po każdej zmergowanej aktualizacji aplikacji dostarcz użytkownikowi
  APK.** Merge do maina zmian w `lib/**` sam uruchamia workflow „Build
  APK" (release, split-per-abi), który podpina surowy plik pod stały
  link: https://github.com/adrianbryniarski-tech/Aplikacja-Nasz-budzet-domowy/releases/latest/download/nasz-budzet-domowy.apk
  — poczekaj na koniec builda, ZWERYFIKUJ plik (pobierz przez proxy;
  host release'ów objects.githubusercontent.com jest przepuszczany,
  Azure blob artefaktów NIE) i wyślij użytkownikowi stały link z
  rozmiarem pliku. Bez proszenia.

- **Pomoc w apce musi nadążać za funkcjami.** Przy dodawaniu nowej funkcji
  lub zmianie istniejącej zawsze sprawdź i zaktualizuj ekran Pomocy:
  `lib/features/onboarding/presentation/help_screen.dart`
  (sekcje `_HelpSection` z krokami). Jeśli funkcja zmienia sposób obsługi
  (np. „model głosu pobierasz w Ustawieniach"), popraw też odpowiednie
  kroki, nie tylko dodawaj nowe.

- **Po każdej zmianie funkcji dopisz wpis „Co nowego".** Nowy
  `ChangelogEntry` na górze listy w
  `lib/features/onboarding/data/changelog.dart` — krótko, nietechnicznym
  językiem (to czyta rodzina). Ustaw nowy unikalny `version`, żeby okienko
  „Co nowego" pokazało się raz po aktualizacji.

## Przed zakończeniem zadania

- `flutter analyze --no-pub` — czysto.
- `flutter test --no-pub` — zielone (znany flaky: `pending_ops_dao_test`
  `watchForHousehold` — przechodzi w izolacji).
- Zmiany schematu bazy → nowa migracja w `supabase/migrations/` z kolejnym
  numerem; nie edytuj już zaaplikowanych migracji.
- Po zmianie migracji / RLS / RPC uruchom testy bazy na prawdziwych
  migracjach: `bash supabase/test/run_db_tests.sh --local` (te same testy
  odpala CI w jobie „DB tests"). Asercje w `supabase/test/tests/*.sql`.
