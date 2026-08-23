import 'package:flutter/material.dart';

/// Animacja "Car Rush" — 🚗 przejeżdża przez ekran z lewej do prawej,
/// zostawiając za sobą chmurkę dymu 💨 i lecące pieniądze 💸. Uruchamia
/// się przy wydatku na Transport / Paliwo.
class CarRush extends StatefulWidget {
  const CarRush({super.key});

  static void show(BuildContext context) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: IgnorePointer(child: CarRush()),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 1900), entry.remove);
  }

  @override
  State<CarRush> createState() => _CarRushState();
}

class _CarRushState extends State<CarRush> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
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
        final fadeT = ((t - 0.85) / 0.15).clamp(0.0, 1.0);
        final globalOpacity = 1 - fadeT;

        // Samochód przejeżdża od x=-100 do x=screen+100. Szybkie tempo.
        final carT = Curves.easeInOut.transform((t / 0.85).clamp(0.0, 1.0));
        final carX = -100.0 + (size.width + 200) * carT;
        // Bouncing samochodu (kiwa się "jadąc po wybojach").
        final carBounce = (carT * 8).floor().isEven ? -2.0 : 2.0;

        // Dymy + pieniądze za samochodem. Pokazujemy 6 cząstek, każda
        // zaczyna w pozycji samochodu w przeszłości i fade-outuje.
        final particles = List<Widget>.generate(6, (i) {
          final particleDelay = i * 0.08;
          final pT = (t - particleDelay).clamp(0.0, 1.0);
          if (pT <= 0) return const SizedBox.shrink();
          final pCarX = -100.0 +
              (size.width + 200) *
                  Curves.easeInOut.transform(
                    ((t - particleDelay) / 0.85).clamp(0.0, 1.0),
                  );
          final age = t - particleDelay;
          final pOpacity = (1 - age * 2).clamp(0.0, 1.0);
          final pRise = age * 60;
          return Positioned(
            left: pCarX,
            top: centerY + 30 - pRise,
            child: Opacity(
              opacity: pOpacity * globalOpacity,
              child: Text(
                i.isEven ? '💨' : '💸',
                style: const TextStyle(fontSize: 28),
              ),
            ),
          );
        });

        return Stack(
          children: [
            ...particles,
            Positioned(
              left: carX,
              top: centerY + carBounce,
              child: Opacity(
                opacity: globalOpacity,
                child: const Text('🚗', style: TextStyle(fontSize: 64)),
              ),
            ),
          ],
        );
      },
    );
  }
}
