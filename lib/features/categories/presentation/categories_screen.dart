import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/categories/presentation/widgets/category_edit_sheet.dart';
import 'package:nasz_budzet_domowy/features/categories/presentation/widgets/delete_category_dialog.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/shared/widgets/async_error_state.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Ekran zarządzania kategoriami.
/// - 12 systemowych (lock icon, nieedytowalne).
/// - Własne: tap → edycja, swipe lub long-press → usuń (z reasignmentem
///   gdy mają transakcje).
/// - "+" w AppBar → bottom sheet do dodania nowej.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final counts = ref.watch(transactionCountByCategoryProvider);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('Kategorie'),
          centerTitle: false,
          floating: true,
          snap: true,
          actions: [
            IconButton(
              tooltip: 'Odśwież',
              icon: const AppIcon(Icons.refresh),
              onPressed: () {
                // Też transakcje — liczniki „ile transakcji" przy
                // kategoriach liczą się z `transactionsProvider`.
                ref
                  ..invalidate(categoriesProvider)
                  ..invalidate(transactionsProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Odświeżam dane…'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Dodaj kategorię',
              icon: const AppIcon(Icons.add),
              onPressed: () => _openCreateSheet(context),
            ),
          ],
        ),
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            ref
              ..invalidate(categoriesProvider)
              ..invalidate(transactionsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 500));
          },
        ),
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: AsyncErrorState(
              error: e,
              onRetry: () {
                ref
                  ..invalidate(categoriesProvider)
                  ..invalidate(transactionsProvider);
              },
            ),
          ),
          data: (categories) {
            // Mapa rodzic → posortowane podkategorie.
            final childrenByParent = <String, List<Category>>{};
            for (final c in categories.where((c) => c.parentId != null)) {
              childrenByParent.putIfAbsent(c.parentId!, () => []).add(c);
            }

            // Buduje wiersze danego typu: kategorie główne, a pod każdą
            // jej podkategorie (wcięte).
            List<Widget> rowsFor(TransactionType type) {
              final tops = categories
                  .where((c) => c.type == type && c.parentId == null)
                  .toList();
              final out = <Widget>[];
              for (final top in tops) {
                out.add(
                  _CategoryRow(
                    category: top,
                    count: counts[top.id] ?? 0,
                    isChild: false,
                  ),
                );
                for (final child
                    in childrenByParent[top.id] ?? const <Category>[]) {
                  out.add(
                    _CategoryRow(
                      category: child,
                      count: counts[child.id] ?? 0,
                      isChild: true,
                    ),
                  );
                }
              }
              return out;
            }

            final expenseRows = rowsFor(TransactionType.expense);
            final incomeRows = rowsFor(TransactionType.income);

            return SliverList(
              delegate: SliverChildListDelegate([
                if (expenseRows.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'Wydatki',
                      style:
                          tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  ...expenseRows,
                ],
                if (incomeRows.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'Dochody',
                      style:
                          tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  ...incomeRows,
                ],
                const SizedBox(height: 96),
              ]),
            );
          },
        ),
      ],
    );
  }
}

Future<bool?> _openCreateSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CategoryEditSheet(),
  );
}

Future<bool?> _openEditSheet(BuildContext context, Category category) {
  if (category.isSystem) return Future.value(false);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CategoryEditSheet(existing: category),
  );
}

Future<bool?> _openSubcategorySheet(BuildContext context, Category parent) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CategoryEditSheet(initialParentId: parent.id),
  );
}

Future<bool?> _openDeleteDialog(BuildContext context, Category category) {
  return showDialog<bool>(
    context: context,
    builder: (_) => DeleteCategoryDialog(category: category),
  );
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({
    required this.category,
    required this.count,
    required this.isChild,
  });

  final Category category;
  final int count;

  /// true = podkategoria (wcięta, bez przycisku dodawania pod-pod).
  final bool isChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Przycisk "dodaj podkategorię" — tylko dla kategorii głównych (system
    // i własnych). Podkategorie nie mają własnych pod-podkategorii.
    final addSubBtn = isChild
        ? null
        : IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Dodaj podkategorię',
            icon: const AppIcon(Icons.add, size: 20),
            onPressed: () => _openSubcategorySheet(context, category),
          );

    final endIcon = category.isSystem
        ? Tooltip(
            message: 'Kategoria systemowa (read-only)',
            child: Icon(
              Icons.lock_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : const AppIcon(Icons.chevron_right);

    final tile = ListTile(
      contentPadding: EdgeInsets.only(left: isChild ? 40 : 16, right: 8),
      leading: CategoryAvatar(category: category, size: isChild ? 30 : 36),
      title: Text(category.name),
      subtitle: count > 0
          ? Text('$count ${_pluralTx(count)}')
          : Text(
              'Brak transakcji',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (addSubBtn != null) addSubBtn,
          endIcon,
        ],
      ),
      onTap: category.isSystem ? null : () => _openEditSheet(context, category),
    );

    if (category.isSystem) {
      return tile;
    }

    return Dismissible(
      key: ValueKey('cat-${category.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final removed = await _openDeleteDialog(context, category);
        return removed ?? false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      child: tile,
    );
  }

  String _pluralTx(int n) {
    if (n == 1) return 'transakcja';
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'transakcje';
    }
    return 'transakcji';
  }
}
