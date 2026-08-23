import 'dart:math';

import 'package:flutter/material.dart';

/// Animacja: z górnej krawędzi ekranu spada N emoji-monet/banknotów.
/// Pokazywana jako fullscreen Overlay przez ~1.5s przy dodaniu dochodu.
///
/// Implementacja: jeden `AnimationController` (0..1) driver'uje N
/// `_Particle` (random start x, random fall speed, random rotation),
/// `CustomPaint` rysuje wszystkie w jednym repaint cyklu — taniej niż
/// N osobnych widgetów z AnimationBuildera.
class MoneyRain extends StatefulWidget {
  const MoneyRain({
    this.duration = const Duration(milliseconds: 3000),
    super.key,
  });

  final Duration duration;

  /// Pokazuje animację jako Overlay nad bieżącym ekranem.
  /// Automatycznie się ściąga po zakończeniu — caller nie musi sprzątać.
  static void show(BuildContext context, {Duration? duration}) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final effective = duration ?? const Duration(milliseconds: 3000);
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: MoneyRain(duration: effective),
        ),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(
      effective + const Duration(milliseconds: 300),
      entry.remove,
    );
  }

  @override
  State<MoneyRain> createState() => _MoneyRainState();
}

class _MoneyRainState extends State<MoneyRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  static const _glyphs = ['💵', '💰', '💸', '🪙', '💶', '💴'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    final rng = Random();
    // Każda cząstka: indywidualny `fallDuration` (10-45% długości animacji)
    // + indywidualny `fallDelay` rozłożony na 0..80% długości. Razem to
    // znaczy że monety spadają losowo przez cały czas — nie wszystkie
    // na raz, nie wszystkie z góry. ~50 cząstek przy duracji 3s.
    _particles = List.generate(48, (_) {
      return _Particle(
        glyph: _glyphs[rng.nextInt(_glyphs.length)],
        startXFraction: rng.nextDouble(),
        fontSize: 22.0 + rng.nextDouble() * 28,
        rotation: (rng.nextDouble() - 0.5) * 0.8,
        fallDelay: rng.nextDouble() * 0.8,
        fallDuration: 0.10 + rng.nextDouble() * 0.35,
        horizontalSway: (rng.nextDouble() - 0.5) * 70,
        rotationSpeed: (rng.nextDouble() - 0.5) * 2.5,
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _RainPainter(
            t: _controller.value,
            particles: _particles,
            screenSize: MediaQuery.of(context).size,
          ),
          size: MediaQuery.of(context).size,
        );
      },
    );
  }
}

class _Particle {
  const _Particle({
    required this.glyph,
    required this.startXFraction,
    required this.fontSize,
    required this.rotation,
    required this.fallDelay,
    required this.fallDuration,
    required this.horizontalSway,
    required this.rotationSpeed,
  });

  final String glyph;
  final double startXFraction;
  final double fontSize;
  final double rotation;

  /// Kiedy ta cząstka zaczyna spadać (0..1 jako frakcja całej animacji).
  final double fallDelay;

  /// Jak długo spada od pojawienia się (0..1 jako frakcja całej animacji).
  /// Mniejsza = szybsza, większa = wolniejsza.
  final double fallDuration;
  final double horizontalSway;
  final double rotationSpeed;
}

class _RainPainter extends CustomPainter {
  _RainPainter({
    required this.t,
    required this.particles,
    required this.screenSize,
  });

  final double t;
  final List<_Particle> particles;
  final Size screenSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Indywidualny przedział życia tej cząstki: [fallDelay, fallDelay
      // + fallDuration]. Poza tym przedziałem nie rysujemy.
      final localT = (t - p.fallDelay) / p.fallDuration;
      if (localT <= 0 || localT > 1.0) continue;

      final startY = -p.fontSize;
      final endY = size.height + p.fontSize;
      final y = startY + (endY - startY) * localT;

      final swayProgress = localT * 2 * pi;
      final x =
          p.startXFraction * size.width + sin(swayProgress) * p.horizontalSway;

      // Fade-in pierwsze 10%, fade-out ostatnie 15%. Środek pełna widoczność.
      final opacity = localT < 0.10
          ? localT / 0.10
          : (localT < 0.85 ? 1.0 : (1 - (localT - 0.85) / 0.15));
      final rotationNow = p.rotation + localT * pi * 2 * p.rotationSpeed;

      final tp = TextPainter(
        text: TextSpan(
          text: p.glyph,
          style: TextStyle(
            fontSize: p.fontSize,
            color: Colors.white.withValues(alpha: opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas
        ..save()
        ..translate(x, y)
        ..rotate(rotationNow);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) => oldDelegate.t != t;
}
