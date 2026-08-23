import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Kwota, która „dolicza się" płynnie do wartości (fintech count-up).
///
/// [TweenAnimationBuilder] sam retargetuje animację przy zmianie [cents]
/// (np. po zmianie okresu na pulpicie) — liczba przelatuje ze starej
/// wartości do nowej zamiast skakać.
class AnimatedAmount extends StatelessWidget {
  const AnimatedAmount({
    required this.cents,
    required this.style,
    this.decimalDigits = 2,
    super.key,
  });

  final int cents;
  final TextStyle? style;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: decimalDigits,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: cents / 100),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Text(fmt.format(value), style: style),
    );
  }
}
