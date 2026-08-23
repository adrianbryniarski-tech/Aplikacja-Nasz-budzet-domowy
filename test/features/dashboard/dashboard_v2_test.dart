import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nasz_budzet_domowy/features/budgets/application/budget_providers.dart';
import 'package:nasz_budzet_domowy/features/budgets/data/budget.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/dashboard/application/dashboard_v2_providers.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/dashboard_screen.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/dashboard_v2.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/investments/application/investment_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:shared_preferences/shared_preferences.dart';

Transaction _tx(
  int amount,
  TransactionType type,
  DateTime when, {
  String? description,
}) =>
    Transaction(
      id: 'tx-${when.microsecondsSinceEpoch}-$amount',
      householdId: 'h1',
      occurredAt: when,
      amountCents: amount,
      type: type,
      categoryId: 'c',
      description: description,
      source: TransactionSource.manual,
      dedupHash: 'hash-$amount',
      createdAt: when,
    );

void main() {
  group('safeToSpendPerDayCents — „ile dziennie do końca okresu"', () {
    final start = DateTime(2026, 8);
    final end = DateTime(2026, 8, 31, 23, 59, 59);

    test('dzieli saldo przez dni do końca (z dzisiaj włącznie)', () {
      final perDay = safeToSpendPerDayCents(
        balanceCents: 31000,
        rangeStart: start,
        rangeEnd: end,
        now: DateTime(2026, 8, 1, 12),
      );
      expect(perDay, 1000); // 310 zł / 31 dni
    });

    test('ostatni dzień okresu = całe saldo na dziś', () {
      final perDay = safeToSpendPerDayCents(
        balanceCents: 4200,
        rangeStart: start,
        rangeEnd: end,
        now: DateTime(2026, 8, 31, 8),
      );
      expect(perDay, 4200);
    });

    test('null gdy saldo <= 0 albo okres nie obejmuje dzisiaj', () {
      expect(
        safeToSpendPerDayCents(
          balanceCents: 0,
          rangeStart: start,
          rangeEnd: end,
          now: DateTime(2026, 8, 15),
        ),
        isNull,
      );
      expect(
        safeToSpendPerDayCents(
          balanceCents: 1000,
          rangeStart: start,
          rangeEnd: end,
          now: DateTime(2026, 9, 2), // po okresie
        ),
        isNull,
      );
      expect(
        safeToSpendPerDayCents(
          balanceCents: 1000,
          rangeStart: start,
          rangeEnd: end,
          now: DateTime(2026, 7, 30), // przed okresem
        ),
        isNull,
      );
    });
  });

  group('dueLabel — etykieta terminu cyklicznej', () {
    final now = DateTime(2026, 8, 23, 14);

    test('dziś / jutro / za N dni / zaległa', () {
      expect(dueLabel(DateTime(2026, 8, 23), now), 'dziś');
      expect(dueLabel(DateTime(2026, 8, 24), now), 'jutro');
      expect(dueLabel(DateTime(2026, 8, 30), now), 'za 7 dni');
      expect(dueLabel(DateTime(2026, 8, 20), now), 'zaległa');
    });
  });

  group('topExpenseCategories', () {
    test('sortuje malejąco, liczy udziały, tnie do limitu', () {
      final top = topExpenseCategories(
        {'a': 5000, 'b': 3000, 'c': 1500, 'd': 500},
      );
      expect(top, hasLength(3));
      expect(top[0].categoryId, 'a');
      expect(top[0].share, 0.5);
      expect(top[1].categoryId, 'b');
      expect(top[2].categoryId, 'c');
    });

    test('puste wydatki → pusta lista', () {
      expect(topExpenseCategories(const {}), isEmpty);
    });
  });

  group('dashboardV2EnabledProvider', () {
    test('domyślnie wyłączony; wczytuje zapisany wybór', () async {
      SharedPreferences.setMockInitialValues({'dashboard_v2_enabled': true});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(dashboardV2EnabledProvider), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(dashboardV2EnabledProvider), isTrue);
    });

    test('setEnabled zapisuje wybór w preferencjach', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(dashboardV2EnabledProvider.notifier)
          .setEnabled(enabled: true);
      expect(container.read(dashboardV2EnabledProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dashboard_v2_enabled'), isTrue);
    });
  });

  group('DashboardScreen z włączonym nowym pulpitem', () {
    final now = DateTime.now();
    // 1. dnia miesiąca w południe — zawsze w zakresie „ten miesiąc".
    final thisMonth = DateTime(now.year, now.month, 1, 12);
    final lastMonth = DateTime(now.year, now.month - 1, 10, 12);

    final dataOverrides = [
      transactionsProvider.overrideWith(
        (ref) => Stream.value([
          _tx(
            100000,
            TransactionType.income,
            thisMonth,
            description: 'Wypłata',
          ),
          _tx(
            3000,
            TransactionType.expense,
            thisMonth,
            description: 'Zakupy',
          ),
          _tx(7000, TransactionType.expense, lastMonth),
        ]),
      ),
      budgetsProvider.overrideWith(
        (ref) => Stream.value([
          Budget(
            id: 'b1',
            householdId: 'h1',
            categoryId: 'c',
            amountCents: 50000,
            startsOn: DateTime(now.year, now.month - 2),
          ),
        ]),
      ),
      currentHouseholdIdProvider.overrideWith((ref) async => 'h1'),
      categoriesProvider.overrideWith(
        (ref) => Stream.value(const [
          Category(
            id: 'c',
            householdId: 'h1',
            name: 'Jedzenie',
            icon: 'food',
            colorHex: '#FF0000',
            type: TransactionType.expense,
            isSystem: false,
          ),
        ]),
      ),
      investmentsProvider.overrideWith((ref) => Stream.value(const [])),
      recurringListProvider.overrideWith((ref) async => const []),
    ];

    Widget app() => ProviderScope(
          overrides: dataOverrides,
          child: const MaterialApp(
            locale: Locale('pl'),
            supportedLocales: [Locale('pl')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: DashboardScreen()),
          ),
        );

    testWidgets('pokazuje karty V2 zamiast klasycznych kafli', (tester) async {
      await initializeDateFormatting('pl_PL');
      SharedPreferences.setMockInitialValues({'dashboard_v2_enabled': true});

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Bohater + podpowiedź dzienna (saldo dodatnie: 1000 − 30 zł).
      expect(find.text('ZOSTAŁO W TYM OKRESIE'), findsOneWidget);
      expect(
        find.textContaining('dziennie do końca okresu'),
        findsOneWidget,
      );
      // Kafle i sekcje.
      expect(find.text('Dochody'), findsOneWidget);
      expect(find.text('Wydatki'), findsOneWidget);
      expect(find.text('Budżety'), findsOneWidget);
      expect(find.text('Na co idzie najwięcej'), findsOneWidget);
      expect(find.text('Ostatnie transakcje'), findsOneWidget);
      expect(find.text('Zakupy'), findsOneWidget);
      // Szybkie akcje.
      expect(find.text('Wydatek'), findsOneWidget);
      expect(find.text('Dochód'), findsOneWidget);
      // Klasycznego kafla nie ma.
      expect(find.text('Saldo okresu'), findsNothing);
    });

    testWidgets('domyślnie zostaje klasyczny pulpit', (tester) async {
      await initializeDateFormatting('pl_PL');
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Saldo okresu'), findsOneWidget);
      expect(find.text('ZOSTAŁO W TYM OKRESIE'), findsNothing);
    });
  });
}
