import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/features/settings/application/theme_providers.dart';
import 'package:nasz_budzet_domowy/shared/widgets/comic_shadow.dart';

/// Kafelek bento — spójna karta dla dashboardu.
///
/// Używa Material 3 `surfaceContainerHigh` z subtelnymi zaokrągleniami
/// i bezpośrednim paddingiem. Tytuł + opcjonalny trailing w nagłówku,
/// `child` wypełnia resztę karty. Dla „Kredki" dostaje gruby obrys i
/// komiksowy cień.
class BentoTile extends ConsumerWidget {
  const BentoTile({
    required this.title,
    required this.child,
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final variant = ref.watch(themeVariantProvider);
    final isComic = variant.isComic;
    final isManga = variant == AppThemeVariant.manga;
    final ink = comicInk(variant, Theme.of(context).scaffoldBackgroundColor);

    // Manga = ośmiokątna koperta (bevel) z grubym konturem; reszta zaokrąglona.
    final ShapeBorder cardShape = isManga
        ? BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: ink, width: 4),
          )
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side:
                isComic ? BorderSide(color: ink, width: 2.5) : BorderSide.none,
          );

    final card = Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: cardShape,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: tt.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: padding,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );

    // RepaintBoundary: każdy kafelek (często z wykresem) maluje się osobno.
    return RepaintBoundary(
      child: ComicShadow(
        borderRadius: isManga ? 10 : 20,
        child: isManga
            ? Stack(
                children: [
                  card,
                  // Druga, cienka linia wewnątrz — imituje warstwy koperty.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            shape: BeveledRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                              side: BorderSide(color: ink, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : card,
      ),
    );
  }
}
