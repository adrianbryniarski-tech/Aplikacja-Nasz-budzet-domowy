import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/settings/application/csv_export.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

Transaction _tx({
  required int amount,
  required TransactionType type,
  required DateTime when,
  String cat = 'c1',
  String? description,
  String? note,
  TransactionSource source = TransactionSource.manual,
}) {
  return Transaction(
    id: 'tx-${when.toIso8601String()}-$amount',
    householdId: 'h1',
    occurredAt: when,
    amountCents: amount,
    type: type,
    categoryId: cat,
    description: description,
    note: note,
    source: source,
    dedupHash: 'hash',
    createdAt: when,
  );
}

const _cat = Category(
  id: 'c1',
  householdId: 'h1',
  name: 'Spożywcze',
  icon: 'cart',
  colorHex: '#7AB87A',
  type: TransactionType.expense,
  isSystem: true,
);

void main() {
  group('buildTransactionsCsv', () {
    test('BOM + nagłówek + wiersz z polskim formatem kwoty', () {
      final csv = buildTransactionsCsv(
        [
          _tx(
            amount: 2350,
            type: TransactionType.expense,
            when: DateTime(2026, 8, 23),
            description: 'Biedronka',
          ),
        ],
        {'c1': _cat},
      );
      expect(csv.startsWith('﻿'), isTrue);
      final lines = csv.trim().replaceFirst('﻿', '').split('\n');
      expect(lines.first, 'Data;Typ;Kwota;Kategoria;Opis;Notatka;Źródło');
      expect(
        lines[1],
        '2026-08-23;Wydatek;23,50;Spożywcze;Biedronka;;ręcznie',
      );
    });

    test('sortuje rosnąco po dacie i rozróżnia typy', () {
      final csv = buildTransactionsCsv(
        [
          _tx(
            amount: 100,
            type: TransactionType.expense,
            when: DateTime(2026, 8, 20),
          ),
          _tx(
            amount: 500000,
            type: TransactionType.income,
            when: DateTime(2026, 8),
          ),
        ],
        {'c1': _cat},
      );
      final lines = csv.trim().replaceFirst('﻿', '').split('\n');
      expect(lines[1], contains('2026-08-01;Dochód;5000,00'));
      expect(lines[2], contains('2026-08-20;Wydatek;1,00'));
    });

    test('cytuje pola ze średnikiem i cudzysłowem', () {
      final csv = buildTransactionsCsv(
        [
          _tx(
            amount: 999,
            type: TransactionType.expense,
            when: DateTime(2026, 8, 23),
            description: 'Sklep; osiedlowy',
            note: 'tzw. "zakupy"',
          ),
        ],
        {'c1': _cat},
      );
      expect(csv, contains('"Sklep; osiedlowy"'));
      expect(csv, contains('"tzw. ""zakupy"""'));
    });

    test('źródło: cykliczna i import z banku', () {
      final csv = buildTransactionsCsv(
        [
          _tx(
            amount: 250000,
            type: TransactionType.expense,
            when: DateTime(2026, 8, 10),
            source: TransactionSource.recurring,
          ),
          _tx(
            amount: 1500,
            type: TransactionType.expense,
            when: DateTime(2026, 8, 11),
            source: TransactionSource.csvImport,
          ),
        ],
        {'c1': _cat},
      );
      expect(csv, contains(';cykliczna'));
      expect(csv, contains(';import z banku'));
    });
  });
}
