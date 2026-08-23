import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category_repository.dart';
import 'package:nasz_budzet_domowy/features/categories/presentation/widgets/color_picker.dart';
import 'package:nasz_budzet_domowy/features/categories/presentation/widgets/icon_picker.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Bottom sheet do tworzenia / edycji kategorii. Edycja systemowej
/// (`isSystem=true`) jest blokowana w UI — wywołanie z taką kategorią
/// rzuca [ArgumentError].
class CategoryEditSheet extends ConsumerStatefulWidget {
  CategoryEditSheet({this.existing, this.initialParentId, super.key})
      : assert(
          existing?.isSystem != true,
          'Systemowe kategorie są read-only',
        );

  /// `null` = tworzenie nowej. Inaczej edycja istniejącej.
  final Category? existing;

  /// Gdy ustawione (i `existing == null`) → tworzymy podkategorię tego
  /// rodzica; dziedziczymy jego typ/kolor/ikonę jako domyślne.
  final String? initialParentId;

  @override
  ConsumerState<CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<CategoryEditSheet> {
  late final TextEditingController _name;
  late String _icon;
  late String _colorHex;
  late TransactionType _type;
  String? _parentId;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final cats = ref.read(categoriesProvider).value ?? const <Category>[];
    _parentId = e?.parentId ?? widget.initialParentId;
    final parent = cats.where((c) => c.id == _parentId).firstOrNull;
    _name = TextEditingController(text: e?.name ?? '');
    _icon = e?.icon ?? parent?.icon ?? 'shopping_cart';
    _colorHex = e?.colorHex ?? parent?.colorHex ?? '#7AB87A';
    _type = e?.type ?? parent?.type ?? TransactionType.expense;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  /// Czy edytowana kategoria sama ma podkategorie (wtedy nie może stać się
  /// podkategorią — jeden poziom zagnieżdżenia).
  bool get _hasChildren {
    if (!_isEdit) return false;
    final cats = ref.read(categoriesProvider).value ?? const <Category>[];
    return cats.any((c) => c.parentId == widget.existing!.id);
  }

  String? get _effectiveParentId => _hasChildren ? null : _parentId;

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nazwa nie może być pusta.');
      return;
    }
    if (name.length > 30) {
      setState(() => _error = 'Maksymalnie 30 znaków.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    final repo = ref.read(categoryRepositoryProvider);
    final CategoryWriteResult result;
    if (_isEdit) {
      result = await repo.update(
        id: widget.existing!.id,
        name: name,
        icon: _icon,
        colorHex: _colorHex,
        type: _type,
        parentId: _effectiveParentId,
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
      result = await repo.insert(
        householdId: householdId,
        name: name,
        icon: _icon,
        colorHex: _colorHex,
        type: _type,
        parentId: _effectiveParentId,
      );
    }

    if (!mounted) return;
    switch (result) {
      case CategoryWriteSuccess():
        Navigator.of(context).pop(true);
      case CategoryDuplicateName():
        setState(() {
          _error = 'Kategoria o tej nazwie już istnieje.';
          _submitting = false;
        });
      case CategoryWriteFailure(:final message):
        setState(() {
          _error = 'Nie udało się zapisać: $message';
          _submitting = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allCats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final hasChildren = _hasChildren;
    final parentCandidates = allCats
        .where(
          (c) =>
              c.type == _type &&
              c.parentId == null &&
              c.id != widget.existing?.id,
        )
        .toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    final parentValue =
        parentCandidates.any((c) => c.id == _parentId) ? _parentId : null;
    final previewCategory = Category(
      id: 'preview',
      householdId: 'preview',
      name: _name.text.isEmpty ? 'Podgląd' : _name.text,
      icon: _icon,
      colorHex: _colorHex,
      type: _type,
      isSystem: false,
    );

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
              alignment: Alignment.center,
            ),
            const SizedBox(height: 16),
            Text(
              _isEdit ? 'Edytuj kategorię' : 'Nowa kategoria',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CategoryAvatar(category: previewCategory, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Nazwa',
                      hintText: 'np. Subskrypcje',
                    ),
                    maxLength: 30,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Wydatek'),
                  icon: AppIcon(Icons.south),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Dochód'),
                  icon: AppIcon(Icons.north),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                // Rodzic musi być tego samego typu — wyczyść jeśli już nie
                // pasuje.
                final p = allCats.where((c) => c.id == _parentId).firstOrNull;
                if (p != null && p.type != _type) _parentId = null;
              }),
            ),
            const SizedBox(height: 16),
            if (hasChildren)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Ta kategoria ma podkategorie, więc pozostaje kategorią '
                  'główną.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              DropdownButtonFormField<String?>(
                key: ValueKey('parent-$_type'),
                initialValue: parentValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Kategoria nadrzędna (opcjonalnie)',
                  prefixIcon: AppIcon(Icons.account_tree_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    child: Text('— Brak (kategoria główna)'),
                  ),
                  for (final c in parentCandidates)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Row(
                        children: [
                          CategoryAvatar(category: c, size: 24),
                          const SizedBox(width: 8),
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
                onChanged: (id) => setState(() => _parentId = id),
              ),
            const SizedBox(height: 20),
            Text('Kolor', style: theme.textTheme.labelLarge),
            const SizedBox(height: 12),
            ColorPicker(
              selectedHex: _colorHex,
              onSelected: (hex) => setState(() => _colorHex = hex),
            ),
            const SizedBox(height: 20),
            Text('Ikona', style: theme.textTheme.labelLarge),
            const SizedBox(height: 12),
            IconPicker(
              selected: _icon,
              onSelected: (name) => setState(() => _icon = name),
            ),
            const SizedBox(height: 12),
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
                  : Text(_isEdit ? 'Zapisz zmiany' : 'Dodaj kategorię'),
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
