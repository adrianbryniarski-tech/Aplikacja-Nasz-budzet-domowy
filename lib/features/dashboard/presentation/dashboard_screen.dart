import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/features/auth/application/auth_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/dashboard/application/dashboard_providers.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/manga_dashboard.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/widgets/balance_tile.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/widgets/budget_alerts_banner.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/widgets/category_pie_tile.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/widgets/date_range_bar.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/widgets/income_expense_bar_tile.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/widgets/portfolio_value_tile.dart';
import 'package:nasz_budzet_domowy/features/dashboard/presentation/widgets/running_balance_tile.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/household/presentation/invite_partner_sheet.dart';
import 'package:nasz_budzet_domowy/features/investments/application/investment_providers.dart';
import 'package:nasz_budzet_domowy/features/settings/application/theme_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/shared/widgets/async_error_state.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';
import 'package:nasz_budzet_domowy/shared/widgets/skeleton.dart';
import 'package:nasz_budzet_domowy/shared/widgets/sync_status_indicator.dart';

/// Ekran główny — bento grid z podsumowaniem finansów.
/// Trzyma globalny panel kontroli (sync status, odśwież, zaproś
/// partnera, ustawienia, wyloguj) — bo to pierwszy/centralny ekran.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final householdId = ref.watch(currentHouseholdIdProvider).value;
    final hasInvestments =
        (ref.watch(investmentsProvider).value ?? const []).isNotEmpty;
    final isManga = ref.watch(themeVariantProvider) == AppThemeVariant.manga;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('Nasz budżet domowy'),
          centerTitle: false,
          floating: true,
          snap: true,
          actions: [
            const SyncStatusIndicator(),
            IconButton(
              tooltip: 'Odśwież',
              icon: const AppIcon(Icons.refresh),
              onPressed: () {
                ref
                  ..invalidate(transactionsProvider)
                  ..invalidate(categoriesProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Odświeżam dane…'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            if (householdId != null)
              IconButton(
                tooltip: 'Zaproś partnera',
                icon: const AppIcon(Icons.person_add_alt),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => InvitePartnerSheet(householdId: householdId),
                ),
              ),
            PopupMenuButton<String>(
              icon: const AppIcon(Icons.more_vert),
              onSelected: (v) async {
                if (v == 'settings') {
                  await context.push<void>('/settings');
                } else if (v == 'logout') {
                  await ref.read(authRepositoryProvider).signOut();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: AppIcon(Icons.settings_outlined),
                    title: Text('Ustawienia'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: AppIcon(Icons.logout),
                    title: Text('Wyloguj'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(74),
            child: Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: DateRangeBar(),
            ),
          ),
        ),
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            ref
              ..invalidate(transactionsProvider)
              ..invalidate(categoriesProvider);
            await Future<void>.delayed(const Duration(milliseconds: 500));
          },
        ),
        // Ostrzeżenia o limitach (80% / 100%) — motyw Manga ma własny
        // panel „Wykorzystanie limitów", więc baner tylko w klasycznym.
        if (!isManga) const SliverToBoxAdapter(child: BudgetAlertsBanner()),
        summaryAsync.when(
          // Szkielet układu zamiast kółka — pulpit od razu wygląda jak
          // pulpit, tylko „wyszarzony" do czasu danych.
          loading: () => const SliverFillRemaining(
            child: DashboardSkeleton(),
          ),
          error: (e, _) => SliverFillRemaining(
            child: AsyncErrorState(
              error: e,
              onRetry: () {
                ref
                  ..invalidate(transactionsProvider)
                  ..invalidate(categoriesProvider);
              },
            ),
          ),
          data: (summary) {
            final categories = categoriesAsync.value ?? const [];
            if (isManga) {
              return SliverToBoxAdapter(
                child: MangaDashboardBody(summary: summary),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              sliver: SliverGrid(
                delegate: SliverChildListDelegate([
                  BalanceTile(summary: summary),
                  if (hasInvestments) const PortfolioValueTile(),
                  CategoryPieTile(
                    summary: summary,
                    categories: categories,
                  ),
                  IncomeExpenseBarTile(summary: summary),
                  RunningBalanceTile(summary: summary),
                ]),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 1,
                  childAspectRatio: 1.35,
                  mainAxisSpacing: 12,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
