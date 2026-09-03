import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_notifications.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

void main() {
  group('BankNotificationParser.cleanMerchant', () {
    test('ucina ogon z saldem i limitem', () {
      expect(
        BankNotificationParser.cleanMerchant(
          ', BIEDRONKA KROLOWEJ JADWIGI, dostępne środki: 1 234,00 PLN',
        ),
        'BIEDRONKA KROLOWEJ JADWIGI',
      );
      expect(
        BankNotificationParser.cleanMerchant('ZABKA, saldo: 500,00 PLN'),
        'ZABKA',
      );
    });

    test('wywala maski kart', () {
      expect(
        BankNotificationParser.cleanMerchant('Biedronka • Karta ••1234'),
        'Biedronka',
      );
      expect(
        BankNotificationParser.cleanMerchant('LIDL nr karty 4321'),
        'LIDL',
      );
    });

    test('zdejmuje wiodące czasowniki i przyimki', () {
      expect(
        BankNotificationParser.cleanMerchant('Płatność kartą w Rossmann'),
        'Rossmann',
      );
      expect(BankNotificationParser.cleanMerchant('at Tesco'), 'Tesco');
      expect(
        BankNotificationParser.cleanMerchant('od GMINA MIASTO NOWY TARG'),
        'GMINA MIASTO NOWY TARG',
      );
    });

    test('wywala kody terminali i osierocone cyfry', () {
      expect(
        BankNotificationParser.cleanMerchant('BIEDRONKA 1234 KRAKOW'),
        'BIEDRONKA KRAKOW',
      );
      expect(
        BankNotificationParser.cleanMerchant('ZABKA Z8134 K.1'),
        'ZABKA',
      );
    });

    test('null gdy nie zostaje nic sensownego', () {
      expect(BankNotificationParser.cleanMerchant('PLN'), isNull);
      expect(BankNotificationParser.cleanMerchant(' •• '), isNull);
      expect(BankNotificationParser.cleanMerchant('12,34 zł'), isNull);
    });
  });

  group('parse na prawdziwych formatach powiadomień', () {
    ({int cents, String merchant, TransactionType type}) run(
      String bank,
      String? title,
      String? content,
    ) {
      final s = BankNotificationParser.parse(
        bank: bank,
        title: title,
        content: content,
      )!;
      return (cents: s.amountCents, merchant: s.merchant, type: s.type);
    }

    test('Portfel Google: kwota w tytule, sklep w treści', () {
      final r = run('Portfel Google', 'Zapłacono 23,50 zł', 'Biedronka');
      expect(r.cents, 2350);
      expect(r.merchant, 'Biedronka');
      expect(r.type, TransactionType.expense);
    });

    test('Portfel Google: sklep w tytule, kwota w treści', () {
      final r = run('Portfel Google', 'Biedronka', '23,50 zł • Karta ••1234');
      expect(r.cents, 2350);
      expect(r.merchant, 'Biedronka');
    });

    test('IKO: kwota + sklep + saldo w treści', () {
      final r = run(
        'PKO BP',
        'Płatność kartą',
        '23,50 PLN, BIEDRONKA 1234 KRAKOW, dostępne środki: 1 234,00 PLN',
      );
      expect(r.cents, 2350);
      expect(r.merchant, 'BIEDRONKA KRAKOW');
    });

    test('Moje ING: kwota w tytule, sklep + saldo w treści', () {
      final r = run(
        'ING',
        'Płatność kartą 23,50 PLN',
        'ZABKA Z8134 K.1, saldo: 1 234,00 PLN',
      );
      expect(r.cents, 2350);
      expect(r.merchant, 'ZABKA');
    });

    test('Revolut po angielsku', () {
      final r = run('Revolut', 'Payment', '23.50 zł at Biedronka');
      expect(r.cents, 2350);
      expect(r.merchant, 'Biedronka');
    });

    test('wpływ: przelew przychodzący od nadawcy', () {
      final r = run(
        'ING',
        'Przelew przychodzący',
        'Wpłynęło 4 289,80 PLN od GMINA MIASTO NOWY TARG',
      );
      expect(r.cents, 428980);
      expect(r.type, TransactionType.income);
      expect(r.merchant, 'GMINA MIASTO NOWY TARG');
    });

    test('gdy nic nie zostanie — nazwa banku jako opis', () {
      final r = run('ING', 'Płatność kartą 15,00 PLN', null);
      expect(r.cents, 1500);
      expect(r.merchant, 'ING');
    });
  });
}
