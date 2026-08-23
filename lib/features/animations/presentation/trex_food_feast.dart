import 'package:flutter/material.dart';

/// Animacja: T-rex (🦖) wbiega z lewej, hamburger (🍔) z prawej — spotykają
/// się w centrum ekranu, T-rex zjada burgera (scale do 0), beknięcie 💤,
/// fade out. Ok. ~1.6 sekundy.
class TrexFoodFeast extends StatefulWidget {
  const TrexFoodFeast({super.key});

  static void show(BuildContext context) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: IgnorePointer(child: TrexFoodFeast()),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 1700), entry.remove);
  }

  @override
  State<TrexFoodFeast> createState() => _TrexFoodFeastState();
}

class _TrexFoodFeastState extends State<TrexFoodFeast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final centerY = size.height * 0.55;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        // Faza 1 (0..0.45): T-rex i hamburger zbiegają się do środka.
        // Faza 2 (0.45..0.65): T-rex pożera burgera (burger shrink to 0).
        // Faza 3 (0.65..0.85): T-rex z beknięciem.
        // Faza 4 (0.85..1.0): fade out.

        final approachT = (t / 0.45).clamp(0.0, 1.0);
        final eatT = ((t - 0.45) / 0.20).clamp(0.0, 1.0);
        final burpT = ((t - 0.65) / 0.20).clamp(0.0, 1.0);
        final fadeT = ((t - 0.85) / 0.15).clamp(0.0, 1.0);

        final globalOpacity = 1 - fadeT;

        final trexX = -80.0 + (size.width / 2 - 30) * approachT;
        final burgerX = size.width + 40.0 - (size.width / 2 + 30) * approachT;
        final burgerScale = (1 - eatT).clamp(0.0, 1.0);

        final trexBounce =
            burpT > 0 ? (1 + 0.15 * (1 - (burpT - 0.5).abs() * 2)) : 1.0;

        return Stack(
          children: [
            // Hamburger
            Positioned(
              left: burgerX,
              top: centerY - 30,
              child: Opacity(
                opacity: globalOpacity * (burgerScale > 0 ? 1.0 : 0.0),
                child: Transform.scale(
                  scale: burgerScale,
                  child: const Text('🍔', style: TextStyle(fontSize: 64)),
                ),
              ),
            ),
            // T-rex
            Positioned(
              left: trexX,
              top: centerY - 30,
              child: Opacity(
                opacity: globalOpacity,
                child: Transform.scale(
                  scale: trexBounce,
                  child: const Text('🦖', style: TextStyle(fontSize: 72)),
                ),
              ),
            ),
            // Beknięcie unosi się nad T-rexem
            if (burpT > 0)
              Positioned(
                left: trexX + 40,
                top: centerY - 40 - burpT * 30,
                child: Opacity(
                  opacity: globalOpacity * burpT * (1 - fadeT),
                  child: const Text('💤', style: TextStyle(fontSize: 24)),
                ),
              ),
          ],
        );
      },
    );
  }
}
