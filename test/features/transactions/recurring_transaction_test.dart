import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/recurring_transaction.dart';

void main() {
  group('clampedDate', () {
    test('dzień mieści się w miesiącu → bez zmian', () {
      expect(clampedDate(2026, 8, 10), DateTime(2026, 8, 10));
    });

    test('31 w kwietniu → 30 kwietnia', () {
      expect(clampedDate(2026, 4, 31), DateTime(2026, 4, 30));
    });

    test('31 w lutym → 28 lutego (2026 nieprzestępny)', () {
      expect(clampedDate(2026, 2, 31), DateTime(2026, 2, 28));
    });

    test('29 w lutym roku przestępnego → 29 lutego', () {
      expect(clampedDate(2028, 2, 29), DateTime(2028, 2, 29));
    });

    test('przelew miesiąca poza 12 → normalizacja roku', () {
      expect(clampedDate(2026, 13, 15), DateTime(2027, 1, 15));
    });
  });

  group('firstDueDate', () {
    test('dzień jeszcze przed nami w tym miesiącu → ten miesiąc', () {
      expect(
        firstDueDate(DateTime(2026, 8, 5), 10),
        DateTime(2026, 8, 10),
      );
    });

    test('dziś jest ten dzień → naliczenie dziś', () {
      expect(
        firstDueDate(DateTime(2026, 8, 10, 15, 30), 10),
        DateTime(2026, 8, 10),
      );
    });

    test('dzień już minął → następny miesiąc', () {
      expect(
        firstDueDate(DateTime(2026, 8, 23), 10),
        DateTime(2026, 9, 10),
      );
    });

    test('31 a mamy wrzesień (30 dni) → 30 września', () {
      expect(
        firstDueDate(DateTime(2026, 9), 31),
        DateTime(2026, 9, 30),
      );
    });
  });

  group('nextDueAfter', () {
    test('kolejny miesiąc, ten sam dzień', () {
      expect(
        nextDueAfter(DateTime(2026, 8, 10), 10),
        DateTime(2026, 9, 10),
      );
    });

    test('po 31 stycznia → 28/29 lutego, a dzień wraca w marcu', () {
      final feb = nextDueAfter(DateTime(2026, 1, 31), 31);
      expect(feb, DateTime(2026, 2, 28));
      expect(nextDueAfter(feb, 31), DateTime(2026, 3, 31));
    });

    test('grudzień → styczeń następnego roku', () {
      expect(
        nextDueAfter(DateTime(2026, 12, 5), 5),
        DateTime(2027, 1, 5),
      );
    });
  });
}
