import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/core/offline/sync_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_notifications.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/presentation/add_transaction_screen.dart';
import 'package:nasz_budzet_domowy/shared/widgets/async_error_state.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';
import 'package:nasz_budzet_domowy/shared/widgets/comic_shadow.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Lista transakcji bieżącego gospodarstwa.
/// Renderuje się jako CustomScrollView (bez własnego Scaffold) —
/// żyje w HomeShell, który dostarcza NavigationBar i FAB.
///
/// Trzyma `_locallyDeleted` set — po swipe-delete optimistycznie ukrywamy
/// item zanim Realtime przyniesie DELETE event. Bez tego Dismissible
/// rzuca "A dismissed Dismissible widget is still part of the tree"
/// bo widget wraca po build (provider jeszcze nie wie o delete).
class TransactionsListScreen extends ConsumerStatefulWidget {
  const TransactionsListScreen({super.key});

  @override
  ConsumerState<TransactionsListScreen> createState() =>
      _TransactionsListScreenState();
}

class _TransactionsListScreenState
    extends ConsumerState<TransactionsListScreen> {
  /// ID transakcji ukrytych lokalnie po swipe (zanim Realtime przyniesie
  /// DELETE i provider się odświeży). Wyczyszczone gdy stream zaktualizuje
  /// listę bez tego ID — wtedy nie trzeba już ukrywać.
  final Set<String> _locallyDeleted = {};

  void _onDeleteLocally(String transactionId) {
    setState(() => _locallyDeleted.add(transactionId));
  }

  void _onDeleteFailed(String transactionId) {
    setState(() => _locallyDeleted.remove(transactionId));
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider);
    final categories = ref.watch(categoriesProvider);

    // Sprzątanie: gdy provider już wie o usunięciu, nie trzymamy ID w secie.
    final visibleIds =
        (transactions.value ?? const <Transaction>[]).map((t) => t.id).toSet();
    _locallyDeleted.removeWhere((id) => !visibleIds.contains(id));

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('Transakcje'),
          centerTitle: false,
          floating: true,
          snap: true,
          actions: [
            IconButton(
              tooltip: 'Import z banku',
              icon: const AppIcon(Icons.upload_file),
              onPressed: () => context.push('/transactions/import'),
            ),
          ],
        ),
        // Propozycje z powiadomień banku (beta) — baner nad listą,
        // znika gdy kolejka pusta.
        const SliverToBoxAdapter(child: _BankSuggestionsBanner()),
        // Pull-to-refresh — jak realtime padnie (np. zerwane wifi przy
        // wybudzeniu), user pociąga listę palcem od góry → fresh fetch.
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            ref
              ..invalidate(transactionsProvider)
              ..invalidate(categoriesProvider);
            await Future<void>.delayed(const Duration(milliseconds: 500));
          },
        ),
        transactions.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
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
          data: (txs) {
            // Filtruj lokalnie usunięte przed renderowaniem — Dismissible
            // wymaga że po onDismissed widget natychmiast zniknie z drzewa.
            final visibleTxs =
                txs.where((t) => !_locallyDeleted.contains(t.id)).toList();
            if (visibleTxs.isEmpty) {
              return const SliverFillRemaining(child: _EmptyState());
            }
            final categoriesMap = {
              for (final c in categories.value ?? const <Category>[]) c.id: c,
            };
            return _TransactionsList(
              transactions: visibleTxs,
              categoriesById: categoriesMap,
              onDeleteLocally: _onDeleteLocally,
              onDeleteFailed: _onDeleteFailed,
            );
          },
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Jeszcze nie ma transakcji',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Stuknij "Dodaj" żeby zapisać pierwszy wydatek lub dochód.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionsList extends StatelessWidget {
  const _TransactionsList({
    required this.transactions,
    required this.categoriesById,
    required this.onDeleteLocally,
    required this.onDeleteFailed,
  });

  final List<Transaction> transactions;
  final Map<String, Category> categoriesById;
  final void Function(String id) onDeleteLocally;
  final void Function(String id) onDeleteFailed;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate(transactions);
    return SliverPadding(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = groups[index];
            return _DateGroup(
              date: entry.key,
              transactions: entry.value,
              categoriesById: categoriesById,
              onDeleteLocally: onDeleteLocally,
              onDeleteFailed: onDeleteFailed,
            );
          },
          childCount: groups.length,
        ),
      ),
    );
  }

  static List<MapEntry<DateTime, List<Transaction>>> _groupByDate(
    List<Transaction> txs,
  ) {
    final map = <DateTime, List<Transaction>>{};
    for (final t in txs) {
      final key = DateTime(
        t.occurredAt.year,
        t.occurredAt.month,
        t.occurredAt.day,
      );
      map.putIfAbsent(key, () => []).add(t);
    }
    return map.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
  }
}

class _DateGroup extends StatelessWidget {
  const _DateGroup({
    required this.date,
    required this.transactions,
    required this.categoriesById,
    required this.onDeleteLocally,
    required this.onDeleteFailed,
  });

  final DateTime date;
  final List<Transaction> transactions;
  final Map<String, Category> categoriesById;
  final void Function(String id) onDeleteLocally;
  final void Function(String id) onDeleteFailed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _dateLabel(date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ComicShadow(
            child: Card(
              child: Column(
                children: [
                  for (final t in transactions)
                    _DismissibleTransactionRow(
                      transaction: t,
                      category: categoriesById[t.categoryId],
                      isLast: t == transactions.last,
                      onDeleteLocally: onDeleteLocally,
                      onDeleteFailed: onDeleteFailed,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Dziś';
    if (date == yesterday) return 'Wczoraj';
    return DateFormat('EEEE, d MMMM y', 'pl_PL').format(date);
  }
}

/// Wrapper z Dismissible — swipe w lewo → confirmation dialog → delete.
/// Działa zarówno na pending (z DAO) jak i zsynchronizowanych transakcjach
/// (przez TransactionRepository).
///
/// CRITICAL: po `onDismissed` widget MUSI natychmiast zniknąć z drzewa
/// (parent musi przefiltrować go z listy w tym samym build). Inaczej Flutter
/// rzuca "A dismissed Dismissible widget is still part of the tree".
/// Rozwiązujemy to przez `onDeleteLocally` — synchronicznie dodaje ID do
/// `_locallyDeleted` set w parent state'cie, build re-render bez tego item.
class _DismissibleTransactionRow extends ConsumerWidget {
  const _DismissibleTransactionRow({
    required this.transaction,
    required this.category,
    required this.isLast,
    required this.onDeleteLocally,
    required this.onDeleteFailed,
  });

  final Transaction transaction;
  final Category? category;
  final bool isLast;
  final void Function(String id) onDeleteLocally;
  final void Function(String id) onDeleteFailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('tx-${transaction.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirm(context),
      onDismissed: (_) async {
        // KROK 1 (SYNC, natychmiast): ukrywamy item w parent — Dismissible
        // może teraz bez problemu zniknąć z drzewa.
        onDeleteLocally(transaction.id);
        final messenger = ScaffoldMessenger.of(context);
        // KROK 2 (ASYNC): faktyczny delete w DB / kolejce. Po sukcesie
        // Realtime przyniesie DELETE event i provider odświeży listę
        // bez tego item — _locallyDeleted self-cleanup w build().
        try {
          if (transaction.isPending) {
            await ref.read(pendingOpsDaoProvider).remove(transaction.id);
          } else {
            await ref
                .read(transactionRepositoryProvider)
                .delete(transaction.id);
          }
          messenger.showSnackBar(
            const SnackBar(content: Text('Transakcja usunięta')),
          );
        } on Object catch (e) {
          // Rollback: usuń z _locallyDeleted żeby item wrócił.
          onDeleteFailed(transaction.id);
          messenger.showSnackBar(
            SnackBar(content: Text('Nie udało się usunąć: $e')),
          );
        }
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
      child: _TransactionRow(
        transaction: transaction,
        category: category,
        isLast: isLast,
      ),
    );
  }

  Future<bool> _confirm(BuildContext context) async {
    final amount = (transaction.amountCents / 100).toStringAsFixed(2);
    final sign = transaction.type == TransactionType.income ? '+' : '−';
    final hasDescription = transaction.description?.trim().isNotEmpty ?? false;
    final label = hasDescription
        ? transaction.description!.trim()
        : (category?.name ?? 'transakcja');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Usunąć transakcję?'),
          content: Text(
            '$sign$amount zł — $label\n\n'
            'Tej operacji nie da się cofnąć.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Anuluj'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Usuń'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
    required this.category,
    required this.isLast,
  });

  final Transaction transaction;
  final Category? category;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = transaction.type == TransactionType.income;
    final sign = isIncome ? '+' : '−';
    final amount =
        NumberFormat('#,##0.00', 'pl_PL').format(transaction.amountCents / 100);
    final accent = isIncome ? AppTheme.incomeAccent : AppTheme.expenseAccent;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (category != null)
                CategoryAvatar(category: category!)
              else
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (transaction.isPending) ...[
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            (transaction.description?.isNotEmpty ?? false)
                                ? transaction.description!
                                : (category?.name ?? 'Transakcja'),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (category != null)
                      Text(
                        transaction.isPending
                            ? '${category!.name} • czeka na sync'
                            : category!.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: transaction.isPending
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$sign$amount zł',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 66,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
      ],
    );
  }
}

/// Baner „Propozycje z banku" (beta) — pokazuje się, gdy nasłuch
/// powiadomień wyłuskał płatności czekające na zatwierdzenie.
class _BankSuggestionsBanner extends ConsumerWidget {
  const _BankSuggestionsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(bankSuggestionsProvider);
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ComicCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showBankSuggestionsSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                AppIcon(
                  Icons.notifications_active_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestions.length == 1
                        ? '1 propozycja z powiadomienia banku'
                        : '${suggestions.length} propozycje/-i z powiadomień '
                            'banku',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const AppIcon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showBankSuggestionsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final suggestions = ref.watch(bankSuggestionsProvider);
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Propozycje z banku (beta)',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (suggestions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Wszystko przejrzane 🎉'),
                ),
              for (final s in suggestions) _BankSuggestionTile(suggestion: s),
            ],
          ),
        );
      },
    ),
  );
}

class _BankSuggestionTile extends ConsumerWidget {
  const _BankSuggestionTile({required this.suggestion});

  final BankSuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isIncome = suggestion.type == TransactionType.income;
    final accent = isIncome ? AppTheme.incomeAccent : AppTheme.expenseAccent;
    final amount =
        NumberFormat('#,##0.00', 'pl_PL').format(suggestion.amountCents / 100);
    return ListTile(
      title: Text(
        suggestion.merchant,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${suggestion.bank} · '
        '${DateFormat('d.MM HH:mm').format(suggestion.capturedAt)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${isIncome ? '+' : '−'}$amount zł',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            tooltip: 'Odrzuć',
            icon: const AppIcon(Icons.close, size: 18),
            onPressed: () => ref
                .read(bankSuggestionsProvider.notifier)
                .remove(suggestion.id),
          ),
        ],
      ),
      onTap: () async {
        // Formularz z wypełnioną kwotą/opisem — user tylko wybiera
        // kategorię i zapisuje. Po udanym zapisie propozycja znika.
        final added = await context.push<bool>(
          '/transactions/add',
          extra: TransactionPrefill(
            amountCents: suggestion.amountCents,
            description: suggestion.merchant,
            occurredAt: suggestion.capturedAt,
            type: suggestion.type,
          ),
        );
        if (added ?? false) {
          await ref
              .read(bankSuggestionsProvider.notifier)
              .remove(suggestion.id);
        }
      },
    );
  }
}
