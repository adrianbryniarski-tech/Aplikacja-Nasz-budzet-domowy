import 'package:flutter/material.dart';

/// Szkielety ładowania (pulsujące prostokąty) zamiast kręcącego kółka —
/// ekran od razu pokazuje SWÓJ układ, tylko „wyszarzony". Nowoczesny
/// standard (Revolut, YouTube, LinkedIn).
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({required this.child, super.key});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

/// Pojedynczy „wyszarzony" prostokąt szkieletu.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    this.height = 16,
    this.width,
    this.radius = 12,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Szkielet pulpitu: duży kafel salda + dwa mniejsze.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: const [
          SkeletonBox(height: 200, radius: 20),
          SizedBox(height: 12),
          SkeletonBox(height: 200, radius: 20),
          SizedBox(height: 12),
          SkeletonBox(height: 200, radius: 20),
        ],
      ),
    );
  }
}

/// Szkielet listy transakcji: nagłówek dnia + wiersze wpisów.
class TransactionsSkeleton extends StatelessWidget {
  const TransactionsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SkeletonBox(height: 36, width: 36, radius: 18),
              SizedBox(width: 14),
              Expanded(child: SkeletonBox(height: 14)),
              SizedBox(width: 24),
              SkeletonBox(height: 14, width: 64),
            ],
          ),
        );

    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const SkeletonBox(height: 14, width: 80),
          const SizedBox(height: 8),
          for (var i = 0; i < 7; i++) row(),
        ],
      ),
    );
  }
}
