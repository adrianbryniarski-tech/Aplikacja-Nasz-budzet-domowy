// Wielolinijkowe fragmenty CSV w listach są celowe (sklejane bez spacji,
// bo tak wyglądają wiersze wyciągów) — wyłączamy reguły adjacent strings.
// ignore_for_file: no_adjacent_strings_in_list
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/bank_statement_parser.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

void main() {
  group('BankStatementParser — PKO BP (iPKO)', () {
    final csv = [
      '"Data operacji","Data waluty","Typ transakcji","Kwota","Waluta",'
          '"Saldo po transakcji","Opis transakcji","","",""',
      '"2026-08-20","2026-08-20","Płatność kartą","-23.50","PLN","+976.50",'
          '"Płatność kartą","Tytuł: 000482771 74837383",'
          '"Lokalizacja: Adres: BIEDRONKA 123 Miasto: WARSZAWA Kraj: POLSKA",'
          '"Data i czas operacji: 2026-08-19"',
      '"2026-08-18","2026-08-18","Przelew na rachunek","+3500.00","PLN",'
          '"+1000.00","Przelew na rachunek","Tytuł: WYNAGRODZENIE 08/2026",'
          '"Nazwa nadawcy: FIRMA SP Z O O",""',
    ].join('\n');

    test('parsuje wydatek i wpływ, czyści etykiety opisu', () {
      final result = BankStatementParser.parse(utf8.encode(csv));

      expect(result.bank, 'PKO BP');
      expect(result.entries, hasLength(2));

      final expense = result.entries[0];
      expect(expense.type, TransactionType.expense);
      expect(expense.amountCents, 2350);
      expect(expense.occurredAt, DateTime(2026, 8, 20));
      expect(expense.description, contains('BIEDRONKA'));
      expect(expense.description, isNot(contains('Tytuł:')));
      expect(expense.description, isNot(contains('Lokalizacja:')));

      final income = result.entries[1];
      expect(income.type, TransactionType.income);
      expect(income.amountCents, 350000);
      expect(income.description, contains('WYNAGRODZENIE'));
    });
  });

  group('BankStatementParser — ING (Moje ING)', () {
    final csv = [
      'Lista transakcji;;;;;;;;;;;;;;;;',
      'Dokument nr 1/2026;;;;;;;;;;;;;;;;',
      ';;;;;;;;;;;;;;;;',
      '"Data transakcji";"Data księgowania";"Dane kontrahenta";"Tytuł";'
          '"Nr rachunku";"Nazwa banku";"Szczegóły";"Nr transakcji";'
          '"Kwota transakcji (waluta rachunku)";"Waluta";'
          '"Kwota blokady/zwolnienie blokady";"Waluta";'
          '"Kwoty płatności w walucie";"Waluta";"Konto";'
          '"Saldo po transakcji";"Waluta"',
      '2026-08-21;2026-08-21;ZABKA Z5732 K.1 WARSZAWA PL;'
          'ZAKUP PRZY UZYCIU KARTY;;;;;-15,80;PLN;;;;;KONTO;984,20;PLN',
      // Blokada — pusta kwota transakcji → pomijamy.
      '2026-08-20;2026-08-20;JAN KOWALSKI;PRZELEW;;;;;;PLN;-50,00;PLN;;;'
          'KONTO;1000,00;PLN',
    ].join('\n');

    test('pomija preambułę i blokady, parsuje kwotę z przecinkiem', () {
      final result = BankStatementParser.parse(utf8.encode(csv));

      expect(result.bank, 'ING');
      expect(result.entries, hasLength(1));
      expect(result.skippedOther, 1);

      final e = result.entries.single;
      expect(e.type, TransactionType.expense);
      expect(e.amountCents, 1580);
      expect(e.occurredAt, DateTime(2026, 8, 21));
      expect(e.description, contains('ZABKA'));
    });
  });

  group('BankStatementParser — Revolut', () {
    final csv = [
      'Type,Product,Started Date,Completed Date,Description,Amount,Fee,'
          'Currency,State,Balance',
      'CARD_PAYMENT,Current,2026-08-19 12:01:33,2026-08-20 06:11:02,'
          'Allegro,-49.99,0.00,PLN,COMPLETED,150.01',
      'TOPUP,Current,2026-08-18 10:00:00,2026-08-18 10:00:01,'
          'Doładowanie,200.00,0.00,PLN,COMPLETED,200.00',
      'CARD_PAYMENT,Current,2026-08-17 09:00:00,,Netflix,-29.99,0.00,PLN,'
          'PENDING,229.99',
      'EXCHANGE,Current,2026-08-16 08:00:00,2026-08-16 08:00:01,'
          'PLN to EUR,-10.00,0.00,EUR,COMPLETED,50.00',
    ].join('\n');

    test('bierze COMPLETED w PLN, dolicza fee, pomija resztę z licznikami', () {
      final result = BankStatementParser.parse(utf8.encode(csv));

      expect(result.bank, 'Revolut');
      expect(result.entries, hasLength(2));
      expect(result.skippedOther, 1); // PENDING
      expect(result.skippedNonPln, 1); // EUR

      final card = result.entries[0];
      expect(card.type, TransactionType.expense);
      expect(card.amountCents, 4999);
      expect(card.occurredAt, DateTime(2026, 8, 20)); // Completed Date
      expect(card.description, 'Allegro');

      final topup = result.entries[1];
      expect(topup.type, TransactionType.income);
      expect(topup.amountCents, 20000);
    });

    test('fee powiększa wydatek', () {
      final withFee = [
        'Type,Product,Started Date,Completed Date,Description,Amount,Fee,'
            'Currency,State,Balance',
        'ATM,Current,2026-08-10 10:00:00,2026-08-10 10:00:01,'
            'Bankomat,-100.00,2.50,PLN,COMPLETED,50.00',
      ].join('\n');
      final result = BankStatementParser.parse(utf8.encode(withFee));
      expect(result.entries.single.amountCents, 10250);
    });
  });

  group('BankStatementParser — narzędzia', () {
    test('decodeCp1250 mapuje polskie znaki', () {
      // "PŁATNOŚĆ ŻABKA łóż" w windows-1250.
      final bytes = <int>[
        0x50, 0xA3, 0x41, 0x54, 0x4E, 0x4F, 0x8C, 0xC6, 0x20, // PŁATNOŚĆ
        0xAF, 0x41, 0x42, 0x4B, 0x41, 0x20, // ŻABKA
        0xB3, 0xF3, 0xBF, // łóż
      ];
      expect(BankStatementParser.decodeCp1250(bytes), 'PŁATNOŚĆ ŻABKA łóż');
    });

    test('parseAmountCents: przecinki, kropki, spacje tysięcy, znaki', () {
      expect(BankStatementParser.parseAmountCents('-23,50'), -2350);
      expect(BankStatementParser.parseAmountCents('+1 234,56'), 123456);
      expect(BankStatementParser.parseAmountCents('-49.99'), -4999);
      expect(BankStatementParser.parseAmountCents(''), isNull);
      expect(BankStatementParser.parseAmountCents('abc'), isNull);
    });

    test('parseDate: ISO, polski format i timestamp', () {
      expect(
        BankStatementParser.parseDate('2026-08-21'),
        DateTime(2026, 8, 21),
      );
      expect(
        BankStatementParser.parseDate('21.08.2026'),
        DateTime(2026, 8, 21),
      );
      expect(
        BankStatementParser.parseDate('2026-08-21 14:03:11'),
        DateTime(2026, 8, 21),
      );
      expect(BankStatementParser.parseDate('nie-data'), isNull);
    });

    test('parseCsv: cudzysłowy z separatorem i escape ""', () {
      final rows = BankStatementParser.parseCsv(
        '"a,b",c\n"x ""y""",z',
        ',',
      );
      expect(rows, [
        ['a,b', 'c'],
        ['x "y"', 'z'],
      ]);
    });

    test('nieznany format → czytelny wyjątek', () {
      expect(
        () => BankStatementParser.parse(utf8.encode('foo;bar\n1;2')),
        throwsA(isA<StatementParseException>()),
      );
    });
  });
}
