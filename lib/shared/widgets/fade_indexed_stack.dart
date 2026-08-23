import 'package:flutter/material.dart';

/// [IndexedStack] z krótkim cross-fade przy zmianie indeksu.
///
/// Zwykły IndexedStack tnie „na twardo" — zmiana zakładki wygląda jak
/// teleport. Tu nowa zakładka wjeżdża płynnym fade (220 ms) z delikatnym
/// powiększeniem, a stan wszystkich zakładek zostaje zachowany (to nadal
/// IndexedStack pod spodem).
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    required this.index,
    required this.children,
    super.key,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.985, end: 1).animate(fade),
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}
