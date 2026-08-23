import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/animations/application/animation_settings.dart';
import 'package:nasz_budzet_domowy/features/animations/presentation/sparkle_burst.dart';
import 'package:nasz_budzet_domowy/features/budgets/application/budget_providers.dart';
import 'package:nasz_budzet_domowy/features/budgets/data/budget.dart';
import 'package:nasz_budzet_domowy/features/budgets/data/budget_repository.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';

/// Bottom sheet do tworzenia / edycji miesięcznego budżetu.
class BudgetEditSheet extends ConsumerStatefulWidget {
  const BudgetEditSheet({this.existing, super.key});

  /// `null` = nowy budżet (wybierasz kategorię). Inaczej edycja kwoty
  /// istniejącego (kategoria zablokowana).
  final Budget? existing;

  @override
  ConsumerState<BudgetEditSheet> createState() => _BudgetEditSheetState();
}

class _BudgetEditSheetState extends ConsumerState<BudgetEditSheet> {
  String? _categoryId;
  late final TextEditingController _amount;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.existing?.categoryId;
    _amount = TextEditingController(
      text: widget.existing == null
          ? ''
          : (widget.existing!.amountCents / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  Future<void> _submit() async {
    final raw = _amount.text.replaceAll(',', '.').trim();
    final value = double.tryParse(raw);
    if (value == null || value <= 0) {
      setState(() => _error = 'Wpisz prawidłową kwotę (np. 800,00).');
      return;
    }
    if (_categoryId == null) {
      setState(() => _error = 'Wybierz kategorię.');
      return;
    }
    final amountCents = (value * 100).round();

    setState(() {
      _error = null;
      _submitting = true;
    });

    final repo = ref.read(budgetRepositoryProvider);
    final BudgetWriteResult result;
    if (_isEdit) {
      result = await repo.updateAmount(
        id: widget.existing!.id,
        amountCents: amountCents,
      );
    } else {
      final householdId = ref.read(currentHouseholdIdProvider).value;
      if (householdId == null) {
        setState(() {
          _error = 'Brak gospodarstwa.';
          _submitting = false;
        });
        return;
      }
      final now = DateTime.now();
      result = await repo.insert(
        householdId: householdId,
        categoryId: _categoryId!,
        amountCents: amountCents,
        startsOn: DateTime(now.year, now.month),
      );
    }

    if (!mounted) return;
    switch (result) {
      case BudgetWriteSuccess():
        if (!_isEdit &&
            ref
                .read(animationSettingsProvider)
                .isOn(AppAnimation.budgetSparkleOnCreate)) {
          SparkleBurst.show(context);
        }
        Navigator.of(context).pop(true);
      case BudgetDuplicate():
        setState(() {
          _error = 'Budżet dla tej kategorii już istnieje w tym miesiącu.';
          _submitting = false;
        });
      case BudgetWriteFailure(:final message):
        setState(() {
          _error = 'Nie udało się zapisać: $message';
          _submitting = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final existingBudgets =
        ref.watch(budgetsProvider).value ?? const <Budget>[];
    final usedCategoryIds = existingBudgets.map((b) => b.categoryId).toSet();

    // Tylko kategorie wydatków, nieużywane w innych budżetach (chyba że to
    // edycja — wtedy obecna kategoria zostaje).
    final candidates = categories
        .where(
          (c) =>
              c.type == TransactionType.expense &&
              (c.id == _categoryId || !usedCategoryIds.contains(c.id)),
        )
        .toList()
      ..sort((a, b) {
        if (a.isSystem != b.isSystem) return a.isSystem ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isEdit ? 'Edytuj budżet' : 'Nowy budżet miesięczny',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Kategoria wydatków',
                border: OutlineInputBorder(),
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
              onChanged:
                  _isEdit ? null : (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Kwota miesięczna',
                suffixText: 'zł',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Zapisz' : 'Dodaj budżet'),
            ),
            if (_isEdit)
              TextButton(
                onPressed: _submitting
                    ? null
                    : () async {
                        final repo = ref.read(budgetRepositoryProvider);
                        final navigator = Navigator.of(context);
                        final result = await repo.delete(widget.existing!.id);
                        if (!mounted) return;
                        if (result is BudgetWriteSuccess) {
                          navigator.pop(true);
                        }
                      },
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text('Usuń budżet'),
              ),
            TextButton(
              onPressed:
                  _submitting ? null : () => Navigator.of(context).pop(false),
              child: const Text('Anuluj'),
            ),
          ],
        ),
      ),
    );
  }
}
