import 'dart:math';

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

/// Nowy pulpit („Pulpit 2.0") — projekt wg języka nowoczesnych fintechów.
///
/// Zasady przeniesione z referencji (FLEX/Finity-podobne dashboardy,
/// „Stripe visual language", metoda dataviz):
/// - JEDEN nasycony, gradientowy obiekt-bohater (karta salda jak karta
///   premium) — reszta ekranu to spokojne szkło, więc bohater niesie
///   cały „wow";
/// - typografia robi hierarchię: wielkie tabelaryczne liczby (Inter /
///   Inter Display), malutkie wersalikowe etykiety, wyciszone opisy;
/// - kolor żyje W DANYCH: gradientowa linia wykresu ze świecącym
///   punktem „dziś", sweep-gradient na ringu budżetów, paski postępu
///   z zaokrąglonymi końcami — a NIE w poświatach na tekstach;
/// - szkło bez tęczowych ramek: półprzezroczysta powierzchnia nad
///   ambientem + cienka jasna ramka 1px (jak frosted glass);
/// - wszystko na tokenach motywu — na motywach nie-neonowych karty są
///   zwykłe, a bohater przechodzi na kolory motywu.
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

    // Kolejne karty wjeżdżają z lekkim poślizgiem (raz, przy wejściu).
    var order = 0;
    Widget entrance(Widget child) => _Entrance(index: order++, child: child);

    return Stack(
      children: [
        // Dryfujące plamy światła za kartami — tylko motywy neonowe.
        const Positioned.fill(child: _AuroraBackdrop()),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              entrance(_HeroCard(summary: summary, range: range)),
              const SizedBox(height: 12),
              entrance(
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
              ),
              const SizedBox(height: 12),
              entrance(const _QuickActionsRow()),
              if (budgets.isNotEmpty) ...[
                const SizedBox(height: 12),
                entrance(
                  _BudgetsCard(budgets: budgets, categories: categories),
                ),
              ],
              if (summary.runningBalancePoints.length >= 2) ...[
                const SizedBox(height: 12),
                entrance(_TrendCard(summary: summary)),
              ],
              if (summary.expenseByCategoryId.isNotEmpty) ...[
                const SizedBox(height: 12),
                entrance(
                  _TopCategoriesCard(
                    summary: summary,
                    categories: categories,
                  ),
                ),
              ],
              entrance(const _UpcomingCard()),
              entrance(_RecentCard(categories: categories)),
            ],
          ),
        ),
      ],
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

/// Jaka część okresu już MINĘŁA (0..1) — cienka linia postępu na
/// bohaterze. `null` gdy okres nie obejmuje dzisiaj.
double? elapsedFractionOfRange({
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final first = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final last = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  if (today.isBefore(first) || today.isAfter(last)) return null;
  final total = last.difference(first).inDays + 1;
  final gone = today.difference(first).inDays + 1;
  return (gone / total).clamp(0.0, 1.0);
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
// Typografia liczb — tabelaryczne cyfry, ciasny tracking.
// ---------------------------------------------------------------------------

/// Styl dużych liczb: tabelaryczne cyfry (równe kolumny — cyfry nie
/// „skaczą" przy count-upie), ciasny tracking, wysokość 1.0.
/// Na Neo dodatkowo Inter/Inter Display (reszta motywów: krój motywu).
TextStyle _numStyle(
  TextStyle? base, {
  required bool neonFont,
  double? size,
  FontWeight weight = FontWeight.w700,
  Color? color,
  bool display = false,
}) {
  return (base ?? const TextStyle()).copyWith(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1,
    letterSpacing: display ? -1.2 : -0.3,
    fontFamily: neonFont ? (display ? 'InterDisplay' : 'Inter') : null,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Malutka wersalikowa etykieta (jak w referencjach: cichy podpis nad
/// wielką liczbą).
TextStyle _labelStyle(TextStyle? base, Color color) {
  return (base ?? const TextStyle()).copyWith(
    fontSize: 10.5,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w600,
    color: color,
  );
}

// ---------------------------------------------------------------------------
// Karty.
// ---------------------------------------------------------------------------

/// Wspólna baza kart V2 — „frosted glass" bez tęczy:
/// - motywy neonowe: półprzezroczysta powierzchnia nad ambientem +
///   cienka JASNA ramka 1px (biel ~10%), duży promień;
/// - motywy komiksowe: gruby kontur + komiksowy cień (jak wszędzie);
/// - reszta: zwykła karta z tokenów.
class _V2Card extends ConsumerWidget {
  const _V2Card({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final variant = ref.watch(themeVariantProvider);
    final ink = comicInk(variant, Theme.of(context).scaffoldBackgroundColor);
    final neon = variant.hasNeonEffects;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final fill = neon
        ? cs.surfaceContainerHigh.withValues(alpha: isDark ? 0.55 : 0.72)
        : cs.surfaceContainerHigh;
    final border = variant.isComic
        ? Border.all(color: ink, width: 2.5)
        : neon
            ? Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.06),
              )
            : null;

    final card = Material(
      color: fill,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: border,
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

/// Bohater pulpitu — JEDYNY nasycony obiekt na ekranie, jak karta
/// premium z referencji: pełny gradient indygo→fiolet→cyjan, wielka
/// biała liczba (Inter Display, tabelaryczna), delta w białej pigułce,
/// cienka linia postępu okresu i podpowiedź „ile dziennie".
class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.summary, required this.range});

  final DashboardSummary summary;
  final DateRangeFilter range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final variant = ref.watch(themeVariantProvider);
    final neon = variant.hasNeonEffects;
    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 0,
    );
    final positive = summary.balanceCents >= 0;
    final delta = summary.deltaCents;
    final deltaUp = delta >= 0;
    final now = DateTime.now();
    final perDay = safeToSpendPerDayCents(
      balanceCents: summary.balanceCents,
      rangeStart: range.start,
      rangeEnd: range.end,
      now: now,
    );
    final elapsed = elapsedFractionOfRange(
      rangeStart: range.start,
      rangeEnd: range.end,
      now: now,
    );

    // Kolory bohatera. Neon: nasycony gradient (ujemne saldo = gradient
    // w czerwieniach — kolor niesie znaczenie). Inne motywy: zalew
    // primary na tokenach, kolory tekstu z motywu.
    final Gradient bg;
    final Color onHero;
    final Color onHeroMuted;
    if (neon) {
      bg = positive
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(cs.primary, const Color(0xFF5B4CFF), 0.4)!,
                const Color(0xFF8B5CF6),
                Color.lerp(variant.gradientAccent, Colors.black, 0.05)!,
              ],
            )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF56233E), Color(0xFFB0436E)],
            );
      onHero = Colors.white;
      onHeroMuted = Colors.white.withValues(alpha: 0.72);
    } else {
      bg = LinearGradient(
        colors: [
          Color.alphaBlend(
            cs.primary.withValues(alpha: 0.16),
            cs.surfaceContainerHigh,
          ),
          cs.surfaceContainerHigh,
        ],
      );
      onHero = positive ? AppTheme.incomeAccent : AppTheme.expenseAccent;
      onHeroMuted = cs.onSurfaceVariant;
    }

    final ink = comicInk(variant, Theme.of(context).scaffoldBackgroundColor);
    final card = Container(
      decoration: BoxDecoration(
        gradient: bg,
        borderRadius: BorderRadius.circular(28),
        border: variant.isComic ? Border.all(color: ink, width: 2.5) : null,
        boxShadow: neon
            ? [
                BoxShadow(
                  color: (positive ? cs.primary : const Color(0xFFB0436E))
                      .withValues(alpha: 0.35),
                  blurRadius: 36,
                  offset: const Offset(0, 10),
                  spreadRadius: -8,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Dekoracyjne, ledwo widoczne okręgi — jak na kartach premium.
          if (neon) ...[
            const _DecorCircle(right: -70, top: -80, size: 220, alpha: 0.10),
            const _DecorCircle(right: 30, bottom: -110, size: 180, alpha: 0.07),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ZOSTAŁO W TYM OKRESIE',
                        style: _labelStyle(tt.labelSmall, onHeroMuted),
                      ),
                    ),
                    _Pill(
                      icon: deltaUp
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      label: '${deltaUp ? '+' : ''}${fmt.format(delta / 100)}',
                      color: neon
                          ? Colors.white
                          : (deltaUp
                              ? AppTheme.incomeAccent
                              : AppTheme.expenseAccent),
                      onGradient: neon,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AnimatedAmount(
                    cents: summary.balanceCents,
                    style: _numStyle(
                      tt.displayLarge,
                      neonFont: neon,
                      size: 46,
                      color: onHero,
                      display: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (elapsed != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                              color: neon
                                  ? Colors.white.withValues(alpha: 0.22)
                                  : cs.surfaceContainerHighest,
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: elapsed,
                            child: ColoredBox(
                              color: neon ? Colors.white : cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  perDay != null
                      ? '≈ ${fmt.format(perDay / 100)} dziennie · zostało '
                          '${daysLeftInRange(range.end, now)} dni'
                      : positive
                          ? 'Dochody minus wydatki w wybranym okresie.'
                          : 'W tym okresie wydaliście więcej, niż weszło.',
                  style: tt.bodySmall?.copyWith(color: onHeroMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return RepaintBoundary(child: ComicShadow(borderRadius: 28, child: card));
  }
}

/// Ledwo widoczny biały okrąg — dekoracja bohatera.
class _DecorCircle extends StatelessWidget {
  const _DecorCircle({
    required this.size,
    required this.alpha,
    this.right,
    this.top,
    this.bottom,
  });

  final double size;
  final double alpha;
  final double? right;
  final double? top;
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: alpha),
            width: 24,
          ),
        ),
      ),
    );
  }
}

/// Mały kafelek statystyki (Dochody / Wydatki): cicha etykieta
/// wersalikami, duża tabelaryczna liczba w kolorze znaczenia.
class _MiniStatCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final neon = ref.watch(themeVariantProvider).hasNeonEffects;
    return _V2Card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: _labelStyle(tt.labelSmall, cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedAmount(
              cents: cents,
              decimalDigits: 0,
              style: _numStyle(
                tt.titleLarge,
                neonFont: neon,
                size: 24,
                color: accent,
              ),
            ),
          ),
          if (deltaPct != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
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

/// Szybkie akcje jak w referencjach (Deposit/Transfer): jedna pełna
/// pigułka, jedna stonowana i okrągły przycisk importu.
class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final haptics = ref.read(hapticsProvider);
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: () {
              haptics.tap();
              context.push<void>(
                '/transactions/add',
                extra: const TransactionPrefill(type: TransactionType.expense),
              );
            },
            icon: const AppIcon(Icons.remove_circle_outline, size: 20),
            label: const Text('Wydatek'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: () {
              haptics.tap();
              context.push<void>(
                '/transactions/add',
                extra: const TransactionPrefill(type: TransactionType.income),
              );
            },
            icon: const AppIcon(Icons.add_circle_outline, size: 20),
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

/// Budżety: gauge ze sweep-gradientem (jak w referencyjnych neonowych
/// infografikach) + trzy najbardziej „gorące" kategorie z paskami.
class _BudgetsCard extends ConsumerWidget {
  const _BudgetsCard({required this.budgets, required this.categories});

  final List<BudgetProgress> budgets;
  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(themeVariantProvider);
    final neon = variant.hasNeonEffects;
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

    // Status ma zarezerwowane kolory: zdrowo = gradient marki (neon) /
    // zieleń, blisko limitu = pomarańcz, przekroczone = czerwień.
    final healthy = fraction < 0.8;
    final statusColor = fraction >= 1
        ? cs.error
        : fraction >= 0.8
            ? AppTheme.expenseAccent
            : AppTheme.incomeAccent;
    final ringGradient = neon && healthy
        ? [cs.primary, variant.gradientAccent]
        : [statusColor, statusColor];

    return _V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CustomPaint(
                  painter: _GaugePainter(
                    fraction: fraction.clamp(0.0, 1.0),
                    colors: ringGradient,
                    track: neon
                        ? Colors.white.withValues(alpha: 0.10)
                        : cs.surfaceContainerHighest,
                  ),
                  child: Center(
                    child: Text(
                      '${(fraction * 100).round()}%',
                      style: _numStyle(
                        tt.labelSmall,
                        neonFont: neon,
                        size: 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 2),
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
          const SizedBox(height: 14),
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
                        style: _numStyle(
                          tt.labelSmall,
                          neonFont: neon,
                          size: 11,
                          weight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _Bar(
                    value: p.fraction.clamp(0.0, 1.0),
                    color: p.fraction >= 1
                        ? cs.error
                        : p.fraction >= 0.8
                            ? AppTheme.expenseAccent
                            : AppTheme.incomeAccent,
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

/// Gauge 270° ze sweep-gradientem i zaokrąglonymi końcami.
class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.fraction,
    required this.colors,
    required this.track,
  });

  final double fraction;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    // 270° łuku, otwarcie na dole (jak w referencyjnych gauge'ach).
    const startAngle = 3 * pi / 4;
    const sweepMax = 3 * pi / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arcRect, startAngle, sweepMax, false, trackPaint);

    if (fraction <= 0) return;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepMax,
        colors: colors,
        transform: const GradientRotation(0),
      ).createShader(rect);
    canvas.drawArc(
      arcRect,
      startAngle,
      sweepMax * fraction,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.colors != colors || old.track != track;
}

/// Trend salda — linia malowana gradientem marki ze świecącym punktem
/// na OSTATNIM dniu (kolor w danych, nie w poświacie).
class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(themeVariantProvider);
    final neon = variant.hasNeonEffects;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final points = summary.runningBalancePoints;
    final accent = summary.balanceCents >= 0
        ? AppTheme.incomeAccent
        : AppTheme.expenseAccent;
    final lineColors =
        neon ? [cs.primary, variant.gradientAccent] : [accent, accent];
    final spots = [
      for (final (i, p) in points.indexed)
        FlSpot(i.toDouble(), p.balanceCents / 100),
    ];
    final lastX = (points.length - 1).toDouble();

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
            height: 92,
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    gradient: LinearGradient(colors: lineColors),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    // Świecący punkt tylko na "dzisiaj" (ostatni pomiar).
                    dotData: FlDotData(
                      checkToShowDot: (spot, bar) => spot.x == lastX,
                      getDotPainter: (spot, pct, bar, idx) =>
                          FlDotCirclePainter(
                        radius: 3.5,
                        color: Colors.white,
                        strokeWidth: 4,
                        strokeColor: lineColors.last.withValues(alpha: 0.45),
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          lineColors.first.withValues(alpha: 0.20),
                          lineColors.last.withValues(alpha: 0),
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
          const SizedBox(height: 6),
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
class _TopCategoriesCard extends ConsumerWidget {
  const _TopCategoriesCard({required this.summary, required this.categories});

  final DashboardSummary summary;
  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final neon = ref.watch(themeVariantProvider).hasNeonEffects;
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
                                  style: _numStyle(
                                    tt.labelSmall,
                                    neonFont: neon,
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            _Bar(value: t.share, color: color),
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

/// Nadchodzące płatności cykliczne — tap otwiera pełną listę.
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
                        borderRadius: BorderRadius.circular(10),
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
    final neon = ref.watch(themeVariantProvider).hasNeonEffects;
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
                        style: _numStyle(
                          tt.bodySmall,
                          neonFont: neon,
                          size: 13,
                          weight: FontWeight.w600,
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

/// Pasek postępu z zaokrąglonymi końcami; na neonach delikatny gradient
/// w stronę akcentu motywu (kolor w danych, bez poświat).
class _Bar extends ConsumerWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(themeVariantProvider);
    final cs = Theme.of(context).colorScheme;
    final neon = variant.hasNeonEffects;
    final track = neon
        ? Colors.white.withValues(alpha: 0.10)
        : cs.surfaceContainerHighest;
    return SizedBox(
      height: 6,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: neon
                    ? LinearGradient(
                        colors: [
                          color,
                          Color.lerp(color, variant.gradientAccent, 0.45)!,
                        ],
                      )
                    : null,
                color: neon ? null : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Jednorazowe wejście karty: przesunięcie z dołu + pojawienie, z lekkim
/// poślizgiem zależnym od pozycji. Czysto kosmetyczne, ~pół sekundy.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.09).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// Ambientowe tło „aurora": trzy wielkie, miękkie plamy światła
/// (primary, akcent motywu i magenta), które bardzo powoli dryfują.
/// Tylko motywy neonowe — na pozostałych nic nie rysujemy i nie tyka
/// żaden ticker (ta sama zasada co AnimatedNeonBorder).
class _AuroraBackdrop extends ConsumerStatefulWidget {
  const _AuroraBackdrop();

  @override
  ConsumerState<_AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends ConsumerState<_AuroraBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final variant = ref.watch(themeVariantProvider);
    if (!variant.hasNeonEffects) {
      if (_controller.isAnimating) _controller.stop();
      return const SizedBox.shrink();
    }
    if (!_controller.isAnimating) _controller.repeat();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _AuroraPainter(
            t: _controller.value,
            primary: cs.primary,
            accent: variant.gradientAccent,
            isDark: isDark,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter({
    required this.t,
    required this.primary,
    required this.accent,
    required this.isDark,
  });

  final double t;
  final Color primary;
  final Color accent;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = t * 2 * pi;
    // Statyczny ambient daje bazę w NeonGradientBackground — aurora
    // tylko dokłada RUCH, więc jest delikatniejsza.
    final base = isDark ? 0.20 : 0.09;
    final radius = size.shortestSide * 0.85;

    void blob(Color color, double cx, double cy, double alpha) {
      final center = Offset(cx * size.width, cy * size.height);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    blob(
      primary,
      0.15 + 0.10 * sin(phase),
      0.12 + 0.08 * cos(phase * 0.8),
      base,
    );
    blob(
      accent,
      0.85 + 0.09 * cos(phase * 0.7),
      0.35 + 0.10 * sin(phase * 0.9),
      base * 0.75,
    );
    blob(
      const Color(0xFFFF4FD8),
      0.35 + 0.12 * sin(phase * 0.6 + 2),
      0.85 + 0.07 * cos(phase * 0.5 + 1),
      base * 0.55,
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) => oldDelegate.t != t;
}

/// Mała pigułka z ikoną (delta w bohaterze). Na gradientowym tle:
/// biała półprzezroczysta; na zwykłym: barwiona kolorem znaczenia.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
    this.onGradient = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final bg = onGradient
        ? Colors.white.withValues(alpha: 0.16)
        : color.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
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
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
