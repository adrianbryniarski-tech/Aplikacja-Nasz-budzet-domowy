import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/budgets/data/budget.dart';
import 'package:nasz_budzet_domowy/features/budgets/data/budget_repository.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  return const BudgetRepository();
});

/// Wszystkie budżety gospodarstwa.
final budgetsProvider = StreamProvider<List<Budget>>((ref) {
  final householdId = ref.watch(currentHouseholdIdProvider).value;
  if (householdId == null) return Stream.value(const <Budget>[]);
  return ref.watch(budgetRepositoryProvider).watchAll(householdId);
});

/// Pierwszy dzień bieżącego miesiąca (lokalnie).
DateTime _firstOfMonth() {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
}

/// Pierwszy dzień następnego miesiąca (lokalnie).
DateTime _firstOfNextMonth() {
  final now = DateTime.now();
  return DateTime(now.year, now.month + 1);
}

/// Wydatki tego miesiąca per kategoria (`categoryId → sumaCents`).
final monthlySpendByCategoryProvider = Provider<Map<String, int>>((ref) {
  final txs = ref.watch(transactionsProvider).value ?? const [];
  final start = _firstOfMonth();
  final end = _firstOfNextMonth();
  final result = <String, int>{};
  for (final t in txs) {
    if (t.type != TransactionType.expense) continue;
    if (t.occurredAt.isBefore(start)) continue;
    if (!t.occurredAt.isBefore(end)) continue;
    result.update(
      t.categoryId,
      (v) => v + t.amountCents,
      ifAbsent: () => t.amountCents,
    );
  }
  return result;
});

/// Budżety z policzonym postępem dla bieżącego miesiąca. Dla każdego budżetu
/// bierzemy NAJNOWSZY rekord per kategoria z `starts_on <= dziś` — to obsłuży
/// przyszłość gdy ktoś będzie ustawiał kwoty z wyprzedzeniem.
final monthlyBudgetProgressProvider = Provider<List<BudgetProgress>>((ref) {
  final allBudgets = ref.watch(budgetsProvider).value ?? const [];
  final spend = ref.watch(monthlySpendByCategoryProvider);
  final today = DateTime.now();

  // Group by category, pick the most recent with starts_on <= today.
  final byCategory = <String, Budget>{};
  for (final b in allBudgets) {
    if (b.startsOn.isAfter(today)) continue;
    final existing = byCategory[b.categoryId];
    if (existing == null || b.startsOn.isAfter(existing.startsOn)) {
      byCategory[b.categoryId] = b;
    }
  }

  return byCategory.values
      .map(
        (b) => BudgetProgress(
          budget: b,
          spentCents: spend[b.categoryId] ?? 0,
        ),
      )
      .toList()
    ..sort((a, b) => b.fraction.compareTo(a.fraction));
});
