import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/core/haptics.dart';
import 'package:nasz_budzet_domowy/features/budgets/data/budget.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/dashboard/application/dashboard_providers.dart';
import 'package:nasz_budzet_domowy/features/dashboard/application/date_range_filter.dart';
import 'package:nasz_budzet_domowy/features/dashboard/data/dashboard_summary.dart';
import 'package:nasz_budzet_domowy/features/settings/application/theme_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/presentation/add_transaction_screen.dart';
import 'package:nasz_budzet_domowy/shared/widgets/animated_amount.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';
import 'package:nasz_budzet_domowy/shared/widgets/comic_shadow.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Nowy pulpit („Pulpit 2.0") — układ bento wg trendów 2025/26.
///
/// Projekt oparty na researchu (bento grid, fintech UX, Material 3
/// Expressive, apki typu „safe to spend"):
/// - hierarchia przez ROZMIAR kart: bohater „Zostało do wydania" na
///   górze, mniejsze kafle niżej — oko znajduje najważniejsze od razu;
/// - podpowiedź „≈ tyle dziennie do końca okresu" — dzienna rama
///   zamiast miesięcznej sumy zmniejsza paraliż decyzyjny;
/// - warstwowość: pulpit = szybki rzut oka, szczegóły są tap dalej
///   (budżety, cykliczne, edycja transakcji);
/// - duże zaokrąglenia, delikatny gradient, count-upy i haptyka —
///   nowocześnie, ale wszystko na tokenach motywu (działa w każdym
///   z 14 motywów i w trybie ciemnym).
class DashboardV2Body extends ConsumerWidget {
  const DashboardV2Body({
    required this.summary,
    required this.categories,
    super.key,
  });

  final DashboardSummary summary;
  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(periodBudgetProgressProvider);
    final range = ref.watch(dateRangeFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroCard(summary: summary, range: range),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStatCard(
                  label: 'Dochody',
                  cents: summary.totalIncomeCents,
                  accent: AppTheme.incomeAccent,
                  icon: Icons.trending_up_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStatCard(
                  label: 'Wydatki',
                  cents: summary.totalExpenseCents,
                  accent: AppTheme.expenseAccent,
                  icon: Icons.trending_down_rounded,
                  deltaPct: summary.expenseDeltaPct,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _QuickActionsRow(),
          if (budgets.isNotEmpty) ...[
            const SizedBox(height: 12),
            _BudgetsCard(budgets: budgets, categories: categories),
          ],
          if (summary.runningBalancePoints.length >= 2) ...[
            const SizedBox(height: 12),
            _TrendCard(summary: summary),
          ],
          if (summary.expenseByCategoryId.isNotEmpty) ...[
            const SizedBox(height: 12),
            _TopCategoriesCard(summary: summary, categories: categories),
          ],
          const _UpcomingCard(),
          _RecentCard(categories: categories),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logika (czysta — testowana wprost).
// ---------------------------------------------------------------------------

/// „Bezpiecznie dziennie": saldo okresu / dni do końca okresu (z dzisiaj
/// włącznie). `null`, gdy okres nie obejmuje dzisiaj albo saldo <= 0 —
/// wtedy podpowiedź nie ma sensu.
int? safeToSpendPerDayCents({
  required int balanceCents,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime now,
}) {
  if (balanceCents <= 0) return null;
  final today = DateTime(now.year, now.month, now.day);
  final firstDay = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  if (today.isBefore(firstDay) ||
      today.isAfter(DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day))) {
    return null;
  }
  final lastDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  final daysLeft = lastDay.difference(today).inDays + 1;
  return balanceCents ~/ daysLeft;
}

/// Ile dni do końca okresu (z dzisiaj włącznie) — do tekstu podpowiedzi.
int daysLeftInRange(DateTime rangeEnd, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final lastDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  return lastDay.difference(today).inDays + 1;
}

/// Etykieta terminu cyklicznej płatności: „dziś", „jutro", „za N dni",
/// „zaległa" (termin minął — naliczy się przy najbliższym odświeżeniu).
String dueLabel(DateTime due, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = day.difference(today).inDays;
  if (diff < 0) return 'zaległa';
  if (diff == 0) return 'dziś';
  if (diff == 1) return 'jutro';
  return 'za $diff dni';
}

/// Top N kategorii wydatków z udziałami (posortowane malejąco).
List<({String categoryId, int cents, double share})> topExpenseCategories(
  Map<String, int> expenseByCategoryId, {
  int limit = 3,
}) {
  final total =
      expenseByCategoryId.values.fold<int>(0, (sum, cents) => sum + cents);
  if (total <= 0) return const [];
  final sorted = expenseByCategoryId.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in sorted.take(limit))
      (categoryId: e.key, cents: e.value, share: e.value / total),
  ];
}

// ---------------------------------------------------------------------------
// Karty.
// ---------------------------------------------------------------------------

/// Wspólna baza kart V2: duże zaokrąglenie, powierzchnia z tokenów,
/// w motywach komiksowych gruby kontur + komiksowy cień.
class _V2Card extends ConsumerWidget {
  const _V2Card({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.gradient,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final variant = ref.watch(themeVariantProvider);
    final ink = comicInk(variant, Theme.of(context).scaffoldBackgroundColor);

    final card = Material(
      color: gradient == null ? cs.surfaceContainerHigh : Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(24),
          border: variant.isComic ? Border.all(color: ink, width: 2.5) : null,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    return RepaintBoundary(
      child: ComicShadow(borderRadius: 24, child: card),
    );
  }
}

/// Bohater pulpitu: ile zostało w tym okresie + delta + „ile dziennie".
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.summary, required this.range});

  final DashboardSummary summary;
  final DateRangeFilter range;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 0,
    );
    final positive = summary.balanceCents >= 0;
    final accent = positive ? AppTheme.incomeAccent : AppTheme.expenseAccent;
    final delta = summary.deltaCents;
    final deltaUp = delta >= 0;
    final now = DateTime.now();
    final perDay = safeToSpendPerDayCents(
      balanceCents: summary.balanceCents,
      rangeStart: range.start,
      rangeEnd: range.end,
      now: now,
    );

    return _V2Card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            cs.primary.withValues(alpha: 0.14),
            cs.surfaceContainerHigh,
          ),
          cs.surfaceContainerHigh,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ZOSTAŁO W TYM OKRESIE',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _Pill(
                icon: deltaUp
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                label: '${deltaUp ? '+' : ''}${fmt.format(delta / 100)}',
                color: deltaUp ? AppTheme.incomeAccent : AppTheme.expenseAccent,
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedAmount(
              cents: summary.balanceCents,
              style: tt.displayLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (perDay != null)
            Row(
              children: [
                Icon(
                  Icons.wb_sunny_outlined,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '≈ ${fmt.format(perDay / 100)} dziennie do końca okresu '
                    '(${daysLeftInRange(range.end, now)} dni)',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            )
          else
            Text(
              positive
                  ? 'Dochody minus wydatki w wybranym okresie.'
                  : 'W tym okresie wydaliście więcej, niż weszło.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Mały kafelek statystyki (Dochody / Wydatki).
class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.cents,
    required this.accent,
    required this.icon,
    this.deltaPct,
  });

  final String label;
  final int cents;
  final Color accent;
  final IconData icon;
  final int? deltaPct;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _V2Card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: tt.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedAmount(
              cents: cents,
              decimalDigits: 0,
              style: tt.titleLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (deltaPct != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${deltaPct! >= 0 ? '+' : ''}$deltaPct% vs poprzedni',
                style: tt.labelSmall?.copyWith(
                  color: deltaPct! > 0
                      ? AppTheme.expenseAccent
                      : AppTheme.incomeAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Szybkie akcje — jedno stuknięcie do najczęstszych czynności.
class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final haptics = ref.read(hapticsProvider);
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () {
              haptics.tap();
              context.push<void>(
                '/transactions/add',
                extra: const TransactionPrefill(type: TransactionType.expense),
              );
            },
            icon: const AppIcon(Icons.remove_circle_outline),
            label: const Text('Wydatek'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () {
              haptics.tap();
              context.push<void>(
                '/transactions/add',
                extra: const TransactionPrefill(type: TransactionType.income),
              );
            },
            icon: const AppIcon(Icons.add_circle_outline),
            label: const Text('Dochód'),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Import z banku',
          onPressed: () {
            haptics.tap();
            context.push<void>('/transactions/import');
          },
          icon: const AppIcon(Icons.upload_file),
        ),
      ],
    );
  }
}

/// Budżety: zbiorczy ring + trzy najbardziej „gorące" kategorie.
class _BudgetsCard extends StatelessWidget {
  const _BudgetsCard({required this.budgets, required this.categories});

  final List<BudgetProgress> budgets;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 0,
    );
    final byId = {for (final c in categories) c.id: c};

    final totalLimit = budgets.fold<int>(
      0,
      (sum, p) => sum + p.budget.amountCents,
    );
    final totalSpent = budgets.fold<int>(0, (sum, p) => sum + p.spentCents);
    final fraction = totalLimit == 0 ? 0.0 : totalSpent / totalLimit;
    final ringColor = fraction >= 1
        ? cs.error
        : fraction >= 0.8
            ? AppTheme.expenseAccent
            : AppTheme.incomeAccent;

    return _V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: fraction.clamp(0.0, 1.0),
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      color: ringColor,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                    Center(
                      child: Text(
                        '${(fraction * 100).round()}%',
                        style: tt.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Budżety',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${fmt.format(totalSpent / 100)} '
                      'z ${fmt.format(totalLimit / 100)} limitów',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in budgets.take(3)) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          byId[p.budget.categoryId]?.name ?? 'Kategoria',
                          style: tt.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${fmt.format(p.spentCents / 100)}'
                        ' / ${fmt.format(p.budget.amountCents / 100)}',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: p.fraction.clamp(0.0, 1.0),
                      minHeight: 6,
                      color: p.fraction >= 1
                          ? cs.error
                          : p.fraction >= 0.8
                              ? AppTheme.expenseAccent
                              : AppTheme.incomeAccent,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Trend salda narastająco — mały, „rzut oka" wykres bez osi.
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final points = summary.runningBalancePoints;
    final accent = summary.balanceCents >= 0
        ? AppTheme.incomeAccent
        : AppTheme.expenseAccent;
    final spots = [
      for (final (i, p) in points.indexed)
        FlSpot(i.toDouble(), p.balanceCents / 100),
    ];

    return _V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saldo w czasie',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: accent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accent.withValues(alpha: 0.25),
                          accent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ],
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
              ),
              duration: const Duration(milliseconds: 400),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Każdy punkt to dzień z transakcją — linia w górę = '
            'zostaje Wam więcej.',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Trzy kategorie, które zjadają najwięcej — z udziałem procentowym.
class _TopCategoriesCard extends StatelessWidget {
  const _TopCategoriesCard({required this.summary, required this.categories});

  final DashboardSummary summary;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 0,
    );
    final byId = {for (final c in categories) c.id: c};
    final top = topExpenseCategories(summary.expenseByCategoryId);

    return _V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Na co idzie najwięcej',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final t in top) ...[
            Builder(
              builder: (context) {
                final category = byId[t.categoryId];
                final color = category != null
                    ? CategoryPalette.fromHex(category.colorHex)
                    : cs.primary;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      if (category != null)
                        CategoryAvatar(category: category, size: 32)
                      else
                        const SizedBox(width: 32, height: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    category?.name ?? 'Inne',
                                    style: tt.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${fmt.format(t.cents / 100)}'
                                  ' · ${(t.share * 100).round()}%',
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: t.share,
                                minHeight: 6,
                                color: color,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Nadchodzące płatności cykliczne (czynsz, abonamenty…) — tap otwiera
/// pełną listę.
class _UpcomingCard extends ConsumerWidget {
  const _UpcomingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final listAsync = ref.watch(recurringListProvider);
    final all = listAsync.value ?? const [];
    final upcoming = all.where((r) => r.active).toList()
      ..sort((a, b) => a.nextDue.compareTo(b.nextDue));
    if (upcoming.isEmpty) return const SizedBox.shrink();

    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 0,
    );
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _V2Card(
        onTap: () => context.push<void>('/recurring'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nadchodzące płatności',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in upcoming.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.event_repeat_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.name,
                        style: tt.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${dueLabel(r.nextDue, now)} · '
                      '${r.type == TransactionType.expense ? '−' : '+'}'
                      '${fmt.format(r.amountCents / 100)}',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ostatnie transakcje z okresu — szybki podgląd, tap = edycja.
class _RecentCard extends ConsumerWidget {
  const _RecentCard({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final txsAsync = ref.watch(filteredTransactionsProvider);
    final byId = {for (final c in categories) c.id: c};
    final txs = [...(txsAsync.value ?? const <Transaction>[])]..sort((a, b) {
        final byDate = b.occurredAt.compareTo(a.occurredAt);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });
    if (txs.isEmpty) return const SizedBox.shrink();

    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 2,
    );
    final fmtDate = DateFormat('d MMM', 'pl_PL');

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _V2Card(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ostatnie transakcje',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            for (final t in txs.take(4))
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push<void>('/transactions/edit', extra: t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      if (byId[t.categoryId] != null)
                        CategoryAvatar(
                          category: byId[t.categoryId]!,
                          size: 32,
                        )
                      else
                        const SizedBox(width: 32, height: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (t.description?.isNotEmpty ?? false)
                                  ? t.description!
                                  : byId[t.categoryId]?.name ?? 'Transakcja',
                              style: tt.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              fmtDate.format(t.occurredAt),
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${t.type == TransactionType.income ? '+' : '−'}'
                        '${fmt.format(t.amountCents / 100)}',
                        style: tt.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: t.type == TransactionType.income
                              ? AppTheme.incomeAccent
                              : AppTheme.expenseAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mała pigułka z ikoną (delta w bohaterze).
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
