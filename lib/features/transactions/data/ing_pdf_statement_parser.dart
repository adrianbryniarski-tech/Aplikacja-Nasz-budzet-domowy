import 'package:nasz_budzet_domowy/features/transactions/data/bank_statement_parser.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Parser wyciągów PDF z ING („Wyciąg z rachunku").
///
/// ING w Moje ING wystawia miesięczne wyciągi tylko jako PDF — ten parser
/// pozwala wrzucić je do importu bez ręcznej konwersji na CSV.
///
/// Jak czytamy PDF:
/// - tekst wyciągamy w trybie layout (linie odpowiadają wierszom na
///   stronie) i normalizujemy twarde spacje (U+00A0), którymi ING
///   spaja kwoty i numery rachunków — bez tego żaden wzorzec nie trafia;
/// - transakcja = blok zaczynający się od DWÓCH kolejnych linii z datą
///   `DD.MM.YYYY` (data księgowania + data transakcji), zakończony linią
///   z kwotą `… PLN`; kwota z minusem = wydatek, bez minusa = wpływ;
/// - z bloku wyciągamy kontrahenta (po etykiecie „Nazwa i adres
///   odbiorcy/płatnika:") i tytuł, odsiewając numery rachunków, numery
///   transakcji i kody typu operacji (TR.BLIK, PRZELEW…);
/// - „Przelew własny" (między własnymi kontami ING) pomijamy — liczony
///   jako wydatek i dochód naraz zawyżyłby obie strony budżetu;
/// - na końcu sprawdzamy licznik: liczba znalezionych transakcji musi
///   zgadzać się z „Suma uznań (N)" + „Suma obciążeń (M)" z nagłówka —
///   jak się nie zgadza, wolimy odmówić niż zaimportować część.
class IngPdfStatementParser {
  const IngPdfStatementParser._();

  static final _date = RegExp(r'^\d{2}\.\d{2}\.\d{4}$');
  static final _amountEnd = RegExp(r'^(.*?)(-?\d{1,3}(?: \d{3})*,\d{2}) PLN$');
  static final _counts = RegExp(r'Suma (?:uznań|obciążeń) \((\d+)\)');
  static final _cpLabel =
      RegExp(r'Nazwa i adres (?:odbiorcy|płatnika):\s*(.*)');

  /// Czasownik zaczynający tytuł operacji — kończy sekcję kontrahenta.
  static final _titleVerb = RegExp(
    '^(?:Płatność|Przelew|Zakup|Wypłata|Prowizja|Opłata|Zwrot|'
    'Wynagrodzenie|Odsetki|Podatek|Zasilenie|Spłata|Moneyback|'
    'Kapitalizacja)',
  );

  /// Śmieci w treści bloku: numery rachunków, id transakcji, kody
  /// typu operacji, maskowane telefony, echo nadawcy („Od JAN KOWALSKI").
  static final _accountNumber = RegExp(r'^[\d ]{20,}$');
  static final _transactionId = RegExp(r'^\d{10,}$');
  static final _nrTransakcji = RegExp(r'^Nr transakcji( \d+)?$');
  static final _maskedPhone = RegExp(r'^\+?48?x+\d+$');
  static final _senderEcho = RegExp(r'^Od [A-ZĄĆĘŁŃÓŚŹŻ][A-ZĄĆĘŁŃÓŚŹŻ .-]+$');
  static const _junkCodes = {
    'TR.BLIK',
    'P .BLIK',
    'P.BLIK',
    'PRZELEW',
    'TR.KART',
    'ZLECENIE',
  };

  /// Powtórzony nagłówek tabeli po złamaniu strony — pomijamy też
  /// w środku bloku (gdyby ING kiedyś przełamał transakcję między strony).
  static final _pageJunk = RegExp(
    r'^(?:Strona \d+ z \d+.*|Data księgowania/?|Data transakcji|'
    r'Dane kontrahenta.*)$',
  );

  /// Stopka pod tabelą — twardy koniec transakcji.
  static const _footer = [
    'Środki pieniężne zgromadzone',
    'Dokument sporządzony',
    'Wygenerowano',
  ];

  /// Parsuje bajty pliku PDF. Rzuca [StatementParseException] po polsku,
  /// gdy plik nie jest wyciągiem ING albo nie daje się pewnie odczytać.
  static StatementParseResult parsePdf(List<int> bytes) {
    String text;
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      text = PdfTextExtractor(document).extractText(layoutText: true);
    } on Object {
      throw const StatementParseException(
        'Nie udało się odczytać tekstu z tego PDF-a. Obsługuję wyciągi '
        'z Moje ING („Wyciąg z rachunku") — nie skany ani inne dokumenty.',
      );
    } finally {
      document?.dispose();
    }
    return parseText(text);
  }

  /// Parsuje już wyciągnięty tekst (rozdzielone dla testów).
  static StatementParseResult parseText(String raw) {
    // Twarde spacje (U+00A0) → zwykłe, inaczej wzorce kwot nie trafiają.
    final text = raw.replaceAll('\u00A0', ' ');
    final countMatches = _counts.allMatches(text).toList();
    if (!text.contains('Wyciąg z rachunku') || countMatches.isEmpty) {
      throw const StatementParseException(
        'Ten PDF nie wygląda na wyciąg z ING. Z PDF-ów czytam na razie '
        'tylko wyciągi z Moje ING — z innych banków pobierz CSV.',
      );
    }
    final expected = countMatches.fold<int>(
      0,
      (sum, m) => sum + int.parse(m.group(1)!),
    );

    final lines = [for (final l in text.split('\n')) l.trimRight()];
    final entries = <StatementEntry>[];
    var internal = 0;

    var i = 0;
    while (i < lines.length - 1) {
      if (!_date.hasMatch(lines[i].trim()) ||
          !_date.hasMatch(lines[i + 1].trim())) {
        i++;
        continue;
      }
      final txDate = lines[i + 1].trim();
      final block = <String>[];
      String? amount;
      var j = i + 2;
      while (j < lines.length) {
        final s = lines[j].trim();
        if (_footer.any(s.startsWith)) break;
        if (_pageJunk.hasMatch(s)) {
          j++;
          continue;
        }
        // Kolejny blok zaczął się bez kwoty — coś nie tak, przerywamy.
        if (_date.hasMatch(s) &&
            j + 1 < lines.length &&
            _date.hasMatch(lines[j + 1].trim())) {
          break;
        }
        final m = _amountEnd.firstMatch(s);
        if (m != null) {
          final prefix = m.group(1)!.trim();
          if (prefix.isNotEmpty) block.add(prefix);
          amount = m.group(2);
          j++;
          break;
        }
        block.add(s);
        j++;
      }
      if (amount != null) {
        final entry = _entryFromBlock(txDate, block, amount);
        if (entry == null) {
          internal++;
        } else {
          entries.add(entry);
        }
      }
      i = j;
    }

    final got = entries.length + internal;
    if (got != expected) {
      throw StatementParseException(
        'Według nagłówka wyciąg ma $expected transakcji, a odczytałem '
        '$got — nie importuję, żeby niczego nie zgubić. Pobierz ten '
        'okres jako CSV z Moje ING i zaimportuj CSV.',
      );
    }

    return StatementParseResult(
      bank: 'ING (PDF)',
      entries: entries,
      skippedInternal: internal,
    );
  }

  /// Buduje wpis z bloku; `null` = przelew własny (pomijamy).
  static StatementEntry? _entryFromBlock(
    String txDate,
    List<String> block,
    String amount,
  ) {
    // Kontrahent: wartość po etykiecie + kolejne linie, aż zacznie się
    // tytuł operacji (linia od czasownika typu „Płatność…"/„Przelew…").
    final counterparty = <String>[];
    final rest = <String>[];
    var cpMode = false;
    for (final line in block) {
      final lm = _cpLabel.firstMatch(line);
      if (lm != null) {
        cpMode = true;
        final tail = lm.group(1)!.trim();
        if (tail.isNotEmpty) counterparty.add(tail);
        continue;
      }
      if (cpMode && _titleVerb.hasMatch(line)) cpMode = false;
      if (cpMode) {
        counterparty.add(line);
      } else {
        rest.add(line);
      }
    }
    var cp = _clean(counterparty);
    var title = _clean(rest);
    if (cp.length > 70) cp = cp.substring(0, 70);
    if (title.length > 90) title = title.substring(0, 90);

    if (title.contains('Przelew własny') || cp.contains('Przelew własny')) {
      return null;
    }

    final parts = txDate.split('.');
    final date = DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
    final cents =
        BankStatementParser.parseAmountCents(amount.replaceAll(' ', ''))!;
    var description = '$cp $title'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (description.length > 140) description = description.substring(0, 140);
    return StatementEntry(
      occurredAt: date,
      amountCents: cents.abs(),
      type: cents < 0 ? TransactionType.expense : TransactionType.income,
      description: description,
      source: TransactionSource.pdfImport,
    );
  }

  static String _clean(List<String> lines) {
    final kept = [for (final l in lines.where(_isNotJunk)) l.trim()];
    return kept.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _isNotJunk(String line) {
    final s = line.trim();
    if (s.isEmpty) return false;
    if (_accountNumber.hasMatch(s)) return false;
    if (_transactionId.hasMatch(s)) return false;
    if (_nrTransakcji.hasMatch(s)) return false;
    if (_junkCodes.contains(s)) return false;
    if (_maskedPhone.hasMatch(s)) return false;
    if (_senderEcho.hasMatch(s)) return false;
    return true;
  }
}
