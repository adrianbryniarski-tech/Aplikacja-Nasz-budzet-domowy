import 'dart:math';

import 'package:flutter/material.dart';

/// Animacja "Bills Attack" — papierowe rachunki 📄 spadają z każdej
/// strony, zbierają się w środku ekranu i tam zapalają się 🔥, a banknoty
/// 💸 wylatują w górę. Dla wydatków na Rachunki / Internet / Prąd.
class BillsAttack extends StatefulWidget {
  const BillsAttack({super.key});

  static void show(BuildContext context) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: IgnorePointer(child: BillsAttack()),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 2000), entry.remove);
  }

  @override
  State<BillsAttack> createState() => _BillsAttackState();
}

class _BillsAttackState extends State<BillsAttack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Bill> _bills;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..forward();
    final rng = Random();
    _bills = List.generate(8, (i) {
      // 8 rachunków z różnych kierunków (45° apart).
      return _Bill(
        startAngle: i * pi / 4,
        delay: rng.nextDouble() * 0.15,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final centerX = size.width / 2;
    final centerY = size.height * 0.5;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Faza 1 (0..0.45): rachunki lecą do środka
        // Faza 2 (0.45..0.65): płoną — 🔥 zamiast 📄
        // Faza 3 (0.55..0.95): banknoty 💸 wylatują w górę
        // Faza 4 (0.85..1.0): fade out
        final fadeT = ((t - 0.85) / 0.15).clamp(0.0, 1.0);
        final globalOpacity = 1 - fadeT;

        final bills = _bills.map<Widget>((b) {
          final localT = ((t - b.delay) / 0.45).clamp(0.0, 1.0);
          final distance = 250.0 * (1 - localT);
          final x = centerX + distance * cos(b.startAngle) - 18;
          final y = centerY + distance * sin(b.startAngle) - 18;
          final isOnFire = t > 0.45 && t < 0.7;
          final visible = localT > 0 && t < 0.7;
          return Positioned(
            left: x,
            top: y,
            child: Opacity(
              opacity: visible ? globalOpacity : 0,
              child: Transform.rotate(
                angle: localT * 4 + b.startAngle,
                child: Text(
                  isOnFire ? '🔥' : '📄',
                  style: const TextStyle(fontSize: 36),
                ),
              ),
            ),
          );
        }).toList();

        // Banknoty wylatują w górę po zapaleniu rachunków.
        final moneyT = ((t - 0.55) / 0.4).clamp(0.0, 1.0);
        final money = List<Widget>.generate(5, (i) {
          if (moneyT == 0) return const SizedBox.shrink();
          final offsetX = (i - 2) * 50.0;
          final rise = moneyT * 200;
          final moneyOpacity = moneyT < 0.7 ? 1.0 : (1 - (moneyT - 0.7) / 0.3);
          return Positioned(
            left: centerX + offsetX - 20,
            top: centerY - rise,
            child: Opacity(
              opacity: moneyOpacity * globalOpacity,
              child: Transform.rotate(
                angle: moneyT * 2 * (i.isEven ? 1 : -1),
                child: const Text('💸', style: TextStyle(fontSize: 36)),
              ),
            ),
          );
        });

        return Stack(children: [...bills, ...money]);
      },
    );
  }
}

class _Bill {
  const _Bill({required this.startAngle, required this.delay});
  final double startAngle;
  final double delay;
}
