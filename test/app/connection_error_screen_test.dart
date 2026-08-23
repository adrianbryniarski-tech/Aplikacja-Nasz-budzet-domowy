import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/app/connection_error_screen.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';

void main() {
  group('ConnectionErrorScreen', () {
    testWidgets('pokazuje komunikat, przycisk i szczegóły błędu',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Provider w stanie błędu — jak przy starcie bez internetu.
            currentHouseholdIdProvider
                .overrideWith((ref) async => throw Exception('serwer 540')),
          ],
          child: const MaterialApp(home: ConnectionErrorScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Brak połączenia z serwerem'), findsOneWidget);
      expect(find.text('Spróbuj ponownie'), findsOneWidget);
      expect(find.textContaining('serwer 540'), findsOneWidget);
    });

    testWidgets('„Spróbuj ponownie" odpala zapytanie od nowa', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentHouseholdIdProvider.overrideWith((ref) async {
              calls++;
              throw Exception('nadal leży');
            }),
          ],
          child: const MaterialApp(home: ConnectionErrorScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // Riverpod 3 sam ponawia nieudane providery (backoff), więc nie
      // zakładamy dokładnej liczby wywołań — tylko wzrost po tapnięciu.
      final callsBeforeTap = calls;
      expect(callsBeforeTap, greaterThanOrEqualTo(1));

      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pumpAndSettle();

      expect(calls, greaterThan(callsBeforeTap));
    });
  });
}
