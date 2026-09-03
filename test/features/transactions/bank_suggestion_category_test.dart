import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_notifications.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_suggestion_actions.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/statement_categorizer.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

Category _cat(String id, String name, TransactionType type) => Category(
      id: id,
      householdId: 'h1',
      name: name,
      icon: 'shopping_cart',
      colorHex: '#7AB87A',
      type: type,
      isSystem: false,
    );

BankSuggestion _sug(
  String merchant, {
  TransactionType type = TransactionType.expense,
}) =>
    BankSuggestion(
      id: 's1',
      bank: 'Portfel Google',
      merchant: merchant,
      amountCents: 2350,
      type: type,
      capturedAt: DateTime(2026, 8, 31, 14, 30),
    );

void main() {
  final categories = [
    _cat('c-spoz', 'Spożywcze', TransactionType.expense),
    _cat('c-transport', 'Transport', TransactionType.expense),
    _cat('c-inne', 'Inne', TransactionType.expense),
    _cat('c-pensja', 'Wynagrodzenie', TransactionType.income),
  ];

  StatementCategorizer categorizer({List<MerchantRule> rules = const []}) =>
      StatementCategorizer(categories: categories, learnedRules: rules);

  group('guessCategoryFor — auto-kategoria dla propozycji z banku', () {
    test('rozpoznaje znane sieci z wbudowanej listy', () {
      final guess = guessCategoryFor(
        _sug('BIEDRONKA KRAKOW'),
        categorizer: categorizer(),
        categories: categories,
      );
      expect(guess?.name, 'Spożywcze');
    });

    test('paliwo → Transport', () {
      final guess = guessCategoryFor(
        _sug('ORLEN STACJA 123'),
        categorizer: categorizer(),
        categories: categories,
      );
      expect(guess?.name, 'Transport');
    });

    test('nieznany sklep → null (użytkownik wybiera sam)', () {
      final guess = guessCategoryFor(
        _sug('KWIACIARNIA U ZOSI'),
        categorizer: categorizer(),
        categories: categories,
      );
      expect(guess, isNull);
    });

    test('nauczona reguła wygrywa — po ręcznym wyborze apka już wie', () {
      final rules = [
        const MerchantRule(pattern: 'kwiaciarnia u zosi', categoryId: 'c-inne'),
      ];
      final guess = guessCategoryFor(
        _sug('KWIACIARNIA U ZOSI'),
        categorizer: categorizer(rules: rules),
        categories: categories,
      );
      expect(guess?.id, 'c-inne');
    });

    test('reguła nadpisuje wbudowany wzorzec', () {
      final rules = [
        // Ktoś kupuje w Żabce tylko paliwo do zapalniczek — jego wybór
        // musi wygrać z wbudowanym „zabka → Spożywcze".
        const MerchantRule(pattern: 'zabka', categoryId: 'c-transport'),
      ];
      final guess = guessCategoryFor(
        _sug('ZABKA'),
        categorizer: categorizer(rules: rules),
        categories: categories,
      );
      expect(guess?.id, 'c-transport');
    });

    test('kategoria musi być właściwego typu (wpływ ≠ kategoria wydatku)', () {
      final rules = [
        const MerchantRule(pattern: 'gmina miasto', categoryId: 'c-inne'),
      ];
      final guess = guessCategoryFor(
        _sug('GMINA MIASTO NOWY TARG', type: TransactionType.income),
        categorizer: categorizer(rules: rules),
        categories: categories,
      );
      // Reguła wskazuje kategorię WYDATKÓW, więc nie może trafić na wpływ.
      expect(guess?.type, isNot(TransactionType.expense));
    });

    test('brak kategoryzatora (kategorie jeszcze się nie wczytały) → null', () {
      expect(
        guessCategoryFor(
          _sug('BIEDRONKA'),
          categorizer: null,
          categories: categories,
        ),
        isNull,
      );
    });
  });

  group('wzorzec nauki reguły', () {
    test('z nazwy sklepu robi krótki, znormalizowany wzorzec', () {
      final pattern = StatementCategorizer.patternFor('BIEDRONKA KROLOWEJ 12');
      expect(pattern, 'biedronka krolowej 12');
      // Ten wzorzec musi potem trafiać w to samo powiadomienie.
      final guess = guessCategoryFor(
        _sug('BIEDRONKA KROLOWEJ 12'),
        categorizer: categorizer(
          rules: [MerchantRule(pattern: pattern, categoryId: 'c-inne')],
        ),
        categories: categories,
      );
      expect(guess?.id, 'c-inne');
    });
  });
}
