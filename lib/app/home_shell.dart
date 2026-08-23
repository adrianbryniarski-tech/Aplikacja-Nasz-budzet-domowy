import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/core/haptics.dart';
import 'package:nasz_budzet_domowy/features/budgets/presentation/budgets_screen.dart';
import 'package:nasz_budzet_domowy/features/categories/presentation/categories_screen.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/dashboard_screen.dart';
import 'package:nasz_budzet_domowy/features/investments/presentation/investments_screen.dart';
import 'package:nasz_budzet_domowy/features/onboarding/presentation/whats_new_screen.dart';
import 'package:nasz_budzet_domowy/features/settings/application/theme_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/presentation/transactions_list_screen.dart';
import 'package:nasz_budzet_domowy/shared/widgets/brand_watermark.dart';
import 'package:nasz_budzet_domowy/shared/widgets/fade_indexed_stack.dart';
import 'package:nasz_budzet_domowy/shared/widgets/glowing_button.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';
import 'package:nasz_budzet_domowy/shared/widgets/neon_gradient_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Główny shell apki z dolną nawigacją M3.
/// Pięć zakładek: Dashboard, Transakcje, Budżety, Inwestycje, Kategorie.
/// FAB (+) zawsze widoczny — na Inwestycjach dodaje pozycję portfela,
/// w pozostałych zakładkach dodaje transakcję.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _seenChangelogKey = 'last_seen_changelog';

  @override
  void initState() {
    super.initState();
    // Po pierwszym narysowaniu pokaż „Co nowego" raz, jeśli wersja zmian
    // jest nowsza niż ostatnio widziana.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWhatsNew());
  }

  Future<void> _maybeShowWhatsNew() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await showWhatsNewIfNeeded(
      context,
      seenVersion: prefs.getString(_seenChangelogKey),
      onSeen: (version) => prefs.setString(_seenChangelogKey, version),
    );
  }

  static const _screens = [
    DashboardScreen(),
    TransactionsListScreen(),
    BudgetsScreen(),
    InvestmentsScreen(),
    CategoriesScreen(),
  ];

  static const _investmentsIndex = 3;

  @override
  Widget build(BuildContext context) {
    // Ikony nawigacji zależne od motywu. Manga → ręcznie rysowane komiksowe
    // ikony; anime-motywy → tematyczny symbol pulpitu (Poké Ball / energia).
    final variant = ref.watch(themeVariantProvider);
    final isManga = variant == AppThemeVariant.manga;
    final (dashIcon, dashSelectedIcon) = switch (variant) {
      AppThemeVariant.pokemon => (
          Icons.catching_pokemon_outlined,
          Icons.catching_pokemon,
        ),
      AppThemeVariant.dragonBall => (
          Icons.brightness_7_outlined,
          Icons.brightness_7,
        ),
      _ => (Icons.dashboard_outlined, Icons.dashboard),
    };

    NavigationDestination dest(
      MangaIconKind mk,
      IconData out,
      IconData fill,
      String label,
    ) {
      return isManga
          ? NavigationDestination(
              icon: MangaIcon(mk),
              selectedIcon: MangaIcon(mk, filled: true),
              label: label,
            )
          : NavigationDestination(
              icon: Icon(out),
              selectedIcon: Icon(fill),
              label: label,
            );
    }

    return Scaffold(
      body: NeonGradientBackground(
        child: Stack(
          children: [
            FadeIndexedStack(
              index: _index,
              children: _screens,
            ),
            // Znak wodny przyklejony w lewym dolnym — pokrywa wszystkie
            // 4 zakładki, nie scrolluje z treścią.
            const BrandWatermark(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          ref.read(hapticsProvider).tap();
          setState(() => _index = i);
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          if (isManga)
            dest(
              MangaIconKind.dashboard,
              dashIcon,
              dashSelectedIcon,
              'Dashboard',
            )
          else
            NavigationDestination(
              icon: Icon(dashIcon),
              selectedIcon: Icon(dashSelectedIcon),
              label: 'Dashboard',
            ),
          dest(
            MangaIconKind.transactions,
            Icons.receipt_long_outlined,
            Icons.receipt_long,
            'Transakcje',
          ),
          dest(
            MangaIconKind.budgets,
            Icons.savings_outlined,
            Icons.savings,
            'Budżety',
          ),
          dest(
            MangaIconKind.investments,
            Icons.trending_up_outlined,
            Icons.trending_up,
            'Inwestycje',
          ),
          dest(
            MangaIconKind.categories,
            Icons.category_outlined,
            Icons.category,
            'Kategorie',
          ),
        ],
      ),
      floatingActionButton: GlowingFAB(
        onPressed: () {
          ref.read(hapticsProvider).success();
          context.push(
            _index == _investmentsIndex
                ? '/investments/add'
                : '/transactions/add',
          );
        },
        tooltip: _index == _investmentsIndex
            ? 'Dodaj inwestycję'
            : 'Dodaj transakcję',
        child: isManga
            ? const MangaIcon(MangaIconKind.add)
            : const AppIcon(Icons.add),
      ),
    );
  }
}
