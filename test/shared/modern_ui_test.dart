import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/core/haptics.dart';
import 'package:nasz_budzet_domowy/shared/widgets/animated_amount.dart';
import 'package:nasz_budzet_domowy/shared/widgets/fade_indexed_stack.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AnimatedAmount', () {
    testWidgets('po ustaniu animacji pokazuje sformatowaną kwotę',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedAmount(cents: 123456, style: TextStyle()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // NumberFormat pl_PL: separator tysięcy (nbsp) + przecinek.
      final text = tester.widget<Text>(find.byType(Text)).data!;
      expect(text, contains('234,56'));
      expect(text, contains('zł'));
    });

    testWidgets('retargetuje przy zmianie wartości', (tester) async {
      Widget build(int cents) => MaterialApp(
            home: Scaffold(
              body: AnimatedAmount(cents: cents, style: const TextStyle()),
            ),
          );
      await tester.pumpWidget(build(1000));
      await tester.pumpAndSettle();
      await tester.pumpWidget(build(5000));
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.byType(Text)).data!;
      expect(text, contains('50,00'));
    });
  });

  group('FadeIndexedStack', () {
    testWidgets('zmiana indeksu pokazuje nową zakładkę i zachowuje stan',
        (tester) async {
      Widget build(int index) => MaterialApp(
            home: Scaffold(
              body: FadeIndexedStack(
                index: index,
                children: const [Text('Zakładka A'), Text('Zakładka B')],
              ),
            ),
          );
      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();
      expect(find.text('Zakładka A'), findsOneWidget);

      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();
      // IndexedStack trzyma oba dzieci w drzewie; widoczna jest B.
      expect(find.text('Zakładka B'), findsOneWidget);
    });
  });

  group('hapticsEnabledProvider', () {
    test('domyślnie włączone; wyłączenie persystuje', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(container.read(hapticsEnabledProvider), isTrue);

      await container
          .read(hapticsEnabledProvider.notifier)
          .setEnabled(enabled: false);
      expect(container.read(hapticsEnabledProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('haptics_enabled'), isFalse);
    });
  });
}
