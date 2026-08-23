import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_notifications.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:shared_preferences/shared_preferences.dart';

Transaction _tx({
  required int amount,
  required DateTime when,
  TransactionType type = TransactionType.expense,
}) {
  return Transaction(
    id: 'tx-$amount-${when.toIso8601String()}',
    householdId: 'h1',
    occurredAt: when,
    amountCents: amount,
    type: type,
    categoryId: 'c1',
    source: TransactionSource.manual,
    dedupHash: 'hash',
    createdAt: when,
  );
}

BankSuggestion _sugg({
  required int amount,
  required DateTime captured,
  TransactionType type = TransactionType.expense,
}) {
  return BankSuggestion(
    id: 's-$amount',
    bank: 'PKO BP',
    merchant: 'BIEDRONKA',
    amountCents: amount,
    type: type,
    capturedAt: captured,
  );
}

void main() {
  group('suggestionAlreadyBooked (anty-dublet między telefonami)', () {
    test('ta sama kwota, typ i dzień → zaksięgowane', () {
      // occurred_at w bazie to sama data (północ) — propozycja złapana
      // po południu ma się dopasować mimo różnicy godzin.
      final booked = suggestionAlreadyBooked(
        _sugg(amount: 2350, captured: DateTime(2026, 8, 23, 17, 45)),
        [_tx(amount: 2350, when: DateTime(2026, 8, 23))],
      );
      expect(booked, isTrue);
    });

    test('inna kwota → nie łapie', () {
      final booked = suggestionAlreadyBooked(
        _sugg(amount: 2350, captured: DateTime(2026, 8, 23, 17, 45)),
        [_tx(amount: 2351, when: DateTime(2026, 8, 23))],
      );
      expect(booked, isFalse);
    });

    test('inny dzień → nie łapie', () {
      final booked = suggestionAlreadyBooked(
        _sugg(amount: 2350, captured: DateTime(2026, 8, 23, 17, 45)),
        [_tx(amount: 2350, when: DateTime(2026, 8, 22))],
      );
      expect(booked, isFalse);
    });

    test('inny typ (dochód vs wydatek) → nie łapie', () {
      final booked = suggestionAlreadyBooked(
        _sugg(amount: 2350, captured: DateTime(2026, 8, 23, 17, 45)),
        [
          _tx(
            amount: 2350,
            when: DateTime(2026, 8, 23),
            type: TransactionType.income,
          ),
        ],
      );
      expect(booked, isFalse);
    });
  });

  group('visibleBankSuggestionsProvider', () {
    test('ukrywa propozycję zaksięgowaną przez drugi telefon', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          transactionsProvider.overrideWith(
            (ref) => Stream.value([
              _tx(amount: 2350, when: DateTime(2026, 8, 23)),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Riverpod 3 pauzuje providery bez słuchaczy — jawny listen
      // utrzymuje stream aktywny, a await czeka na pierwszą emisję.
      final sub = container.listen(transactionsProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(transactionsProvider.future);

      final notifier = container.read(bankSuggestionsProvider.notifier);
      await notifier.add(
        _sugg(amount: 2350, captured: DateTime(2026, 8, 23, 17, 45)),
      );
      await notifier.add(
        _sugg(amount: 999, captured: DateTime(2026, 8, 23, 18)),
      );

      final visible = container.read(visibleBankSuggestionsProvider);
      expect(visible.map((s) => s.amountCents), [999]);
      // Surowa kolejka dalej trzyma obie (lokalny stan bez zmian).
      expect(container.read(bankSuggestionsProvider), hasLength(2));
    });
  });
}
