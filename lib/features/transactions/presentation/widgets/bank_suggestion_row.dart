import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/core/haptics.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_notifications.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_suggestion_actions.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/presentation/add_transaction_screen.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Jeden wiersz propozycji z powiadomienia banku — wspólny dla pulpitu
/// i listy Transakcji.
///
/// Przepływ jednym tapnięciem:
/// - apka zgadła kategorię (nauczona reguła albo wbudowana sieć, np.
///   Biedronka → Spożywcze) → chip pokazuje kategorię, ✓ zapisuje;
/// - apka NIE wie → chip świeci „Wybierz kategorię" i ✓ jest nieaktywne;
///   tapnięcie chipa otwiera listę kategorii, a wybór od razu zapisuje
///   wpis I zapamiętuje regułę na przyszłość;
/// - tapnięcie całego wiersza otwiera pełny formularz (gdy trzeba zmienić
///   kwotę, datę albo dopisać notatkę);
/// - ✕ odrzuca propozycję.
class BankSuggestionRow extends ConsumerWidget {
  const BankSuggestionRow({required this.suggestion, super.key});

  final BankSuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final guessed = guessCategoryFor(
      suggestion,
      categorizer: ref.watch(suggestionCategorizerProvider),
      categories: categories,
    );
    final isIncome = suggestion.type == TransactionType.income;
    final accent = isIncome ? AppTheme.incomeAccent : AppTheme.expenseAccent;
    final amount =
        NumberFormat('#,##0.00', 'pl_PL').format(suggestion.amountCents / 100);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      // Pełny formularz — gdy user chce zmienić kwotę/datę/notatkę.
      onTap: () => _openForm(context, ref, guessed),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            if (guessed != null)
              CategoryAvatar(category: guessed, size: 34)
            else
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.help_outline,
                  size: 18,
                  color: cs.tertiary,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.merchant,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${suggestion.bank} · '
                        '${DateFormat('d.MM HH:mm').format(
                          suggestion.capturedAt,
                        )}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: _CategoryChip(
                          category: guessed,
                          onPressed: () => _pickCategoryAndSave(
                            context,
                            ref,
                            categories,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isIncome ? '+' : '−'}$amount zł',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: guessed != null
                          ? 'Zapisz w „${guessed.name}"'
                          : 'Najpierw wybierz kategorię',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      color: guessed != null ? AppTheme.incomeAccent : null,
                      icon: const AppIcon(Icons.check_circle_outline, size: 20),
                      onPressed: guessed == null
                          ? null
                          : () => _save(
                                context,
                                ref,
                                categoryId: guessed.id,
                                learn: false,
                              ),
                    ),
                    IconButton(
                      tooltip: 'Odrzuć',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: const AppIcon(Icons.close, size: 18),
                      onPressed: () {
                        ref.read(hapticsProvider).tap();
                        ref
                            .read(bankSuggestionsProvider.notifier)
                            .remove(suggestion.id);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    Category? guessed,
  ) async {
    final added = await context.push<bool>(
      '/transactions/add',
      extra: TransactionPrefill(
        amountCents: suggestion.amountCents,
        description: suggestion.merchant,
        occurredAt: suggestion.capturedAt,
        type: suggestion.type,
        categoryId: guessed?.id,
      ),
    );
    if (added ?? false) {
      await ref.read(bankSuggestionsProvider.notifier).remove(suggestion.id);
    }
  }

  /// Apka nie wie (albo user chce poprawić) → arkusz z kategoriami
  /// właściwego typu; wybór ZAPISUJE wpis i uczy regułę.
  Future<void> _pickCategoryAndSave(
    BuildContext context,
    WidgetRef ref,
    List<Category> categories,
  ) async {
    final ofType = categories.where((c) => c.type == suggestion.type).toList();
    final picked = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Do jakiej kategorii: ${suggestion.merchant}?',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Apka zapamięta Twój wybór — następny raz przypisze sama.',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            for (final c in ofType)
              ListTile(
                leading: CategoryAvatar(category: c),
                title: Text(c.name),
                onTap: () => Navigator.of(sheetContext).pop(c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await _save(context, ref, categoryId: picked.id, learn: true);
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref, {
    required String categoryId,
    required bool learn,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(hapticsProvider).success();
    final result = await saveBankSuggestion(
      ref,
      suggestion: suggestion,
      categoryId: categoryId,
      learn: learn,
    );
    final message = switch (result) {
      SuggestionSaved(:final queued) => queued
          ? 'Zapisane lokalnie — wyśle się, gdy wróci internet.'
          : 'Dodano: ${suggestion.merchant}'
              '${learn ? ' (kategoria zapamiętana)' : ''}',
      SuggestionAlreadyBooked() => 'Ten wydatek już był w budżecie.',
      SuggestionSaveFailed(:final message) => message,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Chip z kategorią: nazwa gdy apka zgadła, wyróżnione „Wybierz
/// kategorię" gdy nie wie.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.onPressed});

  final Category? category;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unknown = category == null;
    return ActionChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      avatar: unknown
          ? Icon(
              Icons.touch_app_outlined,
              size: 14,
              color: theme.colorScheme.tertiary,
            )
          : null,
      side: unknown
          ? BorderSide(color: theme.colorScheme.tertiary)
          : BorderSide(color: theme.colorScheme.outlineVariant),
      label: Text(
        unknown ? 'Wybierz kategorię' : category!.name,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: unknown ? theme.colorScheme.tertiary : null,
          fontWeight: unknown ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onPressed: onPressed,
    );
  }
}
