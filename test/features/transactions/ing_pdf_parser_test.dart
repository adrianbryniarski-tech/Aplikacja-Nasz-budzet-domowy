import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/bank_statement_parser.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/ing_pdf_statement_parser.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

/// Syntetyczny tekst w strukturze, jaką daje ekstrakcja layoutowa
/// wyciągu ING (zweryfikowana na prawdziwych plikach): metadane,
/// „Suma uznań/obciążeń (N)", bloki transakcji od dwóch linii z datami,
/// kwota `… PLN` na końcu bloku, powtórzone nagłówki po złamaniu strony,
/// stopka. Twarde spacje (U+00A0) celowo w kwotach — jak w oryginale.
String _statement({String uznania = '1', String obciazenia = '3'}) => [
      'Nr: 1 / 01.03.2026 - 31.03.2026',
      'Wyciąg z rachunku',
      'Dane posiadaczaDane rachunku',
      'JAN PRZYKŁADOWY',
      'Nazwa rachunku:',
      'KONTO Testowe',
      'Saldo początkowe:',
      '1\u00A0000,00 PLN',
      'Suma uznań ($uznania):',
      '5\u00A0000,00 PLN',
      'Suma obciążeń ($obciazenia):',
      '1\u00A0434,56 PLN',
      'Data księgowania/',
      'Data transakcji',
      'Dane kontrahentaTytułSzczegóły / nr transakcjiKwota',
      ' ',
      // Wydatek BLIK: kontrahent po etykiecie (część w tej samej linii),
      // śmieci: numer rachunku, „Nr transakcji", kod TR.BLIK, id.
      '02.03.2026',
      '01.03.2026',
      '79 1050 0028 1000 0024 1009 3963',
      'Nazwa i adres odbiorcy: JMP S.A.',
      'BIEDRONKA WARSZAWA ',
      'Płatność BLIK 01.03.2026',
      'Nr transakcji 92656839693',
      'TR.BLIK',
      '202535464020084763',
      '-234,56 PLN',
      // Wpływ: etykieta bez treści w linii, echo nadawcy („Od ANNA…"),
      // maskowany telefon, kod P .BLIK, kwota z twardą spacją.
      '03.03.2026',
      '03.03.2026',
      'Nazwa i adres płatnika:',
      'FIRMA KRZAK SP. Z O.O.',
      'Przelew BLIK otrzymany',
      'Od ANNA TESTOWA',
      '+48xxx123',
      'P .BLIK',
      '202588888888888888',
      '5\u00A0000,00 PLN',
      // Przelew własny → pomijany (przenosiny między swoimi kontami).
      '05.03.2026',
      '05.03.2026',
      'Nazwa i adres odbiorcy:',
      'JAN PRZYKŁADOWY',
      'Przelew własny na oszczędności',
      'PRZELEW',
      '202599999999999999',
      '-1\u00A0000,00 PLN',
      // Wydatek kartą ze złamaniem strony W ŚRODKU bloku i kwotą
      // poprzedzoną tekstem w tej samej linii.
      '08.03.2026',
      '08.03.2026',
      'Nazwa i adres odbiorcy: SKLEP ABC',
      'Zakup kartą 08.03.2026',
      'Strona 1 z 2. Wyciąg z rachunku',
      'Data księgowania/',
      'Data transakcji',
      'Dane kontrahentaTytułSzczegóły / nr transakcjiKwota',
      ' ',
      'TR.KART',
      'Nr ref 55 -200,00 PLN',
      'Środki pieniężne zgromadzone na rachunku bankowym podlegają ochronie',
      'ING Bank Śląski S.A. z siedzibą w Katowicach',
      'Strona 2 z 2. Wyciąg z rachunku',
    ].join('\n');

void main() {
  group('IngPdfStatementParser.parseText', () {
    test('czyta bloki, filtruje śmieci, pomija przelew własny', () {
      final result = IngPdfStatementParser.parseText(_statement());

      expect(result.bank, 'ING (PDF)');
      expect(result.entries, hasLength(3));
      expect(result.skippedInternal, 1);
      expect(result.skippedNonPln, 0);
      expect(result.skippedOther, 0);

      final blik = result.entries[0];
      // Data transakcji = DRUGA linia z datą (pierwsza to księgowanie).
      expect(blik.occurredAt, DateTime(2026, 3));
      expect(blik.amountCents, 23456);
      expect(blik.type, TransactionType.expense);
      expect(
        blik.description,
        'JMP S.A. BIEDRONKA WARSZAWA Płatność BLIK 01.03.2026',
      );
      expect(blik.source, TransactionSource.pdfImport);

      final wplyw = result.entries[1];
      expect(wplyw.occurredAt, DateTime(2026, 3, 3));
      expect(wplyw.amountCents, 500000); // twarda spacja znormalizowana
      expect(wplyw.type, TransactionType.income);
      expect(
        wplyw.description,
        'FIRMA KRZAK SP. Z O.O. Przelew BLIK otrzymany',
      );

      final karta = result.entries[2];
      expect(karta.occurredAt, DateTime(2026, 3, 8));
      expect(karta.amountCents, 20000);
      expect(karta.type, TransactionType.expense);
      // Złamanie strony w środku bloku nie psuje transakcji, a tekst
      // sprzed kwoty w tej samej linii dokleja się do tytułu.
      expect(karta.description, 'SKLEP ABC Zakup kartą 08.03.2026 Nr ref 55');
    });

    test('w opisach nie ma śmieci (kody, numery, echo nadawcy)', () {
      final result = IngPdfStatementParser.parseText(_statement());
      final all = result.entries.map((e) => e.description).join(' | ');
      expect(all, isNot(contains('TR.BLIK')));
      expect(all, isNot(contains('P .BLIK')));
      expect(all, isNot(contains('TR.KART')));
      expect(all, isNot(contains('Nr transakcji')));
      expect(all, isNot(contains('202535464020084763')));
      expect(all, isNot(contains('79 1050')));
      expect(all, isNot(contains('Od ANNA TESTOWA')));
      expect(all, isNot(contains('+48xxx123')));
    });

    test('licznik z nagłówka nie zgadza się → odmowa importu', () {
      expect(
        () => IngPdfStatementParser.parseText(_statement(uznania: '2')),
        throwsA(
          isA<StatementParseException>().having(
            (e) => e.message,
            'message',
            contains('nie importuję'),
          ),
        ),
      );
    });

    test('PDF niebędący wyciągiem ING → czytelny błąd', () {
      expect(
        () => IngPdfStatementParser.parseText('Faktura VAT 12/2026\nRazem'),
        throwsA(
          isA<StatementParseException>().having(
            (e) => e.message,
            'message',
            contains('nie wygląda na wyciąg z ING'),
          ),
        ),
      );
    });

    test('wyciąg bez transakcji (0 uznań, 0 obciążeń) → pusta lista', () {
      final result = IngPdfStatementParser.parseText(
        [
          'Wyciąg z rachunku',
          'Suma uznań (0):',
          '0,00 PLN',
          'Suma obciążeń (0):',
          '0,00 PLN',
          'Środki pieniężne zgromadzone na rachunku',
        ].join('\n'),
      );
      expect(result.entries, isEmpty);
      expect(result.skippedInternal, 0);
    });
  });
}
