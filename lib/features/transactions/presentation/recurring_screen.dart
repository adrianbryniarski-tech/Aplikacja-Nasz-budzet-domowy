import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/recurring_transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/shared/widgets/async_error_state.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Zarządzanie transakcjami cyklicznymi (czynsz, abonamenty, wypłata).
///
/// Szablon nalicza się automatycznie w dniu `dayOfMonth` — wpis pojawia
/// się na liście transakcji z opisem = nazwą szablonu. Naliczanie robi
/// apka przy starcie (patrz `recurringMaterializerProvider`).
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(recurringListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Transakcje cykliczne')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context, ref),
        icon: const AppIcon(Icons.add),
        label: const Text('Dodaj'),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorState(
          error: e,
          onRetry: () => ref.invalidate(recurringListProvider),
        ),
        data: (items) {
          if (items.isEmpty) return const _EmptyRecurring();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: items.length,
            itemBuilder: (context, i) => _RecurringTile(recurring: items[i]),
          );
        },
      ),
    );
  }
}

class _EmptyRecurring extends StatelessWidget {
  const _EmptyRecurring();

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
              Icons.event_repeat,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text('Brak cyklicznych', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Dodaj np. czynsz, Netflix albo wypłatę — apka sama dopisze '
              'wpis do budżetu w wybranym dniu każdego miesiąca.',
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

class _RecurringTile extends ConsumerWidget {
  const _RecurringTile({required this.recurring});

  final RecurringTransaction recurring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    Category? category;
    for (final c in categories) {
      if (c.id == recurring.categoryId) category = c;
    }
    final isIncome = recurring.type == TransactionType.income;
    final accent = isIncome ? AppTheme.incomeAccent : AppTheme.expenseAccent;
    final amount =
        NumberFormat('#,##0.00', 'pl_PL').format(recurring.amountCents / 100);
    final nextDue = DateFormat('d MMMM', 'pl_PL').format(recurring.nextDue);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: category != null
            ? CategoryAvatar(category: category)
            : const AppIcon(Icons.event_repeat),
        title: Text(recurring.name),
        subtitle: Text(
          recurring.active
              ? '${recurring.dayOfMonth}. dzień miesiąca · następne: $nextDue'
              : 'Wstrzymane',
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
                color: recurring.active
                    ? accent
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                final repo = ref.read(recurringRepositoryProvider);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  if (v == 'toggle') {
                    await repo.setActive(
                      recurring.id,
                      active: !recurring.active,
                    );
                  } else if (v == 'delete') {
                    await repo.delete(recurring.id);
                  }
                  ref.invalidate(recurringListProvider);
                } on Object catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(humanizeError(e))),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(recurring.active ? 'Wstrzymaj' : 'Wznów'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Usuń')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAddSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _AddRecurringSheet(),
  );
}

class _AddRecurringSheet extends ConsumerStatefulWidget {
  const _AddRecurringSheet();

  @override
  ConsumerState<_AddRecurringSheet> createState() => _AddRecurringSheetState();
}

class _AddRecurringSheetState extends ConsumerState<_AddRecurringSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  Category? _category;
  int _dayOfMonth = 1;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  int? _parseAmount(String raw) {
    final cleaned = raw.replaceAll(' ', '').replaceAll(',', '.');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed <= 0) return null;
    return (parsed * 100).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final category = _category;
    if (category == null) {
      setState(() => _errorMessage = 'Wybierz kategorię.');
      return;
    }
    final householdId = ref.read(currentHouseholdIdProvider).value;
    if (householdId == null) return;
    final amountCents = _parseAmount(_amountController.text);
    if (amountCents == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await ref.read(recurringRepositoryProvider).create(
            householdId: householdId,
            name: _nameController.text.trim(),
            amountCents: amountCents,
            type: _type,
            categoryId: category.id,
            dayOfMonth: _dayOfMonth,
          );
      ref
        ..invalidate(recurringListProvider)
        // Szablon z dzisiejszym dniem ma się naliczyć od razu.
        ..invalidate(recurringMaterializerProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = humanizeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final filtered = [
      for (final c in categories)
        if (c.type == _type) c,
    ];
    final selected = filtered.where((c) => c.id == _category?.id).firstOrNull;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nowa transakcja cykliczna',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Wydatek'),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Dochód'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  if (_category != null && _category!.type != _type) {
                    _category = null;
                  }
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Nazwa (np. Czynsz, Netflix, Wypłata)',
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Wpisz nazwę.' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Kwota (PLN)',
                  hintText: '0,00',
                ),
                validator: (v) =>
                    _parseAmount(v ?? '') == null ? 'Kwota niepoprawna.' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Category>(
                key: ValueKey(_type),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategoria'),
                items: [
                  for (final c in filtered)
                    DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          CategoryAvatar(category: c, size: 24),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (c) => setState(() => _category = c),
                validator: (v) => v == null ? 'Wybierz kategorię.' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _dayOfMonth,
                decoration: const InputDecoration(
                  labelText: 'Dzień miesiąca (naliczenie)',
                ),
                items: [
                  for (var d = 1; d <= 31; d++)
                    DropdownMenuItem(value: d, child: Text('$d.')),
                ],
                onChanged: (d) => setState(() => _dayOfMonth = d ?? 1),
              ),
              const SizedBox(height: 6),
              Text(
                'W krótszych miesiącach dzień 29–31 naliczy się ostatniego '
                'dnia miesiąca.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const AppIcon(Icons.check_circle_outline),
                label: const Text('Zapisz'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
