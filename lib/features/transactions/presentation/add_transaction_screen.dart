import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/core/error_messages.dart';
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

/// Form ręcznego dodawania transakcji.
///
/// Pola: typ (segmented control), kwota, kategoria (filtrowana po typie),
/// data (datepicker), opis (opcjonalny), notatka (opcjonalna).
///
/// Walidacje są inline na poszczególnych polach; submit blokowany dopóki
/// wszystkie poprawne. Po sukcesie wraca do ekranu listy.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

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
    if (_category == null) {
      setState(() => _errorMessage = 'Wybierz kategorię.');
      return;
    }

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
    final result = await repo.insert(
      householdId: householdId,
      occurredAt: _occurredAt,
      amountCents: amountCents,
      type: _type,
      categoryId: _category!.id,
      source: _fromVoice ? TransactionSource.voice : TransactionSource.manual,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    switch (result) {
      case TransactionWriteSuccess():
        _playSuccessAnimation();
        context.pop();
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
        context.pop();
      case TransactionDuplicate():
        setState(
          () => _errorMessage = 'Ta sama transakcja jest już zapisana w bazie.',
        );
      case TransactionWriteFailure(:final message):
        setState(() => _errorMessage = message);
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nowa transakcja'),
        actions: [
          VoiceInputButton(
            categories: allCategories,
            onResult: _applyVoiceResult,
          ),
          const SizedBox(width: 8),
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
              _CategoryPickerField(
                categoriesAsync: categoriesAsync,
                items: filteredCategories,
                selected: _category,
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
