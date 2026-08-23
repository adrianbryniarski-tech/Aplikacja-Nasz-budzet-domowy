import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/presentation/add_transaction_screen.dart';
import 'package:nasz_budzet_domowy/features/transactions/presentation/transactions_list_screen.dart';

Transaction _tx({
  required String id,
  required int amount,
  TransactionType type = TransactionType.expense,
  String cat = 'c-spozywcze',
  String? description,
  String? note,
}) {
  final when = DateTime(2026, 8, 20);
  return Transaction(
    id: id,
    householdId: 'h1',
    occurredAt: when,
    amountCents: amount,
    type: type,
    categoryId: cat,
    description: description,
    note: note,
    source: TransactionSource.manual,
    dedupHash: 'hash-$id',
    createdAt: when,
  );
}

Category _cat(String id, String name, [TransactionType? type]) => Category(
      id: id,
      householdId: 'h1',
      name: name,
      icon: 'cart',
      colorHex: '#7AB87A',
      type: type ?? TransactionType.expense,
      isSystem: true,
    );

void main() {
  final categories = {
    'c-spozywcze': _cat('c-spozywcze', 'Spożywcze'),
    'c-transport': _cat('c-transport', 'Transport'),
  };

  group('filterTransactions', () {
    final txs = [
      _tx(id: '1', amount: 100, description: 'Biedronka Warszawa'),
      _tx(id: '2', amount: 200, cat: 'c-transport', description: 'Orlen'),
      _tx(
        id: '3',
        amount: 300,
        type: TransactionType.income,
        description: 'Wypłata',
      ),
      _tx(id: '4', amount: 400, note: 'prezent dla mamy'),
    ];

    test('bez filtra zwraca wszystko', () {
      final out = filterTransactions(
        transactions: txs,
        categoriesById: categories,
        query: '',
      );
      expect(out, hasLength(4));
    });

    test('szuka w opisie bez rozróżniania wielkości liter', () {
      final out = filterTransactions(
        transactions: txs,
        categoriesById: categories,
        query: 'biedronka',
      );
      expect(out.single.id, '1');
    });

    test('szuka po nazwie kategorii', () {
      final out = filterTransactions(
        transactions: txs,
        categoriesById: categories,
        query: 'transport',
      );
      expect(out.single.id, '2');
    });

    test('szuka w notatce', () {
      final out = filterTransactions(
        transactions: txs,
        categoriesById: categories,
        query: 'prezent',
      );
      expect(out.single.id, '4');
    });

    test('filtr typu: tylko dochody', () {
      final out = filterTransactions(
        transactions: txs,
        categoriesById: categories,
        query: '',
        type: TransactionType.income,
      );
      expect(out.single.id, '3');
    });

    test('tekst + typ łączą się (AND)', () {
      final out = filterTransactions(
        transactions: txs,
        categoriesById: categories,
        query: 'orlen',
        type: TransactionType.income,
      );
      expect(out, isEmpty);
    });
  });

  group('topCategories (chipy na formularzu)', () {
    test('sortuje po liczbie użyć i tnie do max', () {
      final txs = [
        for (var i = 0; i < 5; i++)
          _tx(id: 'a$i', amount: 100, cat: 'c-transport'),
        for (var i = 0; i < 2; i++) _tx(id: 'b$i', amount: 100),
      ];
      final top = topCategories(
        transactions: txs,
        candidates: categories.values.toList(),
        max: 1,
      );
      expect(top.single.id, 'c-transport');
    });

    test('kategoria bez użyć nie dostaje chipa', () {
      final txs = [_tx(id: '1', amount: 100)];
      final top = topCategories(
        transactions: txs,
        candidates: categories.values.toList(),
      );
      expect(top.map((c) => c.id), ['c-spozywcze']);
    });

    test('pusta historia → brak chipów', () {
      final top = topCategories(
        transactions: const [],
        candidates: categories.values.toList(),
      );
      expect(top, isEmpty);
    });
  });
}
