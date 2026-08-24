// Multi-line stringi w listach `steps` są intencjonalne (długi tekst
// instrukcji łamany dla limitu 80 znaków) — wyłączamy regułę adjacent
// strings dla tego pliku.
// ignore_for_file: no_adjacent_strings_in_list

import 'package:flutter/material.dart';
import 'package:nasz_budzet_domowy/shared/widgets/comic_shadow.dart';

/// Statyczny ekran pomocy — instrukcje krok-po-kroku. Dostępny zawsze
/// z Ustawień. Cel: żeby właściciel apki nie musiał każdej nowej osobie
/// tłumaczyć "jak połączyć z partnerem" itd.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pomoc')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: const [
          _HelpSection(
            emoji: '🤝',
            title: 'Jak połączyć się z partnerem/ką',
            steps: [
              'TY (pierwsza osoba): na ekranie startowym wybierz '
                  '„Stwórz nowe gospodarstwo", nadaj nazwę.',
              'Dostaniesz 6-znakowy kod (np. ABC-XYZ). Skopiuj go.',
              'Wyślij kod partnerowi (SMS, Telegram, cokolwiek).',
              'PARTNER: instaluje tę samą apkę, zakłada konto na swój '
                  'email + hasło.',
              'Na ekranie startowym wybiera „Mam kod zaproszenia", '
                  'wpisuje Twój kod → „Dołącz".',
              'Gotowe — od teraz widzicie te same transakcje na obu '
                  'telefonach, na żywo.',
            ],
          ),
          _HelpSection(
            emoji: '🔑',
            title: 'Gdzie znaleźć kod zaproszenia później',
            steps: [
              'Zakładka „Pulpit" (pierwsza na dolnym pasku).',
              'Ikona 👤+ w prawym górnym rogu.',
              'Pokaże aktualny kod + przycisk „Kopiuj". Możesz też '
                  'wygenerować nowy.',
            ],
          ),
          _HelpSection(
            emoji: '📧',
            title: 'Kto jest w gospodarstwie (i na jaki email)',
            steps: [
              'Ustawienia → karta „Gospodarstwo".',
              'W sekcji „Członkowie" zobaczysz adresy e-mail wszystkich '
                  'osób w gospodarstwie — przyda się, gdy ktoś zapomni, na '
                  'jaki email się logował.',
            ],
          ),
          _HelpSection(
            emoji: '🔒',
            title: 'Nie pamiętasz hasła',
            steps: [
              'Na ekranie logowania stuknij „Nie pamiętam hasła".',
              'Podaj email konta → przyjdzie 6-cyfrowy kod na maila.',
              'Wpisz kod i ustaw nowe hasło. Po tym jesteś od razu '
                  'zalogowany(a).',
              'Nie znasz emaila? Druga osoba w gospodarstwie sprawdzi go '
                  'w Ustawieniach → Gospodarstwo → Członkowie.',
            ],
          ),
          _HelpSection(
            emoji: '➕',
            title: 'Jak dodać wydatek / dochód',
            steps: [
              'Stuknij duży przycisk + (prawy dolny róg).',
              'Wybierz Wydatek lub Dochód.',
              'Wpisz kwotę. Nad listą kategorii są chipy z Waszymi '
                  'najczęstszymi kategoriami — jeden tap zamiast szukania '
                  'w liście.',
              'Sprawdź datę (domyślnie dziś), opcjonalnie dodaj opis. '
                  'Stuknij „Zapisz".',
            ],
          ),
          _HelpSection(
            emoji: '✏️',
            title: 'Jak poprawić wpis (edycja)',
            steps: [
              'Na liście transakcji stuknij wpis, który chcesz poprawić.',
              'Otworzy się formularz z wypełnionymi polami — zmień kwotę, '
                  'kategorię, datę, opis albo notatkę i stuknij „Zapisz".',
              'Wpis z ikoną zegarka (⏳) czeka na synchronizację — edycja '
                  'będzie możliwa, gdy się wyśle.',
            ],
          ),
          _HelpSection(
            emoji: '🔍',
            title: 'Szukanie na liście transakcji',
            steps: [
              'Zakładka „Transakcje" → ikona lupy u góry.',
              'Wpisz fragment: nazwę sklepu, opis, notatkę albo nazwę '
                  'kategorii (np. „biedronka" albo „transport").',
              'Chipami zawęzisz do samych wydatków albo dochodów.',
              'Zamknięcie lupy czyści szukanie i pokazuje całą listę.',
            ],
          ),
          _HelpSection(
            emoji: '📊',
            title: 'Pulpit — co widać na głównym ekranie',
            steps: [
              'Pulpit to Wasz szybki podgląd pieniędzy w wybranym okresie.',
              'Na górze wybierasz okres (ten miesiąc, 3 miesiące, rok…) — '
                  'wszystkie wykresy dopasowują się do niego. Pod chipami '
                  'widać napis „Pokazuję: …" z dokładnym zakresem dat, więc '
                  'zawsze wiesz, co liczysz.',
              '„Własny" otwiera kalendarz — zaznacz pierwszy i ostatni dzień '
                  '(np. jeden tydzień), a pulpit policzy tylko ten przedział. '
                  'Wybrane daty pokażą się wprost na chipie.',
              'Saldo = dochody minus wydatki. Kolor/strzałka pokazuje, czy '
                  'jest lepiej czy gorzej niż w poprzednim takim okresie.',
              'Sekcja „Wydatki wg kategorii" pokazuje, na co idą pieniądze — '
                  'każda kategoria z kwotą i udziałem (%). Wydatki '
                  'podkategorii liczą się do kategorii głównej.',
              'Słupki i linia pokazują wpływy/wydatki oraz jak rosło lub '
                  'malało saldo w czasie.',
              'Wydatki wg kategorii (i wykorzystanie limitów) też liczą się '
                  'dla wybranego okresu — zmień okres, a wszystko się '
                  'przeliczy.',
              'Pod saldem widać też, czy wydajecie więcej czy mniej niż '
                  'w poprzednim takim okresie (np. „Wydatki −12%").',
              'Gdy jakaś kategoria zbliża się do limitu (80%) albo go '
                  'przekroczy, na górze pulpitu pojawi się żółto-czerwone '
                  'ostrzeżenie — znika, gdy wszystko jest w normie.',
            ],
          ),
          _HelpSection(
            emoji: '✨',
            title: 'Nowy pulpit (beta) — do włączenia w Ustawieniach',
            steps: [
              'Ustawienia → sekcja „Pulpit" → włącz „Nowy pulpit (beta)". '
                  'Można wrócić do klasycznego w każdej chwili — nic nie '
                  'przepada.',
              'Razem z nowym pulpitem włącza się pasujący do niego motyw '
                  '„Neo": fioletowy granat z miękkimi plamami światła, '
                  'czysta typografia Inter i pigułkowe przyciski — '
                  'najlepiej wygląda w trybie ciemnym. Po wyłączeniu '
                  'pulpitu wraca Twój poprzedni motyw, a w każdej chwili '
                  'możesz wybrać inny w sekcji Motyw.',
              'Największa karta u góry pokazuje, ILE ZOSTAŁO do wydania '
                  'w wybranym okresie, a pod spodem podpowiedź „≈ tyle '
                  'dziennie do końca okresu" — łatwiej trzymać się planu '
                  'dzień po dniu.',
              'Niżej: kafle Dochody/Wydatki (z porównaniem do poprzedniego '
                  'okresu), szybkie przyciski „Wydatek"/„Dochód"/import, '
                  'budżety z kółkiem % wykorzystania, wykres salda w czasie '
                  'i „Na co idzie najwięcej".',
              '„Nadchodzące płatności" pokazuje najbliższe transakcje '
                  'cykliczne (czynsz, abonamenty) — stuknij, by przejść do '
                  'pełnej listy.',
              '„Ostatnie transakcje" to podgląd świeżych wpisów — stuknięcie '
                  'otwiera edycję.',
              'Nowy pulpit działa w każdym motywie i trybie ciemnym — '
                  'kolory bierze z wybranego stylu.',
            ],
          ),
          _HelpSection(
            emoji: '🎤',
            title: 'Jak dodać głosem',
            steps: [
              'Najpierw w Ustawieniach → „Sterowanie głosem" pobierz '
                  'model głosu (~50 MB) — jednorazowo, najlepiej przez Wi-Fi.',
              'Na ekranie dodawania transakcji stuknij ikonę mikrofonu '
                  '(prawy górny róg) — otworzy się okienko „Dodaj głosem".',
              'Za pierwszym razem telefon zapyta o zgodę na mikrofon — '
                  'pozwól. (Jeśli wcześniej odmówiłeś: w okienku jest przycisk '
                  '„Otwórz ustawienia").',
              'Stuknij duży mikrofon i POCZEKAJ, aż zniknie kółko ładowania '
                  'i pojawi się „Słucham…" — dopiero wtedy mów (np. „50 zł '
                  'Biedronka wczoraj"). Stuknij ponownie, żeby zakończyć.',
              'Co rozumie: kwotę, datę (dziś / wczoraj / „13 marca"), sklep '
                  'lub nazwę kategorii, oraz dochód (np. „pensja 5000").',
              'Apka wypełni pola — sprawdź i zapisz.',
            ],
          ),
          _HelpSection(
            emoji: '🏦',
            title: 'Import wyciągów z banku (CSV, PDF, ZIP)',
            steps: [
              'Pobierz z banku wyciąg CSV (PKO BP — iPKO, ING — Moje ING, '
                  'Revolut) albo PDF (ING). Możesz też wziąć ZIP z wieloma '
                  'wyciągami — np. tak, jak ING wysyła je mailem.',
              'Zakładka „Transakcje" → ikona importu (strzałka z kartką) '
                  'w pasku u góry → „Wybierz pliki (CSV / PDF / ZIP)" — '
                  'możesz zaznaczyć kilka plików naraz.',
              'Apka sama rozpozna bank, rozdzieli transakcje i zaproponuje '
                  'kategorie — znane sklepy (np. Biedronka, Orlen, apteki) '
                  'rozpozna od ręki.',
              'Z PDF-ów ING apka pomija przelewy między Waszymi własnymi '
                  'kontami („Przelew własny") — to przenosiny pieniędzy, '
                  'nie wydatki. Ten sam wyciąg wrzucony dwa razy (np. '
                  'luzem i w ZIP-ie) też się nie zdubluje.',
              'Wiersze ze znakiem zapytania przejrzyj i ustaw kategorię — '
                  'apka zapamięta Twój wybór i następnym razem przypisze '
                  'ją sama.',
              'Stuknij „Zapisz". Nic się nie zdubluje — to, co już było '
                  'w budżecie, zostanie pominięte przy zapisie.',
              'Bonus: wiersze, które wyglądają na dodane wcześniej ręcznie '
                  '(ten sam dzień, kwota i typ co wpis w budżecie), apka '
                  'sama odznacza i oznacza „chyba już jest" — zaznacz je '
                  'z powrotem tylko, jeśli to naprawdę inne zakupy.',
            ],
          ),
          _HelpSection(
            emoji: '🔔',
            title: 'Propozycje z powiadomień banku (beta)',
            steps: [
              'Ustawienia → sekcja „Import z banku" → włącz „Propozycje '
                  'z powiadomień banku".',
              'Android poprosi o dostęp do powiadomień — zaznacz „Nasz '
                  'budżet domowy" na liście, która się otworzy.',
              'Gdy zapłacisz kartą — także zbliżeniowo przez Portfel '
                  'Google — na liście Transakcji pojawi się baner '
                  'z propozycją — stuknij ją, sprawdź kategorię i zapisz. '
                  'Czytamy powiadomienia Portfela Google, IKO, Moje ING '
                  'i Revoluta.',
              'Propozycje zostają na Twoim telefonie (nie w chmurze) '
                  'i znikają po zapisaniu albo odrzuceniu (X).',
              'Duble Wam nie grożą: gdy jedna osoba zapisze płatność, '
                  'u drugiej ta propozycja sama zniknie. A gdyby mimo to '
                  'ktoś dodawał drugi raz to samo (ta sama kwota tego '
                  'samego dnia), apka zapyta „ten wydatek chyba już jest".',
            ],
          ),
          _HelpSection(
            emoji: '🏷️',
            title: 'Kategorie i podkategorie',
            steps: [
              'Zakładka „Kategorie" (dolny pasek) — osobno wydatki '
                  'i dochody.',
              'Ikona + u góry → nowa kategoria (nazwa, kolor, ikona, typ).',
              'Przy każdej kategorii głównej jest „+" — dodaje podkategorię '
                  '(np. pod „Transport" → „Paliwo", „Serwis").',
              'Podkategorię wybierzesz przy dodawaniu transakcji; na wykresie '
                  'jej wydatki liczą się do kategorii głównej.',
              'Własne: stuknij by edytować, przesuń w lewo by usunąć '
                  '(z przeniesieniem transakcji). Systemowe są zablokowane.',
            ],
          ),
          _HelpSection(
            emoji: '🗑️',
            title: 'Jak usunąć pomyłkę',
            steps: [
              'Na liście transakcji przesuń wpis palcem w lewo — zniknie '
                  'od razu, bez pytania.',
              'Na dole przez kilka sekund widać „Cofnij" — stuknij, jeśli '
                  'to była pomyłka, a wpis wróci.',
            ],
          ),
          _HelpSection(
            emoji: '🔁',
            title: 'Transakcje cykliczne (czynsz, abonamenty, wypłata)',
            steps: [
              'Ustawienia → „Transakcje cykliczne" → „Dodaj".',
              'Podaj nazwę (np. Czynsz), kwotę, kategorię i dzień miesiąca.',
              'Apka sama dopisze wpis do budżetu w tym dniu — także gdy '
                  'apka była zamknięta (naliczy zaległe przy otwarciu). '
                  'W krótszych miesiącach dzień 29–31 naliczy się ostatniego '
                  'dnia.',
              'Wpis cykliczny wygląda jak zwykła transakcja (opis = nazwa '
                  'szablonu) — można go edytować i usuwać.',
              'Szablon możesz wstrzymać (⋮ → „Wstrzymaj") albo usunąć — '
                  'dotychczasowe wpisy zostają.',
            ],
          ),
          _HelpSection(
            emoji: '🎯',
            title: 'Jak ustawić budżet miesięczny',
            steps: [
              'Zakładka „Budżety" (dolny pasek).',
              'Ikona + → wybierz kategorię wydatków, wpisz kwotę.',
              'Pasek pokaże ile już wydaliście: zielony / żółty / '
                  'czerwony (przekroczone).',
            ],
          ),
          _HelpSection(
            emoji: '📈',
            title: 'Inwestycje (krypto, złoto, srebro)',
            steps: [
              'Zakładka „Inwestycje" (dolny pasek).',
              'Ikona + → wybierz krypto / złoto / srebro, podaj ilość, '
                  'datę i cenę zakupu.',
              'Cenę możesz wpisać w PLN, USD lub EUR — przeliczymy na PLN '
                  'po kursie NBP z dnia zakupu.',
              'Dokupienie tego samego aktywa scala się w jedną pozycję '
                  'ze średnią ceną zakupu.',
              'Wartość i zysk/strata liczą się po aktualnych kursach; '
                  'wykres pokazuje wartość portfela w czasie.',
              'Sprzedałeś? Stuknij pozycję → „Sprzedaj / zapisz stratę". '
                  'Możesz sprzedać całość albo część (np. pół bitcoina). '
                  'Wpisz kwotę, którą odzyskałeś — albo od razu samą stratę. '
                  'Apka policzy ostateczny wynik (zysk lub stratę) i pokaże '
                  'go w „Historii realizacji".',
              'Pomyłka? Stuknij wpis w historii → „Cofnij sprzedaż" '
                  '— ilość wróci do portfela.',
            ],
          ),
          _HelpSection(
            emoji: '🎨',
            title: 'Jak zmienić wygląd i animacje',
            steps: [
              'Zakładka „Pulpit" → ⋮ (3 kropki) → „Ustawienia".',
              'Wybierz jeden z 14 motywów (m.in. Manga — czarno-biały komiks '
                  'z własnymi ikonami, Kredka, Dragon Ball, Pokémon, Aurora) '
                  '+ tryb jasny/ciemny. Każdy ma inne kolory, czcionkę '
                  'i kształty.',
              'Niżej — włącz/wyłącz pojedyncze animacje i dźwięki, '
                  'a także delikatne wibracje przy akcjach.',
            ],
          ),
          _HelpSection(
            emoji: '🔐',
            title: 'Blokada apki (PIN / odcisk palca)',
            steps: [
              'Ustawienia → sekcja „Bezpieczeństwo" → włącz „Blokada apki".',
              'Ustaw 4–6 cyfrowy PIN (dwa razy ten sam).',
              'Od teraz przy otwarciu apki (i po 2 minutach w tle) trzeba '
                  'podać PIN. Każdy telefon ustawia własny.',
              'Jeśli telefon ma czytnik odcisku albo odblokowanie twarzą, '
                  'możesz włączyć „Odblokowanie odciskiem / twarzą" — PIN '
                  'zostaje jako zapasowy.',
              'Nie zgub PIN-u! Bez niego trzeba przeinstalować apkę '
                  '(dane budżetu są w chmurze, więc nic nie przepadnie).',
            ],
          ),
          _HelpSection(
            emoji: '🧹',
            title: 'Zacznij od nowa (reset wpisów)',
            steps: [
              'Ustawienia → sekcja „Twoje dane" → „Zacznij od nowa (usuń '
                  'wszystkie wpisy)".',
              'Usuwa WSZYSTKIE transakcje — u obojga domowników, z chmury '
                  'i z telefonów. Tego nie da się cofnąć, dlatego trzeba '
                  'przepisać słowo „KASUJĘ", zanim przycisk się odblokuje.',
              'Nietknięte zostają: inwestycje, kategorie, budżety (limity), '
                  'płatności cykliczne i nauczone kategorie importu — '
                  'zaczynacie z czystą listą, ale bez konfigurowania '
                  'wszystkiego od zera.',
              'Rada: tuż przed resetem zrób „Eksport do CSV" — zostanie '
                  'Wam kopia historii.',
            ],
          ),
          _HelpSection(
            emoji: '📤',
            title: 'Eksport do Excela (CSV)',
            steps: [
              'Ustawienia → sekcja „Twoje dane" → „Eksport do CSV (Excel)".',
              'Wybierz: ten miesiąc albo wszystkie transakcje.',
              'Telefon pokaże okno „Udostępnij" — wyślij plik na maila, '
                  'zapisz na Dysku Google albo prześlij na komputer.',
              'Plik otwiera się w Excelu / Arkuszach Google — z polskimi '
                  'znakami i kwotami z przecinkiem.',
            ],
          ),
          _HelpSection(
            emoji: '🔄',
            title: 'Coś się nie odświeża?',
            steps: [
              'Pociągnij listę palcem od góry w dół (pull-to-refresh) — '
                  'odświeży też paski budżetów i liczniki przy kategoriach.',
              'Albo stuknij ikonę 🔄 w pasku u góry.',
              'Na Inwestycjach odświeżenie pobiera świeże kursy — pod '
                  'wartością portfela widać, z której godziny są kursy.',
              'Dane synchronizują się automatycznie gdy jest internet.',
            ],
          ),
          _HelpSection(
            emoji: '📡',
            title: 'Brak internetu albo serwer nie odpowiada',
            steps: [
              'Gdy przy starcie nie ma połączenia, apka pokaże ekran '
                  '„Brak połączenia z serwerem" z przyciskiem „Spróbuj '
                  'ponownie" — zamiast kręcić kółkiem bez końca.',
              'Wydatek dodany bez internetu zapisuje się na telefonie '
                  '(ikona zegarka przy wpisie) i wyśle się sam, gdy wróci '
                  'połączenie albo gdy znów otworzysz apkę.',
              'Gdy któryś ekran nie może pobrać danych, zobaczysz krótki '
                  'opis problemu (internet czy serwer) i przycisk '
                  '„Spróbuj ponownie".',
              'Problem nie mija? Prześlij drugiej osobie tekst spod '
                  '„Szczegóły" — pomoże namierzyć przyczynę.',
            ],
          ),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.emoji,
    required this.title,
    required this.steps,
  });

  final String emoji;
  final String title;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ComicCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
