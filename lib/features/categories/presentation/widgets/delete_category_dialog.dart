import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category_repository.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';

/// Dialog usuwania kategorii. Jeśli kategoria ma transakcje, użytkownik
/// MUSI wybrać kategorię docelową — wtedy atomowo (RPC) reasignujemy
/// transakcje + usuwamy kategorię. Jeśli nie ma transakcji, prosty confirm.
class DeleteCategoryDialog extends ConsumerStatefulWidget {
  const DeleteCategoryDialog({
    required this.category,
    super.key,
  });

  final Category category;

  @override
  ConsumerState<DeleteCategoryDialog> createState() =>
      _DeleteCategoryDialogState();
}

class _DeleteCategoryDialogState extends ConsumerState<DeleteCategoryDialog> {
  String? _targetId;
  String? _error;
  bool _submitting = false;

  Future<void> _submit({required bool needsReassign}) async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    final repo = ref.read(categoryRepositoryProvider);
    final CategoryWriteResult result;
    if (needsReassign) {
      result = await repo.deleteWithReassign(
        oldId: widget.category.id,
        targetId: _targetId!,
      );
    } else {
      result = await repo.delete(widget.category.id);
    }
    if (!mounted) return;
    switch (result) {
      case CategoryWriteSuccess():
        Navigator.of(context).pop(true);
      case CategoryDuplicateName():
        setState(() {
          _error = 'Nieoczekiwany błąd.';
          _submitting = false;
        });
      case CategoryWriteFailure(:final message):
        setState(() {
          _error = message;
          _submitting = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count =
        ref.watch(transactionCountByCategoryProvider)[widget.category.id] ?? 0;
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final candidates = all
        .where(
          (c) => c.id != widget.category.id && c.type == widget.category.type,
        )
        .toList()
      ..sort((a, b) {
        if (a.isSystem != b.isSystem) return a.isSystem ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    final needsReassign = count > 0;
    final cantContinue =
        needsReassign && (candidates.isEmpty || _targetId == null);

    return AlertDialog(
      title: Row(
        children: [
          CategoryAvatar(category: widget.category),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Usuń "${widget.category.name}"?',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!needsReassign)
            Text(
              'Kategoria nie ma żadnych transakcji — można ją usunąć od razu.',
              style: theme.textTheme.bodyMedium,
            )
          else if (candidates.isEmpty) ...[
            Text(
              'Ta kategoria ma $count ${_pluralTx(count)}, '
              'a nie ma innej kategorii '
              '${widget.category.type.isIncome ? "dochodów" : "wydatków"} '
              'do której można je przenieść. Stwórz najpierw inną.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ] else ...[
            Text(
              'Ta kategoria ma $count ${_pluralTx(count)}. '
              'Wybierz kategorię docelową — transakcje zostaną przeniesione, '
              'a następnie kategoria usunięta.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _targetId,
              decoration: const InputDecoration(
                labelText: 'Przenieś transakcje do…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final c in candidates)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(
                      children: [
                        CategoryAvatar(category: c, size: 24),
                        const SizedBox(width: 8),
                        Text(c.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _targetId = v),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Anuluj'),
        ),
        FilledButton.tonal(
          onPressed: (_submitting || cantContinue)
              ? null
              : () => _submit(needsReassign: needsReassign),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.errorContainer,
            foregroundColor: theme.colorScheme.onErrorContainer,
          ),
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Usuń'),
        ),
      ],
    );
  }

  String _pluralTx(int n) {
    if (n == 1) return 'transakcję';
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'transakcje';
    }
    return 'transakcji';
  }
}
