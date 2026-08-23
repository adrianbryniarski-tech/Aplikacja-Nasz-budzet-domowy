import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/features/budgets/application/budget_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/shared/widgets/comic_shadow.dart';

/// Baner ostrzeżeń o limitach na pulpicie: kategorie, które w BIEŻĄCYM
/// miesiącu przekroczyły limit (🔴) albo są powyżej 80% (🟠).
///
/// Liczy zawsze z bieżącego miesiąca ([monthlyBudgetProgressProvider]),
/// niezależnie od wybranego zakresu dat pulpitu — limity są miesięczne,
/// więc ostrzeżenie ma sens tylko względem miesiąca. Znika, gdy wszystko
/// jest w normie.
class BudgetAlertsBanner extends ConsumerWidget {
  const BudgetAlertsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(monthlyBudgetProgressProvider);
    final alerts =
        progress.where((p) => p.isExceeded || p.isNearLimit).take(4).toList();
    if (alerts.isEmpty) return const SizedBox.shrink();

    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final names = {for (final c in categories) c.id: c.name};
    final theme = Theme.of(context);
    final fmt = NumberFormat('#,##0', 'pl_PL');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ComicShadow(
        child: Card(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Uwaga na limity (ten miesiąc)',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final p in alerts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '${p.isExceeded ? '🔴' : '🟠'} '
                      '${names[p.budget.categoryId] ?? 'Kategoria'}: '
                      '${(p.fraction * 100).round()}% limitu '
                      '(${fmt.format(p.spentCents / 100)}'
                      ' / ${fmt.format(p.budget.amountCents / 100)} zł)',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
