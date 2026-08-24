import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/features/settings/application/theme_providers.dart';

/// Owija child w tło zależne od motywu:
/// - neon (cyber/synthwave/galaktyka) → subtelny podwójny radial gradient,
/// - Kredka → komiksowy raster kropek (halftone) na całej apce,
/// - pozostałe → child bez zmian (zero overhead).
///
/// Użyć w głównym body Scaffold'a żeby cała apka miała spójny charakter.
class NeonGradientBackground extends ConsumerWidget {
  const NeonGradientBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(themeVariantProvider);

    // Komiksowy raster kropek dla motywów komiksowych (Kredka, Manga).
    // RepaintBoundary + isComplex → Skia cache'uje raster i nie przerysowuje
    // go przy każdej klatce treści (inaczej ~1500 kropek co scroll = zacięcia).
    if (variant.isComic) {
      final ink = Theme.of(context).colorScheme.onSurface;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      // Manga = wyraźniejszy, gęstszy raster (jak screentone na zegarkach);
      // w ciemnym trybie białe kropki mocniejsze, żeby było je widać.
      final isManga = variant == AppThemeVariant.manga;
      final alpha = isManga ? (isDark ? 0.22 : 0.13) : 0.06;
      return Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _HalftonePainter(
                  ink.withValues(alpha: alpha),
                  gap: isManga ? 20 : 16,
                  dotFactor: isManga ? 0.16 : 0.09,
                ),
                isComplex: true,
              ),
            ),
          ),
          child,
        ],
      );
    }

    if (!variant.hasGradientBackground) return child;

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = scheme.primary;
    final accent = variant.gradientAccent;

    // Neo: atmosfera jak w nowoczesnych fintechach — trzy WIDOCZNE,
    // wielkie plamy światła (fiolet / magenta / cyjan) na fioletowym
    // granacie, w całej apce. Statyczne (RepaintBoundary = zero kosztu
    // przy scrollu); ruch dokłada aurora na samym pulpicie.
    if (variant == AppThemeVariant.neo) {
      final boost = isDark ? 1.0 : 0.45;
      return Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                children: [
                  _AmbientBlob(
                    center: const Alignment(-1.1, -0.95),
                    radius: 1.1,
                    color: primary,
                    alpha: 0.34 * boost,
                  ),
                  _AmbientBlob(
                    center: const Alignment(1.25, -0.1),
                    radius: 0.95,
                    color: const Color(0xFFFF4FD8), // magenta
                    alpha: 0.20 * boost,
                  ),
                  _AmbientBlob(
                    center: const Alignment(-0.5, 1.25),
                    radius: 1.05,
                    color: accent,
                    alpha: 0.18 * boost,
                  ),
                ],
              ),
            ),
          ),
          child,
        ],
      );
    }

    // W ciemnym tle gradient mocniejszy (większa alpha), bo nie ginie
    // w niebycie. W jasnym subtelny.
    final alphaPrimary = isDark ? 0.18 : 0.08;
    final alphaAccent = isDark ? 0.14 : 0.06;

    return Stack(
      children: [
        // Gradienty są statyczne — RepaintBoundary izoluje je od przerysowań
        // treści (scroll/animacje), żeby nie malowały się co klatkę.
        Positioned.fill(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.8, -0.9),
                  radius: 1.3,
                  colors: [
                    primary.withValues(alpha: alphaPrimary),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, 0.9),
                  radius: 1.3,
                  colors: [
                    accent.withValues(alpha: alphaAccent),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Jedna miękka plama światła (radial gradient do przezroczystości).
class _AmbientBlob extends StatelessWidget {
  const _AmbientBlob({
    required this.center,
    required this.radius,
    required this.color,
    required this.alpha,
  });

  final Alignment center;
  final double radius;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: center,
            radius: radius,
            colors: [color.withValues(alpha: alpha), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

/// Rysuje równomierną siatkę kropek (efekt komiksowego rastra/halftone).
class _HalftonePainter extends CustomPainter {
  _HalftonePainter(this.color, {this.gap = 16, this.dotFactor = 0.09});

  final Color color;
  final double gap;
  final double dotFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final radius = gap * dotFactor;
    for (var y = 0.0; y < size.height; y += gap) {
      for (var x = 0.0; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HalftonePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.gap != gap ||
      oldDelegate.dotFactor != dotFactor;
}
