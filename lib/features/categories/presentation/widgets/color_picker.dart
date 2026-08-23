import 'package:flutter/material.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Picker 12-kolorowej palety low-stimulus. Każde koło tap-em wybiera kolor.
class ColorPicker extends StatelessWidget {
  const ColorPicker({
    required this.selectedHex,
    required this.onSelected,
    super.key,
  });

  final String selectedHex;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final color in CategoryPalette.palette)
          _ColorDot(
            color: color,
            isSelected:
                _toHex(color).toUpperCase() == selectedHex.toUpperCase(),
            onTap: () => onSelected(_toHex(color)),
          ),
      ],
    );
  }

  static String _toHex(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: theme.colorScheme.onSurface, width: 3)
              : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: isSelected
            ? const AppIcon(Icons.check, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}
