import 'dart:math';

import 'package:flutter/material.dart';

/// Animacja "wybuch ze środka". Emoji startują w centrum, eksplodują na
/// losowe kierunki (angle 0..2π), obracają się, pulsują skalą, lecą
/// w stronę krawędzi ekranu. Po przelocie znikają fade-out.
///
/// Bardziej "śmieszne" niż prosty deszcz — każdy particle ma indywidualny
/// charakter (rotation speed, scale wave, kierunek).
class EmojiBurst extends StatefulWidget {
  const EmojiBurst({
    required this.glyphs,
    this.count = 24,
    this.duration = const Duration(milliseconds: 1300),
    super.key,
  });

  final List<String> glyphs;
  final int count;
  final Duration duration;

  static void show(
    BuildContext context, {
    required List<String> glyphs,
  }) {
    if (glyphs.isEmpty) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(child: EmojiBurst(glyphs: glyphs)),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(
      const Duration(milliseconds: 1500),
      entry.remove,
    );
  }

  @override
  State<EmojiBurst> createState() => _EmojiBurstState();
}

class _EmojiBurstState extends State<EmojiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    final rng = Random();
    _particles = List.generate(widget.count, (_) {
      return _Particle(
        glyph: widget.glyphs[rng.nextInt(widget.glyphs.length)],
        angle: rng.nextDouble() * 2 * pi,
        distance: 180.0 + rng.nextDouble() * 220,
        fontSize: 32.0 + rng.nextDouble() * 24,
        rotationSpeed: (rng.nextDouble() - 0.5) * 8,
        scaleWave: rng.nextDouble() * 0.6 + 0.4,
        startDelay: rng.nextDouble() * 0.15,
        gravity: 0.5 + rng.nextDouble() * 0.5,
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
          painter: _BurstPainter(
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
    required this.angle,
    required this.distance,
    required this.fontSize,
    required this.rotationSpeed,
    required this.scaleWave,
    required this.startDelay,
    required this.gravity,
  });

  final String glyph;
  final double angle;
  final double distance;
  final double fontSize;
  final double rotationSpeed;
  final double scaleWave;
  final double startDelay;
  final double gravity;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.t,
    required this.particles,
    required this.screenSize,
  });

  final double t;
  final List<_Particle> particles;
  final Size screenSize;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.5);
    for (final p in particles) {
      final localT = ((t - p.startDelay) / (1 - p.startDelay)).clamp(0.0, 1.0);
      if (localT == 0) continue;

      final radial = Curves.easeOut.transform(localT) * p.distance;
      final fall = p.gravity * 120 * localT * localT;

      final x = center.dx + cos(p.angle) * radial;
      final y = center.dy + sin(p.angle) * radial + fall;

      final scale = 1.0 + p.scaleWave * sin(localT * pi * 3) * (1 - localT);
      final opacity = localT < 0.7 ? 1.0 : (1 - (localT - 0.7) / 0.3);
      final rotation = p.rotationSpeed * localT;

      final tp = TextPainter(
        text: TextSpan(
          text: p.glyph,
          style: TextStyle(
            fontSize: p.fontSize * scale,
            color: Colors.white.withValues(alpha: opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas
        ..save()
        ..translate(x, y)
        ..rotate(rotation);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) => oldDelegate.t != t;
}

/// Mapowanie kategorii na zestaw emoji. Kategorie z dedykowanymi
/// animowanymi scenami (Transport, Zdrowie, Rachunki, Spożywcze) są
/// obsłużone osobnymi widgetami — tutaj pomijamy.
List<String>? emojisForCategory(String categoryName) {
  final n = categoryName.toLowerCase();
  bool has(List<String> keys) => keys.any(n.contains);

  if (has(['dziec', 'niemowl', 'maluch'])) {
    return const ['🧸', '🍼', '🎈', '🚼', '🍭'];
  }
  if (has(['rozryw', 'kino', 'gier', 'koncert'])) {
    return const ['🎬', '🍿', '🎮', '🎤', '🎉'];
  }
  if (has(['mieszk', 'dom', 'remont', 'czynsz'])) {
    return const ['🏠', '🛋️', '🪴', '🔨', '🔧'];
  }
  if (has(['ubran', 'odzież', 'butów'])) {
    return const ['👕', '👗', '👟', '🧥', '🩳'];
  }
  if (has(['subskryp', 'netflix', 'spotify'])) {
    return const ['📺', '🎵', '☁️', '🔔', '💳'];
  }
  if (has(['hobby', 'sport', 'siłow'])) {
    return const ['🏋️', '⚽', '🎨', '📚', '🎯'];
  }
  if (has(['uroda', 'kosmet', 'fryzj'])) {
    return const ['💄', '💅', '💆', '✨', '💇'];
  }
  if (has(['prezent', 'urodz', 'święt'])) {
    return const ['🎁', '🎉', '🎂', '🎈', '🎊'];
  }
  if (has(['oszczęd', 'inwest'])) {
    return const ['🐷', '💰', '📈', '🏦', '💎'];
  }
  return null;
}
