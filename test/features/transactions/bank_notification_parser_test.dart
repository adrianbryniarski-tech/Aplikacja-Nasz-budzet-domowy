import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_notifications.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BankNotificationParser', () {
    test('płatność kartą → wydatek z kwotą i sklepem', () {
      final s = BankNotificationParser.parse(
        bank: 'PKO BP',
        title: 'IKO',
        content: 'Płatność kartą 23,50 PLN BIEDRONKA 123 WARSZAWA',
      );
      expect(s, isNotNull);
      expect(s!.amountCents, 2350);
      expect(s.type, TransactionType.expense);
      expect(s.merchant, contains('BIEDRONKA'));
      expect(s.bank, 'PKO BP');
    });

    test('przelew przychodzący → wpływ', () {
      final s = BankNotificationParser.parse(
        bank: 'ING',
        title: 'Moje ING',
        content: 'Przelew przychodzący 3 500,00 zł od JAN KOWALSKI',
      );
      expect(s, isNotNull);
      expect(s!.amountCents, 350000);
      expect(s.type, TransactionType.income);
      expect(s.merchant, contains('JAN KOWALSKI'));
    });

    test('kwota z kropką i walutą zł — Revolut', () {
      final s = BankNotificationParser.parse(
        bank: 'Revolut',
        title: 'Zapłacono 49.99 zł',
        content: 'Allegro',
      );
      expect(s, isNotNull);
      expect(s!.amountCents, 4999);
      expect(s.type, TransactionType.expense);
    });

    test('powiadomienie bez kwoty → null (np. reklama banku)', () {
      final s = BankNotificationParser.parse(
        bank: 'PKO BP',
        title: 'IKO',
        content: 'Sprawdź nową ofertę kredytu w aplikacji!',
      );
      expect(s, isNull);
    });

    test('brak tekstu za kwotą → sklep z tekstu przed kwotą', () {
      final s = BankNotificationParser.parse(
        bank: 'ING',
        title: 'ZABKA Z5732',
        content: 'Zapłacono 15,80 zł',
      );
      expect(s, isNotNull);
      expect(s!.merchant, contains('ZABKA'));
    });

    test('powiadomienie Portfela Google → wydatek ze sklepem', () {
      final s = BankNotificationParser.parse(
        bank: 'Portfel Google',
        title: 'Zapłacono 23,50 zł',
        content: 'Biedronka · Visa ••1234',
      );
      expect(s, isNotNull);
      expect(s!.amountCents, 2350);
      expect(s.type, TransactionType.expense);
      expect(s.merchant, contains('Biedronka'));
      expect(s.bank, 'Portfel Google');
    });
  });

  group('kBankPackages', () {
    test('zawiera Portfel Google (przy NFC to on pokazuje push)', () {
      expect(
        kBankPackages['com.google.android.apps.walletnfcrel'],
        'Portfel Google',
      );
    });
  });

  group('BankSuggestionsNotifier — anty-dublet', () {
    test('bank i Portfel Google o tej samej płatności → jedna propozycja',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(bankSuggestionsProvider.notifier);
      final now = DateTime.now();

      await notifier.add(
        BankSuggestion(
          id: 'a',
          bank: 'PKO BP',
          merchant: 'BIEDRONKA 123 WARSZAWA',
          amountCents: 2350,
          type: TransactionType.expense,
          capturedAt: now,
        ),
      );
      // Ta sama kwota chwilę później, inny tekst sklepu (inne źródło).
      await notifier.add(
        BankSuggestion(
          id: 'b',
          bank: 'Portfel Google',
          merchant: 'Biedronka · Visa ••1234',
          amountCents: 2350,
          type: TransactionType.expense,
          capturedAt: now.add(const Duration(seconds: 5)),
        ),
      );

      expect(container.read(bankSuggestionsProvider), hasLength(1));
    });
  });
}
