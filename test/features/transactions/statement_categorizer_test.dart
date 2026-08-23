import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/statement_categorizer.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

void main() {
  Category cat(String id, String name, TransactionType type) => Category(
        id: id,
        householdId: 'h1',
        name: name,
        icon: 'x',
        colorHex: '#111111',
        type: type,
        isSystem: true,
      );

  final categories = [
    cat('c-spoz', 'Spożywcze', TransactionType.expense),
    cat('c-trans', 'Transport', TransactionType.expense),
    cat('c-rozr', 'Rozrywka', TransactionType.expense),
    cat('c-pensja', 'Pensja', TransactionType.income),
  ];

  group('StatementCategorizer', () {
    test('wbudowany wzorzec: Biedronka → Spożywcze (po nazwie seedowej)', () {
      final c = StatementCategorizer(
        categories: categories,
        learnedRules: const [],
      );
      expect(
        c.categoryIdFor(
          'PŁATNOŚĆ KARTĄ BIEDRONKA 123 WARSZAWA',
          TransactionType.expense,
        ),
        'c-spoz',
      );
      expect(
        c.categoryIdFor('ORLEN STACJA 4321', TransactionType.expense),
        'c-trans',
      );
      expect(
        c.categoryIdFor('WYNAGRODZENIE 08/2026', TransactionType.income),
        'c-pensja',
      );
    });

    test('reguła nauczona ma pierwszeństwo nad wbudowaną', () {
      final c = StatementCategorizer(
        categories: categories,
        learnedRules: const [
          // Rodzina uznała, że Biedronka to jednak Rozrywka. Ich budżet.
          MerchantRule(pattern: 'biedronka', categoryId: 'c-rozr'),
        ],
      );
      expect(
        c.categoryIdFor('BIEDRONKA 123', TransactionType.expense),
        'c-rozr',
      );
    });

    test('dłuższy nauczony wzorzec wygrywa z krótszym', () {
      final c = StatementCategorizer(
        categories: categories,
        learnedRules: const [
          MerchantRule(pattern: 'zabka', categoryId: 'c-spoz'),
          MerchantRule(pattern: 'zabka cafe', categoryId: 'c-rozr'),
        ],
      );
      expect(
        c.categoryIdFor('ZABKA CAFE 001', TransactionType.expense),
        'c-rozr',
      );
      expect(
        c.categoryIdFor('ZABKA Z5732', TransactionType.expense),
        'c-spoz',
      );
    });

    test('niezgodny typ kategorii → reguła pomijana', () {
      final c = StatementCategorizer(
        categories: categories,
        learnedRules: const [
          // Reguła wskazuje kategorię wydatkową, a wpis jest dochodem.
          MerchantRule(pattern: 'biedronka', categoryId: 'c-spoz'),
        ],
      );
      expect(
        c.categoryIdFor('BIEDRONKA ZWROT', TransactionType.income),
        isNull,
      );
    });

    test('brak dopasowania → null', () {
      final c = StatementCategorizer(
        categories: categories,
        learnedRules: const [],
      );
      expect(
        c.categoryIdFor('TAJEMNICZY SKLEP 42', TransactionType.expense),
        isNull,
      );
    });

    test('patternFor: 3 pierwsze słowa po normalizacji', () {
      expect(
        StatementCategorizer.patternFor('ŻABKA Z5732 K.1 WARSZAWA PL'),
        'zabka z5732 k',
      );
      expect(StatementCategorizer.patternFor('LIDL'), 'lidl');
    });
  });
}
