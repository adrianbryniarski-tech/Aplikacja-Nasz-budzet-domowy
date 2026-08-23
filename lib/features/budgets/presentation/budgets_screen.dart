import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/features/budgets/application/budget_providers.dart';
import 'package:nasz_budzet_domowy/features/budgets/data/budget.dart';
import 'package:nasz_budzet_domowy/features/budgets/presentation/widgets/budget_edit_sheet.dart';
import 'package:nasz_budzet_domowy/features/budgets/presentation/widgets/budget_progress_tile.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/shared/widgets/async_error_state.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Ekran listy budżetów miesięcznych. Każdy rekord = jedna kategoria
/// wydatków + miesięczny limit + pasek postępu wydatków w bieżącym miesiącu.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(budgetsProvider);
    final progress = ref.watch(monthlyBudgetProgressProvider);
    final categoriesById = <String, Category>{
      for (final c
          in (ref.watch(categoriesProvider).value ?? const <Category>[]))
        c.id: c,
    };
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('Budżety'),
          centerTitle: false,
          floating: true,
          snap: true,
          actions: [
            IconButton(
              tooltip: 'Odśwież',
              icon: const AppIcon(Icons.refresh),
              onPressed: () {
                // Też transakcje — paski postępu liczą wydatki z
                // `transactionsProvider`, nie z samych budżetów.
                ref
                  ..invalidate(budgetsProvider)
                  ..invalidate(transactionsProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Odświeżam dane…'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Nowy budżet',
              icon: const AppIcon(Icons.add),
              onPressed: () => _openCreateSheet(context),
            ),
          ],
        ),
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            ref
              ..invalidate(budgetsProvider)
              ..invalidate(transactionsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 500));
          },
        ),
        budgetsAsync.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: AsyncErrorState(
              error: e,
              onRetry: () {
                ref
                  ..invalidate(budgetsProvider)
                  ..invalidate(transactionsProvider);
              },
            ),
          ),
          data: (_) {
            if (progress.isEmpty) {
              return const SliverFillRemaining(child: _EmptyState());
            }
            final monthLabel =
                DateFormat('LLLL y', 'pl_PL').format(DateTime.now());
            return SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    monthLabel[0].toUpperCase() + monthLabel.substring(1),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                for (final p in progress)
                  if (categoriesById[p.budget.categoryId] != null)
                    BudgetProgressTile(
                      progress: p,
                      category: categoriesById[p.budget.categoryId]!,
                      onTap: () => _openEditSheet(context, p.budget),
                    ),
                const SizedBox(height: 96),
              ]),
            );
          },
        ),
      ],
    );
  }
}

Future<bool?> _openCreateSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const BudgetEditSheet(),
  );
}

Future<bool?> _openEditSheet(BuildContext context, Budget budget) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BudgetEditSheet(existing: budget),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.savings_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Brak budżetów',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Ustaw limit miesięczny dla kategorii wydatków — '
              'apka będzie pilnować ile zostało.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
