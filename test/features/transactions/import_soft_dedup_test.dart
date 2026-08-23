import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/import_repository.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

void main() {
  group('ImportRepository.softKey (miękki odcisk dzień|kwota|typ)', () {
    test('ta sama data (różne godziny) → ten sam klucz', () {
      final a = ImportRepository.softKey(
        DateTime(2026, 8, 23, 17, 45),
        2350,
        TransactionType.expense,
      );
      final b = ImportRepository.softKey(
        DateTime(2026, 8, 23),
        2350,
        TransactionType.expense,
      );
      expect(a, b);
      expect(a, '2026-08-23|2350|expense');
    });

    test('inny dzień / kwota / typ → inne klucze', () {
      final base = ImportRepository.softKey(
        DateTime(2026, 8, 23),
        2350,
        TransactionType.expense,
      );
      expect(
        ImportRepository.softKey(
          DateTime(2026, 8, 22),
          2350,
          TransactionType.expense,
        ),
        isNot(base),
      );
      expect(
        ImportRepository.softKey(
          DateTime(2026, 8, 23),
          2351,
          TransactionType.expense,
        ),
        isNot(base),
      );
      expect(
        ImportRepository.softKey(
          DateTime(2026, 8, 23),
          2350,
          TransactionType.income,
        ),
        isNot(base),
      );
    });

    test('format zgodny z occurred_at z bazy (YYYY-MM-DD)', () {
      // Klucz liczony z odpowiedzi bazy (DateTime.parse('2026-01-05'))
      // musi trafić w klucz liczony z wpisu wyciągu.
      final fromDb = ImportRepository.softKey(
        DateTime.parse('2026-01-05'),
        118300,
        TransactionType.expense,
      );
      final fromStatement = ImportRepository.softKey(
        DateTime(2026, 1, 5),
        118300,
        TransactionType.expense,
      );
      expect(fromDb, fromStatement);
    });
  });
}
