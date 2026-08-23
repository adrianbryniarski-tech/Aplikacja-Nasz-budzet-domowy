import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/statement_categorizer.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/bank_statement_parser.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/import_repository.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/statement_file_reader.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';
import 'package:nasz_budzet_domowy/shared/widgets/comic_shadow.dart';
import 'package:nasz_budzet_domowy/shared/widgets/inline_error.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Import wyciągów bankowych: CSV (PKO BP, ING, Revolut), PDF (ING)
/// i ZIP-y z takimi plikami — można wybrać kilka naraz.
///
/// Przepływ: wybór plików → parsowanie → podgląd z auto-kategoriami
/// (wbudowane sieci + reguły nauczone od domowników) → zapis paczką
/// z deduplikacją. Poprawki kategorii zapamiętujemy jako reguły —
/// kolejny import przypisze je sam.
class ImportStatementScreen extends ConsumerStatefulWidget {
  const ImportStatementScreen({super.key});

  @override
  ConsumerState<ImportStatementScreen> createState() =>
      _ImportStatementScreenState();
}

/// Jeden wiersz podglądu.
class _ImportRow {
  _ImportRow({
    required this.entry,
    required this.categoryId,
    required this.autoMatched,
    this.suspectedDuplicate = false,
  }) {
    selected = !suspectedDuplicate;
  }

  final StatementEntry entry;
  String categoryId;

  /// true = kategorię trafił automat (reguła/wbudowana), false = fallback
  /// „Inne" do przejrzenia.
  final bool autoMatched;

  /// W bazie jest już transakcja z tym samym DNIEM, kwotą i typem —
  /// pewnie dodana ręcznie (inny opis, więc twardy dedup jej nie złapie).
  /// Domyślnie odznaczamy; user może zaznaczyć z powrotem.
  final bool suspectedDuplicate;

  late bool selected;

  /// User ręcznie zmienił kategorię → po zapisie uczymy się reguły.
  bool touchedByUser = false;
}

class _ImportStatementScreenState extends ConsumerState<ImportStatementScreen> {
  MergedStatements? _parsed;
  List<_ImportRow> _rows = const [];
  bool _busy = false;
  String? _error;

  Future<void> _pickAndParse() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'pdf', 'zip'],
      );
      if (picked.isEmpty) {
        setState(() => _busy = false); // anulowano wybór
        return;
      }
      final files = <StatementFile>[
        for (final p in picked)
          StatementFile(name: p.name, bytes: await p.readAsBytes()),
      ];
      final parsed = StatementFileReader.readPicked(files);
      if (parsed.entries.isEmpty) {
        throw StatementParseException(
          parsed.fileErrors.isNotEmpty
              ? parsed.fileErrors.join('\n')
              : 'W plikach nie ma żadnych transakcji do zaimportowania.',
        );
      }

      final householdId = ref.read(currentHouseholdIdProvider).value;
      if (householdId == null) {
        throw const StatementParseException(
          'Brak gospodarstwa — zaloguj się ponownie.',
        );
      }
      final categories =
          ref.read(categoriesProvider).value ?? const <Category>[];
      final importRepo = ref.read(importRepositoryProvider);
      final rules = await importRepo.merchantRules(householdId);
      final categorizer = StatementCategorizer(
        categories: categories,
        learnedRules: rules,
      );

      // Miękkie odciski istniejących wpisów w zakresie dat wyciągu —
      // wiersze „chyba już dodane ręcznie" odznaczymy domyślnie.
      var from = parsed.entries.first.occurredAt;
      var to = from;
      for (final e in parsed.entries) {
        if (e.occurredAt.isBefore(from)) from = e.occurredAt;
        if (e.occurredAt.isAfter(to)) to = e.occurredAt;
      }
      final softKeys = await importRepo.existingSoftKeys(
        householdId: householdId,
        from: from,
        to: to,
      );

      final rows = <_ImportRow>[];
      for (final entry in parsed.entries) {
        final suggested =
            categorizer.categoryIdFor(entry.description, entry.type);
        final fallback = _fallbackCategory(categories, entry.type);
        final categoryId = suggested ?? fallback;
        if (categoryId == null) continue; // brak jakiejkolwiek kategorii
        rows.add(
          _ImportRow(
            entry: entry,
            categoryId: categoryId,
            autoMatched: suggested != null,
            suspectedDuplicate: softKeys.contains(
              ImportRepository.softKey(
                entry.occurredAt,
                entry.amountCents,
                entry.type,
              ),
            ),
          ),
        );
      }
      setState(() {
        _parsed = parsed;
        _rows = rows;
        _busy = false;
      });
    } on StatementParseException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on Object catch (e) {
      setState(() {
        _busy = false;
        _error = humanizeError(e);
      });
    }
  }

  /// „Inne" (wydatki) / „Inne dochody"; gdy ich nie ma — pierwsza
  /// kategoria główna właściwego typu.
  String? _fallbackCategory(List<Category> categories, TransactionType type) {
    final ofType = categories.where((c) => c.type == type).toList();
    if (ofType.isEmpty) return null;
    final preferred = type == TransactionType.expense ? 'inne' : 'inne dochody';
    for (final c in ofType) {
      if (TransactionHasher.normalize(c.name) == preferred) return c.id;
    }
    return ofType.first.id;
  }

  Future<void> _save() async {
    final householdId = ref.read(currentHouseholdIdProvider).value;
    if (householdId == null) return;
    final selected = _rows.where((r) => r.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _busy = true);
    final repo = ref.read(importRepositoryProvider);
    final result = await repo.saveEntries(
      householdId: householdId,
      rows: [
        for (final r in selected) (entry: r.entry, categoryId: r.categoryId),
      ],
    );
    if (!mounted) return;

    switch (result) {
      case ImportSaveSuccess(:final inserted, :final duplicates):
        // Ucz się reguł z ręcznych poprawek — usprawnia następny import.
        for (final r in selected.where((r) => r.touchedByUser)) {
          await repo.upsertMerchantRule(
            householdId: householdId,
            pattern: StatementCategorizer.patternFor(r.entry.description),
            categoryId: r.categoryId,
          );
        }
        ref.invalidate(transactionsProvider);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              duplicates == 0
                  ? 'Dodano $inserted transakcji.'
                  : 'Dodano $inserted transakcji, pominięto $duplicates '
                      'duplikatów (już były w budżecie).',
            ),
          ),
        );
        context.pop();
      case ImportSaveFailure(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  Future<void> _pickCategory(_ImportRow row) async {
    final all = ref.read(categoriesProvider).value ?? const <Category>[];
    final categories = all.where((c) => c.type == row.entry.type).toList();
    final picked = await showModalBottomSheet<Category>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in categories)
              ListTile(
                leading: CategoryAvatar(category: c),
                title: Text(c.name),
                onTap: () => Navigator.of(context).pop(c),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      row
        ..categoryId = picked.id
        ..touchedByUser = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = _parsed;
    return Scaffold(
      appBar: AppBar(title: const Text('Import z banku')),
      body: SafeArea(
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : parsed == null
                ? _buildIntro(theme)
                : _buildPreview(theme, parsed),
      ),
    );
  }

  Widget _buildIntro(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: 16),
        ],
        ComicCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Jak to działa', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '1. Pobierz z banku wyciąg CSV (PKO BP, ING, Revolut) '
                  'albo PDF (ING). Może być też ZIP z wieloma plikami.\n'
                  '2. Wybierz pliki poniżej — możesz kilka naraz. Apka '
                  'sama rozpozna bank, rozdzieli transakcje i zaproponuje '
                  'kategorie.\n'
                  '3. Przejrzyj, popraw co trzeba i zapisz. Nic się nie '
                  'zdubluje, a poprawki kategorii apka zapamięta na '
                  'kolejne importy.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _pickAndParse,
          icon: const AppIcon(Icons.upload_file),
          label: const Text('Wybierz pliki (CSV / PDF / ZIP)'),
        ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme, MergedStatements parsed) {
    final selectedCount = _rows.where((r) => r.selected).length;
    final toReview = _rows.where((r) => !r.autoMatched).length;
    final suspected = _rows.where((r) => r.suspectedDuplicate).length;
    final suspectedInfo = '$suspected chyba już jest w budżecie '
        '(odznaczone — zaznacz, jeśli to co innego)';
    final skipped = parsed.skippedNonPln + parsed.skippedOther;
    final repeats = parsed.crossFileDuplicates + parsed.duplicateFiles;
    final internalInfo = '${parsed.skippedInternal} przelewów między '
        'własnymi kontami pominięto';
    final categoriesById = {
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
        c.id: c,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ComicCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parsed.parsedFiles > 1
                        ? 'Wykryto: ${parsed.banksLabel} — ${_rows.length} '
                            'transakcji z ${parsed.parsedFiles} plików'
                        : 'Wykryto: ${parsed.banksLabel} — ${_rows.length} '
                            'transakcji',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (suspected > 0) suspectedInfo,
                      if (toReview > 0)
                        '$toReview do przejrzenia (oznaczone kolorem)',
                      if (parsed.skippedInternal > 0) internalInfo,
                      if (repeats > 0)
                        '$repeats powtórek z innych plików pominięto',
                      if (skipped > 0) 'pominięto $skipped (waluta/w toku)',
                      'duplikaty odfiltrują się przy zapisie',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (parsed.fileErrors.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    InlineError(message: parsed.fileErrors.join('\n')),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    InlineError(message: _error!),
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: _rows.length,
            itemBuilder: (context, i) {
              final row = _rows[i];
              final category = categoriesById[row.categoryId];
              return _ImportRowTile(
                row: row,
                category: category,
                onToggle: (v) =>
                    setState(() => row.selected = v ?? !row.selected),
                onPickCategory: () => _pickCategory(row),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _parsed = null;
                      _rows = const [];
                      _error = null;
                    }),
                    child: const Text('Inne pliki'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: selectedCount == 0 ? null : _save,
                    icon: const AppIcon(Icons.save_alt),
                    label: Text('Zapisz $selectedCount'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportRowTile extends StatelessWidget {
  const _ImportRowTile({
    required this.row,
    required this.category,
    required this.onToggle,
    required this.onPickCategory,
  });

  final _ImportRow row;
  final Category? category;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onPickCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = row.entry;
    final isIncome = e.type == TransactionType.income;
    final accent = isIncome ? AppTheme.incomeAccent : AppTheme.expenseAccent;
    final amount =
        NumberFormat('#,##0.00', 'pl_PL').format(e.amountCents / 100);
    final needsReview = !row.autoMatched && !row.touchedByUser;

    return CheckboxListTile(
      value: row.selected,
      onChanged: onToggle,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Row(
        children: [
          Expanded(
            child: Text(
              e.description.isEmpty ? '(bez opisu)' : e.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIncome ? '+' : '−'}$amount zł',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Text(
              DateFormat('d.MM').format(e.occurredAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (row.suspectedDuplicate) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'W budżecie jest już wpis z tym dniem, kwotą '
                    'i typem — pewnie dodany ręcznie.',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'chyba już jest',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Flexible(
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: needsReview
                    ? Icon(
                        Icons.help_outline,
                        size: 16,
                        color: theme.colorScheme.tertiary,
                      )
                    : null,
                side: needsReview
                    ? BorderSide(color: theme.colorScheme.tertiary)
                    : null,
                label: Text(
                  category?.name ?? '—',
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: onPickCategory,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
