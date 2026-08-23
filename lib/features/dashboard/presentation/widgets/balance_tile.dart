import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/features/dashboard/data/dashboard_summary.dart';
import 'package:nasz_budzet_domowy/shared/widgets/animated_neon_border.dart';
import 'package:nasz_budzet_domowy/shared/widgets/bento_tile.dart';

/// Tile (a): saldo okresu + delta vs poprzedni równy okres.
class BalanceTile extends StatelessWidget {
  const BalanceTile({required this.summary, super.key});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 2,
    );
    final balance = summary.balanceCents / 100;
    final delta = summary.deltaCents / 100;
    final positive = balance >= 0;
    final deltaPositive = delta >= 0;

    return AnimatedNeonBorder(
      child: BentoTile(
        title: 'Saldo okresu',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                fmt.format(balance),
                style: tt.displayMedium?.copyWith(
                  color:
                      positive ? AppTheme.incomeAccent : AppTheme.expenseAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  deltaPositive
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 14,
                  color: deltaPositive
                      ? AppTheme.incomeAccent
                      : AppTheme.expenseAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  '${deltaPositive ? '+' : ''}${fmt.format(delta)}'
                  ' vs poprzedni okres',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (summary.expenseDeltaPct != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Wydatki ${summary.expenseDeltaPct! >= 0 ? '+' : ''}'
                  '${summary.expenseDeltaPct}% vs poprzedni okres',
                  style: tt.bodySmall?.copyWith(
                    color: summary.expenseDeltaPct! > 0
                        ? AppTheme.expenseAccent
                        : AppTheme.incomeAccent,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat(
                  label: 'Dochody',
                  valueCents: summary.totalIncomeCents,
                  color: AppTheme.incomeAccent,
                ),
                const SizedBox(width: 24),
                _Stat(
                  label: 'Wydatki',
                  valueCents: summary.totalExpenseCents,
                  color: AppTheme.expenseAccent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.valueCents,
    required this.color,
  });

  final String label;
  final int valueCents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        Text(
          fmt.format(valueCents / 100),
          style: tt.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
