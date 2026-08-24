import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/settings/presentation/reset_transactions_dialog.dart';

void main() {
  group('isResetPhraseValid', () {
    test('akceptuje frazę niezależnie od wielkości liter i spacji', () {
      expect(isResetPhraseValid('KASUJĘ'), isTrue);
      expect(isResetPhraseValid('kasuję'), isTrue);
      expect(isResetPhraseValid('  Kasuję  '), isTrue);
    });

    test('odrzuca wszystko inne (w tym wersję bez ogonka)', () {
      expect(isResetPhraseValid(''), isFalse);
      expect(isResetPhraseValid('kasuje'), isFalse);
      expect(isResetPhraseValid('USUŃ'), isFalse);
      expect(isResetPhraseValid('KASUJĘ WSZYSTKO'), isFalse);
    });
  });

  group('ResetTransactionsDialog', () {
    Future<int?> openAndReturn(
      WidgetTester tester,
      Future<int> Function() onConfirm,
    ) async {
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<int>(
                    context: context,
                    builder: (_) =>
                        ResetTransactionsDialog(onConfirm: onConfirm),
                  );
                },
                child: const Text('otwórz'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('otwórz'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('przycisk odblokowuje się dopiero po przepisaniu frazy',
        (tester) async {
      var called = 0;
      await openAndReturn(tester, () async {
        called++;
        return 5;
      });

      FilledButton button() => tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Usuń wszystko'),
          );
      expect(button().onPressed, isNull, reason: 'pusto = zablokowany');

      await tester.enterText(find.byType(TextField), 'nie to słowo');
      await tester.pump();
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'kasuję');
      await tester.pump();
      expect(button().onPressed, isNotNull);

      await tester.tap(find.text('Usuń wszystko'));
      await tester.pumpAndSettle();
      expect(called, 1);
      expect(find.byType(ResetTransactionsDialog), findsNothing);
    });

    testWidgets('Anuluj zamyka bez wywołania onConfirm', (tester) async {
      var called = 0;
      await openAndReturn(tester, () async {
        called++;
        return 0;
      });
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(called, 0);
      expect(find.byType(ResetTransactionsDialog), findsNothing);
    });

    testWidgets('błąd kasowania zostaje w dialogu z komunikatem',
        (tester) async {
      await openAndReturn(tester, () async {
        throw Exception('brak sieci');
      });
      await tester.enterText(find.byType(TextField), 'KASUJĘ');
      await tester.pump();
      await tester.tap(find.text('Usuń wszystko'));
      await tester.pumpAndSettle();

      expect(find.byType(ResetTransactionsDialog), findsOneWidget);
      expect(find.textContaining('Nie udało się usunąć'), findsOneWidget);
    });
  });
}
