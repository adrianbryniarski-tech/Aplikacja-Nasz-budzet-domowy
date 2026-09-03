import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/core/haptics.dart';
import 'package:nasz_budzet_domowy/features/animations/presentation/animation_player.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/voice_parser.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction_repository.dart';
import 'package:nasz_budzet_domowy/features/transactions/presentation/widgets/voice_input_button.dart';
import 'package:nasz_budzet_domowy/shared/widgets/category_avatar.dart';
import 'package:nasz_budzet_domowy/shared/widgets/inline_error.dart';
import 'package:nasz_budzet_domowy/shared/widgets/loading_filled_button.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Wstępne wypełnienie formularza (np. z propozycji z powiadomienia
/// banku albo przyszłych integracji). Wszystkie pola opcjonalne.
class TransactionPrefill {
  const TransactionPrefill({
    this.amountCents,
    this.description,
    this.occurredAt,
    this.type,
    this.categoryId,
  });

  final int? amountCents;
  final String? description;
  final DateTime? occurredAt;
  final TransactionType? type;

  /// Kategoria zgadnięta z góry (np. „Biedronka → Spożywcze" przy
  /// propozycji z powiadomienia banku) — formularz otwiera się z nią
  /// wybraną, user może zmienić.
  final String? categoryId;
}

/// Form dodawania LUB edycji transakcji.
///
/// Pola: typ (segmented control), kwota, kategoria (filtrowana po typie),
/// data (datepicker), opis (opcjonalny), notatka (opcjonalna).
/// Nad listą kategorii chipy z najczęściej używanymi — jeden tap zamiast
/// szukania w dropdownie.
///
/// Tryb edycji: podaj [existing] — formularz startuje z wartościami
/// transakcji i zapis robi UPDATE zamiast INSERT.
///
/// Walidacje są inline na poszczególnych polach; submit blokowany dopóki
/// wszystkie poprawne. Po sukcesie wraca do ekranu listy.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({this.prefill, this.existing, super.key});

  final TransactionPrefill? prefill;

  /// Transakcja do edycji (null = tryb dodawania).
  final Transaction? existing;

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _noteController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  Category? _category;
  DateTime _occurredAt = DateTime.now();
  bool _isSaving = false;
  String? _errorMessage;

  /// Czy aktualny formularz został zainicjowany głosem. Resetowane na false
  /// gdy user ręcznie edytuje kwotę — od tego momentu transakcja idzie
  /// jako `manual`, bo voice tylko zasugerował.
  bool _fromVoice = false;

  /// Wypełnia formularz wynikiem parsowania głosu.
  void _applyVoiceResult(VoiceParseResult result) {
    setState(() {
      if (result.amountCents != null) {
        _amountController.text = (result.amountCents! / 100).toStringAsFixed(2);
      }
      if (result.occurredAt != null) {
        _occurredAt = result.occurredAt!;
      }
      if (result.description != null) {
        _descriptionController.text = result.description!;
      }
      _type = result.type;
      _fromVoice = true;
    });
  }

  /// W trybie edycji: id kategorii z transakcji — obiekt [Category]
  /// dobieramy dopiero gdy provider kategorii się załaduje.
  String? _initialCategoryId;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _amountController.text = (existing.amountCents / 100).toStringAsFixed(2);
      _descriptionController.text = existing.description ?? '';
      _noteController.text = existing.note ?? '';
      _occurredAt = existing.occurredAt;
      _type = existing.type;
      _initialCategoryId = existing.categoryId;
      return;
    }
    final prefill = widget.prefill;
    if (prefill != null) {
      if (prefill.amountCents != null) {
        _amountController.text =
            (prefill.amountCents! / 100).toStringAsFixed(2);
      }
      if (prefill.description != null) {
        _descriptionController.text = prefill.description!;
      }
      if (prefill.occurredAt != null) _occurredAt = prefill.occurredAt!;
      if (prefill.type != null) _type = prefill.type!;
      _initialCategoryId = prefill.categoryId;
    }
  }

  /// Aktualnie wybrana kategoria: jawny wybór usera albo (w edycji)
  /// kategoria transakcji rozwiązana z załadowanej listy.
  Category? _resolveCategory(List<Category> all) {
    if (_category != null) return _category;
    final id = _initialCategoryId;
    if (id == null) return null;
    for (final c in all) {
      if (c.id == id && c.type == _type) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Wybiera animację zgodnie z typem transakcji i kategorią + per-user
  /// togglami w ustawieniach. Wywołane PRZED `context.pop()` — apka jeszcze
  /// jest na ekranie, więc Overlay rysuje się nad listą po powrocie.
  void _playSuccessAnimation() {
    AnimationPlayer(ref).play(
      context: context,
      type: _type,
      category: _category,
    );
  }

  /// Parsuje pole kwoty na grosze (`amount_cents`). Akceptuje `,` lub `.`
  /// jako separator dziesiętny, max 2 cyfry po przecinku.
  int? _parseAmount(String raw) {
    final cleaned = raw.replaceAll(' ', '').replaceAll(',', '.');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed <= 0) return null;
    return (parsed * 100).round();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pl', 'PL'),
    );
    if (picked != null) setState(() => _occurredAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final category =
        _resolveCategory(ref.read(categoriesProvider).value ?? const []);
    if (category == null) {
      setState(() => _errorMessage = 'Wybierz kategorię.');
      return;
    }
    _category = category;

    final householdId = ref.read(currentHouseholdIdProvider).value;
    if (householdId == null) {
      setState(
        () => _errorMessage = 'Brak gospodarstwa. Zaloguj się ponownie.',
      );
      return;
    }

    final amountCents = _parseAmount(_amountController.text);
    if (amountCents == null) {
      setState(() => _errorMessage = 'Kwota niepoprawna.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final repo = ref.read(transactionRepositoryProvider);
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    // Zapis z propozycji powiadomienia → miękka kontrola dubli: o tej samej
    // płatności mógł już wpis zrobić drugi telefon (innym tekstem, więc
    // twardy dedup_hash nie zadziała). Pytamy zamiast blokować.
    if (!_isEditing && widget.prefill != null) {
      final similar = await repo.findSameDay(
        householdId: householdId,
        amountCents: amountCents,
        type: _type,
        occurredAt: _occurredAt,
      );
      if (!mounted) return;
      if (similar.isNotEmpty) {
        final proceed = await _confirmPossibleDuplicate(similar.first);
        if (!mounted) return;
        if (!proceed) {
          setState(() => _isSaving = false);
          return;
        }
      }
    }

    final TransactionWriteResult result;
    if (_isEditing) {
      result = await repo.update(
        id: widget.existing!.id,
        occurredAt: _occurredAt,
        amountCents: amountCents,
        type: _type,
        categoryId: category.id,
        description: description,
        note: note,
      );
    } else {
      result = await repo.insert(
        householdId: householdId,
        occurredAt: _occurredAt,
        amountCents: amountCents,
        type: _type,
        categoryId: category.id,
        source: _fromVoice ? TransactionSource.voice : TransactionSource.manual,
        description: description,
        note: note,
      );
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    switch (result) {
      case TransactionWriteSuccess():
        ref.read(hapticsProvider).success();
        if (!_isEditing) _playSuccessAnimation();
        context.pop(true);
      case TransactionWriteQueued():
        // Brak sieci → zapisane lokalnie. UX: zamykamy formularz tak samo
        // jak przy sukcesie, ale dorzucamy snackbar — user musi widzieć
        // że to "czeka" inaczej będzie myślał że zapis się powiódł.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Zapisane offline — zsynchronizuje się gdy wróci internet.',
            ),
          ),
        );
        context.pop(true);
      case TransactionDuplicate():
        setState(
          () => _errorMessage = 'Ta sama transakcja jest już zapisana w bazie.',
        );
      case TransactionWriteFailure(:final message):
        setState(() => _errorMessage = message);
    }
  }

  /// Dialog „ten wydatek chyba już jest" — pokazuje istniejący wpis
  /// i pyta, czy na pewno dodać drugi.
  Future<bool> _confirmPossibleDuplicate(Transaction match) async {
    final amount =
        NumberFormat('#,##0.00', 'pl_PL').format(match.amountCents / 100);
    final date = DateFormat('d MMMM', 'pl_PL').format(match.occurredAt);
    final label = (match.description?.trim().isNotEmpty ?? false)
        ? '„${match.description!.trim()}"'
        : 'bez opisu';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ten wydatek chyba już jest'),
        content: Text(
          'W budżecie jest już wpis na $amount zł z $date ($label) — '
          'mógł go dodać drugi domownik albo import.\n\n'
          'Dodać mimo to drugi raz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Nie dodawaj'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Dodaj mimo to'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);
    final filteredCategories = categoriesAsync.maybeWhen(
      data: (cats) => cats.where((c) => c.type == _type).toList(),
      orElse: () => const <Category>[],
    );

    final dateLabel = DateFormat('d MMMM y', 'pl_PL').format(_occurredAt);

    final allCategories = categoriesAsync.value ?? const <Category>[];
    final selectedCategory = _resolveCategory(allCategories);
    final recentTxs =
        ref.watch(transactionsProvider).value ?? const <Transaction>[];
    final quickCategories = topCategories(
      transactions: recentTxs,
      candidates: filteredCategories,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edytuj transakcję' : 'Nowa transakcja'),
        actions: [
          if (!_isEditing) ...[
            VoiceInputButton(
              categories: allCategories,
              onResult: _applyVoiceResult,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              _TypeSelector(
                value: _type,
                onChanged: (v) => setState(() {
                  _type = v;
                  // Reset wyboru kategorii jeśli nie pasuje do nowego typu.
                  if (_category != null && _category!.type != v) {
                    _category = null;
                  }
                }),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                ],
                style: theme.textTheme.headlineMedium,
                decoration: const InputDecoration(
                  labelText: 'Kwota (PLN)',
                  hintText: '0,00',
                  prefixIcon: AppIcon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Wpisz kwotę.';
                  if (_parseAmount(v) == null) return 'Kwota niepoprawna.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (quickCategories.isNotEmpty) ...[
                _QuickCategoryChips(
                  categories: quickCategories,
                  selected: selectedCategory,
                  onChanged: (c) => setState(() => _category = c),
                ),
                const SizedBox(height: 10),
              ],
              _CategoryPickerField(
                categoriesAsync: categoriesAsync,
                items: filteredCategories,
                selected: selectedCategory,
                onChanged: (c) => setState(() => _category = c),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data',
                    prefixIcon: AppIcon(Icons.calendar_today_outlined),
                  ),
                  child: Text(dateLabel),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Opis (opcjonalny)',
                  hintText: 'Np. Biedronka, paliwo Orlen…',
                  prefixIcon: AppIcon(Icons.short_text),
                ),
              ),
              TextFormField(
                controller: _noteController,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Notatka (opcjonalna)',
                  prefixIcon: AppIcon(Icons.notes),
                ),
              ),
              const SizedBox(height: 8),
              if (_errorMessage != null) ...[
                InlineError(message: _errorMessage!),
                const SizedBox(height: 16),
              ],
              LoadingFilledButton(
                label: 'Zapisz',
                icon: Icons.check_circle_outline,
                isLoading: _isSaving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Najczęściej używane kategorie (po liczbie transakcji w gospodarstwie),
/// ograniczone do [candidates] — listy już przefiltrowanej po typie.
/// Zasila szybkie chipy nad dropdownem kategorii.
List<Category> topCategories({
  required List<Transaction> transactions,
  required List<Category> candidates,
  int max = 5,
}) {
  if (candidates.isEmpty) return const [];
  final counts = <String, int>{};
  for (final t in transactions) {
    counts.update(t.categoryId, (v) => v + 1, ifAbsent: () => 1);
  }
  final used = [
    for (final c in candidates)
      if ((counts[c.id] ?? 0) > 0) c,
  ]..sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
  return used.take(max).toList();
}

/// Chipy szybkiego wyboru kategorii — top 5 najczęściej używanych.
class _QuickCategoryChips extends StatelessWidget {
  const _QuickCategoryChips({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  final List<Category> categories;
  final Category? selected;
  final ValueChanged<Category> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final c in categories)
          ChoiceChip(
            avatar: CategoryAvatar(category: c, size: 22),
            label: Text(c.name),
            selected: c.id == selected?.id,
            onSelected: (_) => onChanged(c),
          ),
      ],
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.value, required this.onChanged});

  final TransactionType value;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TransactionType>(
      segments: const [
        ButtonSegment(
          value: TransactionType.expense,
          label: Text('Wydatek'),
          icon: AppIcon(Icons.south_outlined),
        ),
        ButtonSegment(
          value: TransactionType.income,
          label: Text('Dochód'),
          icon: AppIcon(Icons.north_outlined),
        ),
      ],
      selected: {value},
      onSelectionChanged: (set) => onChanged(set.first),
    );
  }
}

class _CategoryPickerField extends StatelessWidget {
  const _CategoryPickerField({
    required this.categoriesAsync,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final AsyncValue<List<Category>> categoriesAsync;
  final List<Category> items;
  final Category? selected;
  final ValueChanged<Category?> onChanged;

  @override
  Widget build(BuildContext context) {
    return categoriesAsync.when(
      loading: () => const _CategoryFieldShell(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      ),
      error: (e, _) => _CategoryFieldShell(
        child: Text(humanizeError(e)),
      ),
      data: (_) {
        // Grupujemy: kategoria główna, a pod nią wcięte podkategorie.
        // Można wybrać dowolny poziom.
        final ordered = _groupByParent(items);
        // Zaznaczona wartość MUSI być dokładnie jednym z elementów listy —
        // inaczej DropdownButton rzuca asercję. Wyznaczamy ją z aktualnej
        // listy po `id` (gdy kategorii już nie ma / zła dla typu → null).
        final value = ordered.where((c) => c.id == selected?.id).firstOrNull;
        return DropdownButtonFormField<Category>(
          // `key` per typ wymusza rebuild dropdownu gdy user przełączy
          // wydatek↔dochód — inaczej wewnętrzny stan FormField może
          // zostać przy starej kategorii (poprzedniego typu).
          key: ValueKey(ordered.firstOrNull?.type),
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Kategoria',
            prefixIcon: AppIcon(Icons.category_outlined),
          ),
          items: [
            for (final c in ordered)
              DropdownMenuItem<Category>(
                value: c,
                child: Padding(
                  padding: EdgeInsets.only(left: c.isSubcategory ? 20 : 0),
                  child: Row(
                    children: [
                      if (c.isSubcategory)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.subdirectory_arrow_right,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      CategoryAvatar(category: c, size: 28),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          onChanged: onChanged,
          validator: (v) => v == null ? 'Wybierz kategorię.' : null,
        );
      },
    );
  }
}

/// Porządkuje kategorie hierarchicznie: każda kategoria główna, a zaraz po
/// niej jej podkategorie (alfabetycznie). Sieroty (podkategoria bez rodzica
/// na liście) trafiają na koniec.
List<Category> _groupByParent(List<Category> items) {
  int byName(Category a, Category b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final tops = items.where((c) => c.parentId == null).toList()..sort(byName);
  final childrenByParent = <String, List<Category>>{};
  for (final c in items.where((c) => c.parentId != null)) {
    childrenByParent.putIfAbsent(c.parentId!, () => []).add(c);
  }
  final topIds = tops.map((c) => c.id).toSet();
  final ordered = <Category>[];
  for (final top in tops) {
    ordered.add(top);
    final kids = childrenByParent[top.id] ?? const [];
    ordered.addAll(kids.toList()..sort(byName));
  }
  // Podkategorie, których rodzica nie ma w tym zbiorze.
  for (final c in items.where(
    (c) => c.parentId != null && !topIds.contains(c.parentId),
  )) {
    ordered.add(c);
  }
  return ordered;
}

class _CategoryFieldShell extends StatelessWidget {
  const _CategoryFieldShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Kategoria',
        prefixIcon: AppIcon(Icons.category_outlined),
      ),
      child: child,
    );
  }
}
