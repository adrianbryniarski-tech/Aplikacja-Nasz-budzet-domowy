import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/dashboard/application/dashboard_providers.dart';
import 'package:nasz_budzet_domowy/features/dashboard/data/category_breakdown.dart';
import 'package:nasz_budzet_domowy/features/dashboard/data/dashboard_summary.dart';

/// Treść pulpitu w stylu „Manga Neo-Brutalism" (wg dostarczonej makiety):
/// koperty KPI, pasek wykorzystania z rastrem, kategorie ze słupkami,
/// dymek + trend, przyciski. Płasko, twardo, ośmiokątne rogi, cienie 6px.
class MangaDashboardBody extends ConsumerWidget {
  const MangaDashboardBody({required this.summary, super.key});

  final DashboardSummary summary;

  static const _white = Color(0xFFFFFFFF);
  static const _blue = Color(0xFF59C2ED);
  static const _volt = Color(0xFFE4F523);
  static const _pink = Color(0xFFFF3366);

  String _zl(int cents) {
    final v = (cents / 100).round();
    return NumberFormat('#,###', 'pl_PL').format(v).replaceAll(',', ' ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final income = summary.totalIncomeCents;
    final expense = summary.totalExpenseCents;
    final left = income - expense;
    final usage = income > 0 ? (expense / income).clamp(0.0, 1.0) : 0.0;
    final usagePct = (usage * 100).round();

    final progress = ref.watch(periodBudgetProgressProvider);
    final categoryList =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final cats = <String, String>{
      for (final c in categoryList) c.id: c.name,
    };
    // Pełny podział wydatków wg kategorii dla wybranego okresu (niezależnie
    // od limitów) — `expenseByCategoryId` jest już odfiltrowane do zakresu.
    final spend = computeCategorySpend(
      summary.expenseByCategoryId,
      categoryList,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Podsumowanie miesiąca'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  label: 'Dochód',
                  value: _zl(income),
                  trend: 'WPŁYWY',
                  color: _white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Kpi(
                  label: 'Wydatki',
                  value: _zl(expense),
                  // Gdy jest odniesienie — porównanie z poprzednim równym
                  // okresem; inaczej udział w dochodach.
                  trend: summary.expenseDeltaPct != null
                      ? '${summary.expenseDeltaPct! >= 0 ? '+' : ''}'
                          '${summary.expenseDeltaPct}% VS POPRZ.'
                      : '$usagePct% DOCHODU',
                  color: _blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Kpi(
                  label: 'Pozostało',
                  value: _zl(left),
                  trend: left >= 0 ? 'NA PLUSIE' : 'NA MINUSIE',
                  color: left >= 0 ? _volt : _pink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _UsageBar(pct: usage, income: _zl(income)),
          const SizedBox(height: 22),
          _Panel(
            head: 'Wydatki wg kategorii',
            child: spend.isEmpty
                ? const Text(
                    'Brak wydatków w tym okresie.',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                  )
                : Column(
                    children: [
                      for (final s in spend.take(8))
                        _SpendRow(
                          name: s.name,
                          amount: _zl(s.amountCents),
                          pct: (s.fraction * 100).round(),
                          fraction: spend.first.amountCents == 0
                              ? 0
                              : s.amountCents / spend.first.amountCents,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 22),
          _Panel(
            head: 'Wykorzystanie limitów',
            child: progress.isEmpty
                ? const Text(
                    'Brak limitów. Ustaw budżety kategorii.',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                  )
                : Column(
                    children: [
                      for (final p in progress.take(7))
                        _CatRow(
                          name: cats[p.budget.categoryId] ?? 'Kategoria',
                          spent: _zl(p.spentCents),
                          limit: _zl(p.budget.amountCents),
                          fraction: p.fraction.clamp(0.0, 1.0),
                          over: p.isExceeded,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 22),
          _Panel(
            head: 'Trend wydatków',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (progress.any((p) => p.isExceeded))
                  const _Bubble('Niektóre kategorie po limicie!')
                else
                  const _Bubble('Wydatki w normie. Tak trzymać!'),
                const SizedBox(height: 18),
                _Trend(buckets: summary.barBuckets),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _Btn(
                        label: 'Dodaj wydatek',
                        color: _blue,
                        onTap: () => context.push('/transactions/add'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Btn(
                        label: 'Limity',
                        color: _pink,
                        onTap: () => context.push('/settings'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== KOMPONENTY =====================

const _ink = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);
const _pink = Color(0xFFFF3366);

/// Tytuł sekcji — czarny chip z białym tekstem (Archivo Black).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = _inkFor(context);
    final onInk = ink == _white ? _ink : _white;
    return Container(
      color: ink,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'ArchivoBlack',
          color: onInk,
          fontSize: 14,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Koperta KPI — ośmiokąt, gruby kontur, twardy cień, kolorowy środek.
class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.trend,
    required this.color,
  });

  final String label;
  final String value;
  final String trend;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ink = _inkFor(context);
    final onInk = ink == _white ? _ink : _white;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: BeveledRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: ink, width: 4),
        ),
        color: ink,
        shadows: [BoxShadow(color: ink, offset: const Offset(6, 6))],
      ),
      child: Container(
        decoration: ShapeDecoration(
          shape: const BeveledRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          color: color,
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        constraints: const BoxConstraints(minHeight: 122),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 1,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontFamily: 'ArchivoBlack',
                  fontSize: 26,
                  color: _ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              color: ink,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                trend,
                style: TextStyle(
                  color: onInk,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Biały panel z konturem 4px i twardym cieniem 6px + nagłówek z linią.
class _Panel extends StatelessWidget {
  const _Panel({required this.head, required this.child});
  final String head;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ink = _inkFor(context);
    final surface = Theme.of(context).colorScheme.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: ink, width: 4),
        boxShadow: [BoxShadow(color: ink, offset: const Offset(6, 6))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: ink, width: 2)),
              ),
              child: Text(
                head.toUpperCase(),
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Duży pasek wykorzystania dochodu — track z rastrowym wypełnieniem.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.pct, required this.income});
  final double pct;
  final String income;

  @override
  Widget build(BuildContext context) {
    final ink = _inkFor(context);
    final onInk = ink == _white ? _ink : _white;
    final surface = Theme.of(context).colorScheme.surface;
    final over = pct >= 0.9;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: ink, width: 4),
        boxShadow: [BoxShadow(color: ink, offset: const Offset(6, 6))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'WYKORZYSTANIE DOCHODU',
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                ),
                Container(
                  color: ink,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(
                    '${(pct * 100).round()}%',
                    style: TextStyle(
                      fontFamily: 'ArchivoBlack',
                      color: onInk,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: DecoratedBox(
                decoration:
                    BoxDecoration(border: Border.all(color: ink, width: 4)),
                child: Row(
                  children: [
                    Expanded(
                      flex: (pct * 100).round().clamp(1, 100),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border:
                              Border(right: BorderSide(color: ink, width: 4)),
                        ),
                        child: over
                            ? const ColoredBox(color: _pink)
                            : _Halftone(ink: ink, dotSpacing: 7, dot: 0.26),
                      ),
                    ),
                    Expanded(
                      flex: (100 - (pct * 100).round()).clamp(0, 99),
                      child: const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _foot('0 ZŁ', ink),
                _foot('PRÓG 90%', ink),
                _foot('$income ZŁ', ink),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _foot(String t, Color ink) => Text(
        t,
        style: TextStyle(
          color: ink,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 1,
        ),
      );
}

/// Wiersz kategorii — etykiety + słupek (raster lub róż gdy po limicie).
class _CatRow extends StatelessWidget {
  const _CatRow({
    required this.name,
    required this.spent,
    required this.limit,
    required this.fraction,
    required this.over,
  });

  final String name;
  final String spent;
  final String limit;
  final double fraction;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final ink = _inkFor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: .5,
                  ),
                ),
              ),
              Text(
                '$spent / $limit ZŁ',
                style: TextStyle(color: ink, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 20,
            child: DecoratedBox(
              decoration:
                  BoxDecoration(border: Border.all(color: ink, width: 2)),
              child: Row(
                children: [
                  Expanded(
                    flex: (fraction * 100).round().clamp(1, 100),
                    child: over
                        ? const ColoredBox(color: _pink)
                        : _Halftone(ink: ink, dotSpacing: 6, dot: 0.22),
                  ),
                  Expanded(
                    flex: (100 - (fraction * 100).round()).clamp(0, 99),
                    child: const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wiersz podziału wydatków — nazwa, kwota + %, raster proporcjonalny do
/// największej kategorii w okresie.
class _SpendRow extends StatelessWidget {
  const _SpendRow({
    required this.name,
    required this.amount,
    required this.pct,
    required this.fraction,
  });

  final String name;
  final String amount;
  final int pct;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final ink = _inkFor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: .5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$amount ZŁ · $pct%',
                style: TextStyle(color: ink, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 20,
            child: DecoratedBox(
              decoration:
                  BoxDecoration(border: Border.all(color: ink, width: 2)),
              child: Row(
                children: [
                  Expanded(
                    flex: (fraction * 100).round().clamp(1, 100),
                    child: _Halftone(ink: ink, dotSpacing: 6, dot: 0.22),
                  ),
                  Expanded(
                    flex: (100 - (fraction * 100).round()).clamp(0, 99),
                    child: const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dymek komiksowy (alert) — róż, kontur, ostry ogonek.
class _Bubble extends StatelessWidget {
  const _Bubble(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = _inkFor(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: _pink,
            border: Border.all(color: ink, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              text,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -10,
          left: 22,
          child: CustomPaint(
            size: const Size(16, 12),
            painter: _TailPainter(ink),
          ),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.2, size.height)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = _pink)
      ..drawPath(
        path,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.ink != ink;
}

/// Wykres trendu — słupki z rastrem + plakietka wartości; ostatni = róż.
class _Trend extends StatelessWidget {
  const _Trend({required this.buckets});
  final List<BarBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final ink = _inkFor(context);
    final onInk = ink == _white ? _ink : _white;
    if (buckets.isEmpty) {
      return Text(
        'BRAK DANYCH',
        style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 11),
      );
    }
    final bars =
        buckets.length > 6 ? buckets.sublist(buckets.length - 6) : buckets;
    final maxExp =
        bars.map((b) => b.expenseCents).fold(1, (a, b) => a > b ? a : b);
    final fmt = DateFormat('LLL', 'pl_PL');
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      color: ink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        '${(bars[i].expenseCents / 100).round()}',
                        style: TextStyle(
                          color: onInk,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 78 *
                          (maxExp == 0 ? 0.0 : bars[i].expenseCents / maxExp)
                              .clamp(0.05, 1.0),
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: ink, width: 2),
                        ),
                        child: i == bars.length - 1
                            ? const ColoredBox(color: _pink)
                            : _Halftone(ink: ink, dotSpacing: 6, dot: 0.16),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fmt.format(bars[i].date).toUpperCase(),
                      style: TextStyle(
                        color: ink,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Przycisk neo-brutalist — kontur 4px, twardy cień, wciśnięcie.
class _Btn extends StatefulWidget {
  const _Btn({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final ink = _inkFor(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _down = false),
      child: Transform.translate(
        offset: _down ? const Offset(5, 5) : Offset.zero,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.color,
            border: Border.all(color: ink, width: 4),
            boxShadow: _down
                ? null
                : [BoxShadow(color: ink, offset: const Offset(5, 5))],
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rastrowe (halftone) wypełnienie słupka.
class _Halftone extends StatelessWidget {
  const _Halftone({
    required this.ink,
    required this.dotSpacing,
    required this.dot,
  });
  final Color ink;
  final double dotSpacing;
  final double dot;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary + isComplex → Skia cache'uje raster jako gotowy obrazek
    // (dziesiątki kropek × kilkanaście słupków = inaczej zacięcia przy każdej
    // klatce/scrollu).
    return RepaintBoundary(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: CustomPaint(
          size: Size.infinite,
          isComplex: true,
          painter: _HalftoneFill(ink: ink, spacing: dotSpacing, dotFactor: dot),
        ),
      ),
    );
  }
}

class _HalftoneFill extends CustomPainter {
  _HalftoneFill({
    required this.ink,
    required this.spacing,
    required this.dotFactor,
  });
  final Color ink;
  final double spacing;
  final double dotFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = ink;
    final r = spacing * dotFactor * 2;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), r, p);
      }
    }
  }

  @override
  bool shouldRepaint(_HalftoneFill old) =>
      old.ink != ink || old.spacing != spacing || old.dotFactor != dotFactor;
}

Color _inkFor(BuildContext context) {
  final bg = Theme.of(context).scaffoldBackgroundColor;
  return bg.computeLuminance() < 0.35 ? _white : _ink;
}
