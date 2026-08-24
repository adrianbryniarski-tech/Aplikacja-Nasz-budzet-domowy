// Wielolinijkowe stringi w `changes` są celowe (długie opisy łamane do 80
// znaków) — wyłączamy regułę adjacent strings.
// ignore_for_file: no_adjacent_strings_in_list

/// Lista zmian „Co nowego" — najnowszy wpis na górze.
///
/// Po KAŻDEJ aktualizacji dopisz nowy [ChangelogEntry] na początku listy
/// (zwykłym, nietechnicznym językiem — to czyta rodzina, nie programista).
/// `version` musi być unikalne dla każdego wpisu — na jego podstawie apka
/// pokazuje okienko „Co nowego" raz, po wejściu do nowej wersji.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.title,
    required this.changes,
  });

  /// Unikalny klucz wpisu (np. data). Zmiana = pokaż auto-okienko raz.
  final String version;
  final String date;
  final String title;
  final List<String> changes;
}

const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    version: '2026-08-24b',
    date: '24 sierpnia 2026',
    title: 'Reset wpisów i pewniejsze aktualizacje',
    changes: [
      'W Ustawieniach (sekcja „Twoje dane") jest teraz „Zacznij od '
          'nowa" — usuwa wszystkie transakcje u obojga, gdy chcecie '
          'wystartować z czystą kartą. Inwestycje, kategorie, budżety '
          'i płatności cykliczne zostają nietknięte.',
      'Żeby nikt nie skasował budżetu przypadkiem, trzeba przepisać '
          'słowo „KASUJĘ" — dopiero wtedy przycisk się odblokuje. '
          'Przed resetem warto zrobić eksport do CSV.',
      'Każde kolejne APK ma teraz rosnący numer wersji — aktualizacja '
          'instaluje się po wierzchu niezależnie od tego, jak starą '
          'wersję ma telefon. Wystarczy ten sam stały link.',
    ],
  ),
  ChangelogEntry(
    version: '2026-08-24a',
    date: '24 sierpnia 2026',
    title: 'Nowy pulpit z prawdziwym efektem WOW',
    changes: [
      'Za kartami nowego pulpitu faluje teraz „aurora" — wielkie, '
          'powoli dryfujące plamy światła w kolorach motywu. Karty '
          'zrobiły się szklane, z cienkimi świecącymi ramkami.',
      'Saldo w wielkiej karcie jest malowane gradientem indygo→cyjan '
          'i delikatnie świeci, kwoty dochodów/wydatków mają neonową '
          'poświatę, a wokół głównej karty krąży animowana ramka.',
      'Kółko budżetów i paski kategorii świecą swoimi kolorami, linia '
          'wykresu ma poświatę, a przyciski Wydatek/Dochód dostały glow.',
      'Karty wjeżdżają na ekran jedna po drugiej przy wejściu na pulpit.',
      'Efekty widać na motywach neonowych (Neo, Cyber, Synthwave, '
          'Galaktyka) — najlepiej w trybie ciemnym. Na spokojnych '
          'motywach nowy pulpit zostaje elegancko stonowany.',
    ],
  ),
  ChangelogEntry(
    version: '2026-08-23g',
    date: '23 sierpnia 2026',
    title: 'Nowy pulpit dostał własny motyw „Neo"',
    changes: [
      'Włączenie „Nowego pulpitu (beta)" przełącza teraz całą apkę na '
          'nowy motyw „Neo" — elektryczny indygo z cyjanowym neonem, '
          'zaprojektowany w parze z nowym pulpitem. Najbardziej robi '
          'wrażenie w trybie ciemnym.',
      'Po wyłączeniu nowego pulpitu wraca Twój poprzedni motyw. '
          'A jeśli wolisz nowy pulpit w innym stylu — po prostu wybierz '
          'inny motyw w Ustawieniach, nic się nie zresetuje.',
      '„Neo" jest też dostępny jak każdy inny motyw na liście — możesz '
          'go używać także z klasycznym pulpitem.',
    ],
  ),
  ChangelogEntry(
    version: '2026-08-23f',
    date: '23 sierpnia 2026',
    title: 'Nowy pulpit do włączenia — zaprojektowany wg trendów 2026',
    changes: [
      'W Ustawieniach (sekcja „Pulpit") możesz włączyć „Nowy pulpit '
          '(beta)" — świeży wygląd głównego ekranu. Klasyczny zostaje, '
          'wracasz do niego jednym przełącznikiem.',
      'Największa karta mówi wprost, ile zostało do wydania, i podpowiada '
          '„≈ tyle dziennie do końca okresu" — bez liczenia w głowie.',
      'Do tego: szybkie przyciski Wydatek/Dochód/import, budżety z kółkiem '
          'procentów, wykres salda, „Na co idzie najwięcej", nadchodzące '
          'płatności cykliczne i ostatnie transakcje — wszystko na jednym '
          'ekranie, w kolorach Twojego motywu.',
    ],
  ),
  ChangelogEntry(
    version: '2026-08-23e',
    date: '23 sierpnia 2026',
    title: 'Wyciągi z ING wrzucasz teraz jako PDF — bez kombinowania',
    changes: [
      'Import z banku przyjmuje teraz także PDF-y z ING i ZIP-y '
          'z wyciągami w środku — dokładnie takie pliki, jakie '
          'pobierasz z Moje ING, bez żadnego przerabiania.',
      'Można wybrać kilka plików naraz — apka złoży je w jedną listę '
          'i posortuje po dacie.',
      'Przelewy między Waszymi własnymi kontami („Przelew własny") '
          'apka pomija sama — nie zawyżą wydatków ani dochodów.',
      'Ten sam wyciąg wrzucony dwa razy (np. luzem i w ZIP-ie) nie '
          'zdubluje transakcji, a apka policzy się z nagłówkiem '
          'wyciągu — jak coś się nie zgadza, powie wprost zamiast '
          'importować połowę.',
    ],
  ),
  ChangelogEntry(
    version: '2026-08-23d',
    date: '23 sierpnia 2026',
    title: 'Apka po liftingu — płynniej i nowocześniej',
    changes: [
      'Zmiana zakładki i wejście na nowy ekran są teraz płynne '
          '(delikatne przenikanie zamiast twardego cięcia) — we '
          'wszystkich motywach.',
      'Saldo, dochody i wydatki na pulpicie „doliczają się" płynnie do '
          'wartości — także po zmianie okresu.',
      'Zamiast kręcącego kółka pulpit i lista transakcji pokazują przy '
          'ładowaniu szkielet ekranu (jak w nowoczesnych apkach '
          'bankowych).',
      'Delikatne wibracje przy zapisaniu, usunięciu i zmianie zakładki '
          '— można wyłączyć w Ustawieniach → Animacje.',
      'Treść wchodzi pod przezroczysty pasek statusu (edge-to-edge) — '
          'wygląd jak w Androidzie 15.',
      'Import z banku pilnuje też wpisów dodanych wcześniej ręcznie: '
          'wiersz z tym samym dniem, kwotą i typem co coś w budżecie '
          'zostanie odznaczony z etykietą „chyba już jest" — nic nie '
          'policzy się podwójnie.',
    ],
  ),
  ChangelogEntry(
    version: '2026-08-23c',
    date: '23 sierpnia 2026',
    title: 'Wielka paczka wygody: edycja, szukajka, cykliczne, PIN…',
    changes: [
      'Wpis można wreszcie POPRAWIĆ: stukasz transakcję na liście '
          'i zmieniasz kwotę, kategorię, datę czy opis — bez kasowania '
          'i wpisywania od nowa.',
      'Lupa na liście transakcji: szukasz po sklepie, opisie, notatce '
          'albo kategorii; chipami zawężasz do wydatków lub dochodów.',
      'Usuwanie bez pytania, ale z ratunkiem: wpis znika od razu, a na '
          'dole masz kilka sekund na „Cofnij".',
      'Transakcje cykliczne: czynsz, Netflix czy wypłata dopisują się '
          'same w wybranym dniu miesiąca (Ustawienia → Transakcje '
          'cykliczne).',
      'Koniec dubli między Waszymi telefonami: gdy jedno z Was zapisze '
          'płatność z powiadomienia, u drugiej osoby propozycja sama '
          'zniknie — a przy próbie dodania tego samego wpisu apka '
          'dopyta „ten wydatek chyba już jest".',
      'Szybkie chipy kategorii na formularzu — Wasze ulubione kategorie '
          'jeden tap od ręki.',
      'Pulpit ostrzega przy 80% i 100% limitu kategorii oraz pokazuje, '
          'czy wydajecie więcej niż w poprzednim okresie.',
      'Blokada apki PIN-em (opcjonalnie odciskiem palca / twarzą) — '
          'Ustawienia → Bezpieczeństwo.',
      'Eksport transakcji do Excela (CSV) — Ustawienia → Twoje dane.',
    ],
  ),
  ChangelogEntry(
    version: '2026-08-23b',
    date: '23 sierpnia 2026',
    title: 'Import wyciągów z banku i propozycje z powiadomień',
    changes: [
      'Koniec ręcznego klepania wydatków: pobierz wyciąg CSV z banku '
          '(PKO BP, ING albo Revolut), wskaż plik w zakładce Transakcje '
          '(ikona importu u góry), a apka sama rozdzieli transakcje '
          'i zaproponuje kategorie — znane sklepy, stacje i apteki '
          'rozpozna od ręki.',
      'Apka uczy się Waszych poprawek: raz ustawisz kategorię dla '
          'sklepu, a każdy kolejny import przypisze ją automatycznie.',
      'Bez obaw o duplikaty — wpisy, które już są w budżecie (np. '
          'dodane ręcznie albo z poprzedniego wyciągu), przy imporcie '
          'zostaną pominięte.',
      'Nowość w becie: propozycje z powiadomień. Po włączeniu '
          'w Ustawieniach (sekcja „Import z banku") płatność kartą — '
          'także zbliżeniowo przez Portfel Google — od razu pojawia się '
          'jako propozycja na liście Transakcji: stukasz, sprawdzasz '
          'kategorię i zapisujesz.',
    ],
  ),
  ChangelogEntry(
    version: '2026-08-23',
    date: '23 sierpnia 2026',
    title: 'Apka nie zawiesza się, gdy nie ma internetu lub serwera',
    changes: [
      'Gdy przy starcie nie da się połączyć z serwerem, zamiast kółka '
          'kręcącego się bez końca zobaczysz jasny ekran „Brak połączenia '
          'z serwerem" z przyciskiem „Spróbuj ponownie".',
      'Błędy w całej apce mówią teraz po ludzku, co się stało (np. „Brak '
          'połączenia z internetem") i mają przycisk „Spróbuj ponownie".',
      'Zapisywanie (wydatku, budżetu, inwestycji, sprzedaży) nie może już '
          'kręcić się w nieskończoność — po kilkunastu sekundach dostaniesz '
          'komunikat, a wydatek dodany bez internetu zapisze się na '
          'telefonie i wyśle sam później, też po ponownym otwarciu apki.',
      'Odświeżanie (pociągnięcie listy) działa teraz w pełni: na Budżetach '
          'odświeża też paski wydatków, na Kategoriach liczniki, a na '
          'Inwestycjach całą zakładkę, nie tylko kursy.',
      'Pod wartością portfela widać, z której godziny są kursy („Kursy '
          'z 18:42"), a „Odśwież kursy" zawsze pobiera świeże. Nowo dodane '
          'aktywo dostaje kurs od razu.',
      'Wykres wartości portfela nie zawyża już dni po sprzedaży — '
          'automatyczny dzienny zapis liczy tylko to, co wciąż posiadamy.',
    ],
  ),
  ChangelogEntry(
    version: '2026-06-01',
    date: '1 czerwca 2026',
    title: 'Wydatki wg kategorii — z kwotami, dla wybranego okresu',
    changes: [
      'Na pulpicie widać pełny podział wydatków wg kategorii: kwota i '
          'udział (%) dla każdej kategorii. W motywie klasycznym kwoty są '
          'teraz w legendzie wykresu, a w motywie Manga jest osobny panel '
          '„Wydatki wg kategorii" (niezależny od limitów).',
      'Podział zawsze dotyczy okresu wybranego na górze — np. ustaw własny '
          'tydzień, a zobaczysz wydatki tylko z tego tygodnia.',
    ],
  ),
  ChangelogEntry(
    version: '2026-05-31',
    date: '31 maja 2026',
    title: 'Adresy członków + odzyskiwanie hasła',
    changes: [
      'W Ustawieniach → „Gospodarstwo" w sekcji „Członkowie" widać teraz '
          'adresy e-mail osób w gospodarstwie (zamiast samych '
          'identyfikatorów). Łatwo sprawdzić, na jaki email ktoś się logował.',
      'Na ekranie logowania pojawiło się „Nie pamiętam hasła" — przychodzi '
          '6-cyfrowy kod na maila, wpisujesz go i ustawiasz nowe hasło. '
          'Bez czekania na administratora.',
    ],
  ),
  ChangelogEntry(
    version: '2026-05-30',
    date: '30 maja 2026',
    title: 'Wybór okresu — czytelniej i na całym pulpicie',
    changes: [
      'Pod chipami okresu pojawił się napis „Pokazuję: …" z dokładnym '
          'zakresem dat — od razu widać, jaki okres liczysz. A gdy wybierzesz '
          '„Własny", wybrane daty pokazują się wprost na chipie.',
      'Gdy zmieniasz okres (np. „Poprzedni" miesiąc albo własny tydzień), '
          'przeliczają się WSZYSTKIE elementy — także panel „Wydatki wg '
          'kategorii" i wykorzystanie limitów (wcześniej ta część potrafiła '
          'zostać na bieżącym miesiącu).',
    ],
  ),
  ChangelogEntry(
    version: '2026-05-24',
    date: '24 maja 2026',
    title: 'Sprzedaż inwestycji i zapisywanie strat',
    changes: [
      'W „Inwestycjach" możesz teraz zapisać sprzedaż: stuknij pozycję → '
          '„Sprzedaj / zapisz stratę". Sprzedasz całość albo część (np. pół '
          'bitcoina) — reszta zostaje w portfelu.',
      'Dwa sposoby na wynik: wpisz kwotę, którą odzyskałeś (apka sama '
          'policzy zysk lub stratę), albo wpisz od razu samą stratę '
          'w złotówkach.',
      'Nowa „Historia realizacji" pokazuje każdą sprzedaż z jej wynikiem, '
          'a u góry widać łączny zrealizowany zysk lub stratę.',
      'Pomyłka? Stuknij wpis w historii i wybierz „Cofnij sprzedaż" — '
          'sprzedana ilość wróci do portfela.',
    ],
  ),
  ChangelogEntry(
    version: '2026-05-22',
    date: '22 maja 2026',
    title: 'Wygodniejszy głos, nowe wyglądy i podkategorie',
    changes: [
      'Nowy motyw „Manga": ostry czarno-biały komiks z grubymi konturami, '
          'kropkowym rastrem i własnymi komiksowymi ikonami (też kategorie '
          'i paski). Do wyboru 4 zestawy kolorów (czerwień, błękit, złoty, '
          'mięta) w Ustawieniach.',
      'Na pulpicie widać teraz wartość portfela inwestycyjnego (z zyskiem), '
          'jeśli masz jakieś inwestycje.',
      'Czytelniejszy wykres kołowy kategorii (nic nie nachodzi na tort) oraz '
          'mniejsze, zgrabniejsze kafelki wyboru motywu w Ustawieniach.',
      'Naprawiony mikrofon: apka prosi teraz o zgodę na mikrofon, a „Słucham…" '
          'pojawia się dopiero gdy mikrofon naprawdę nagrywa (wcześniej ginął '
          'początek zdania). Końcówka nagrania też nie jest już ucinana.',
      'Dodawanie głosem jest prostsze: stukasz mikrofon (nie trzeba już '
          'trzymać), a w okienku masz instrukcję i przykłady komend.',
      'Dużo płynniej: naprawiony wyciek pamięci przy dodawaniu transakcji '
          '(model głosu ładuje się raz, nie za każdym otwarciem), animowana '
          'ramka przestała kręcić się w tle bez końca, a tło i kafelki są '
          'lepiej odseparowane. Apka nie powinna już przycinać/wieszać się.',
      'Nowe wyglądy: Kredka (komiksowy — czarne kontury, kropkowy raster '
          'i twardy cień pod kartami), '
          'Plastelina i Aurora. Motywy różnią się teraz też kształtami '
          'przycisków i kart, nie tylko kolorem. Wybierzesz w Ustawieniach.',
      'Dwa motywy dla fanów anime: „Dragon Ball" (pomarańcz i energia, smocza '
          'kula w rogu) oraz „Pokémon" (błękit i Poké Ball). Każdy ma własną '
          'czcionkę i tematyczną ikonę.',
      'Podkategorie: pod kategorią główną (np. „Transport") możesz mieć '
          'podkategorie (np. „Paliwo"). Na wykresie liczą się do głównej.',
      'Nowy ekran „Co nowego" — tutaj po każdej aktualizacji zobaczysz '
          'krótko, co się zmieniło.',
    ],
  ),
];

/// Klucz najnowszego wpisu — do porównania z zapamiętanym „ostatnio widziano".
String get currentChangelogVersion => kChangelog.first.version;
