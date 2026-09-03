import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_notifications.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/statement_categorizer.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction_repository.dart';

/// Reguły „sklep → kategoria" nauczone od domowników (`merchant_rules`).
/// Te same, których używa import wyciągów — nauka z jednego miejsca
/// działa w drugim.
final merchantRulesProvider = FutureProvider<List<MerchantRule>>((ref) async {
  final householdId = ref.watch(currentHouseholdIdProvider).value;
  if (householdId == null) return const [];
  try {
    return await ref.watch(importRepositoryProvider).merchantRules(householdId);
  } on Object {
    // Brak sieci: kategoryzujemy samymi wbudowanymi wzorcami.
    return const [];
  }
});

/// Kategoryzator dla propozycji z powiadomień: nauczone reguły + wbudowana
/// lista polskich sieci (Biedronka → Spożywcze, Orlen → Transport…).
final suggestionCategorizerProvider = Provider<StatementCategorizer?>((ref) {
  final categories = ref.watch(categoriesProvider).value;
  if (categories == null || categories.isEmpty) return null;
  return StatementCategorizer(
    categories: categories,
    learnedRules: ref.watch(merchantRulesProvider).value ?? const [],
  );
});

/// Kategoria zgadnięta dla propozycji — `null` gdy apka nie wie i musi
/// zapytać użytkownika.
Category? guessCategoryFor(
  BankSuggestion suggestion, {
  required StatementCategorizer? categorizer,
  required List<Category> categories,
}) {
  if (categorizer == null) return null;
  final id = categorizer.categoryIdFor(suggestion.merchant, suggestion.type);
  if (id == null) return null;
  for (final c in categories) {
    if (c.id == id) return c;
  }
  return null;
}

/// Wynik zatwierdzenia propozycji — do komunikatu w UI.
sealed class SuggestionSaveResult {
  const SuggestionSaveResult();
}

class SuggestionSaved extends SuggestionSaveResult {
  const SuggestionSaved({required this.queued});

  /// `true` = poszło do kolejki offline (wyśle się samo po powrocie sieci).
  final bool queued;
}

class SuggestionAlreadyBooked extends SuggestionSaveResult {
  const SuggestionAlreadyBooked();
}

class SuggestionSaveFailed extends SuggestionSaveResult {
  const SuggestionSaveFailed(this.message);

  final String message;
}

/// Zapisuje propozycję jako transakcję jednym tapnięciem.
///
/// [learn] = użytkownik wybrał kategorię RĘCZNIE → zapamiętujemy regułę
/// „ten sklep → ta kategoria", żeby następny raz apka trafiła sama
/// (dokładnie ta sama pamięć, z której korzysta import wyciągów).
/// Propozycję usuwamy z kolejki tylko po udanym zapisie — przy błędzie
/// zostaje, żeby dało się spróbować ponownie.
Future<SuggestionSaveResult> saveBankSuggestion(
  WidgetRef ref, {
  required BankSuggestion suggestion,
  required String categoryId,
  required bool learn,
}) async {
  final householdId = ref.read(currentHouseholdIdProvider).value;
  if (householdId == null) {
    return const SuggestionSaveFailed('Brak gospodarstwa — zaloguj się.');
  }

  final result = await ref.read(transactionRepositoryProvider).insert(
        householdId: householdId,
        occurredAt: suggestion.capturedAt,
        amountCents: suggestion.amountCents,
        type: suggestion.type,
        categoryId: categoryId,
        source: TransactionSource.manual,
        description: suggestion.merchant,
      );

  switch (result) {
    case TransactionWriteSuccess():
    case TransactionWriteQueued():
      if (learn) {
        await ref.read(importRepositoryProvider).upsertMerchantRule(
              householdId: householdId,
              pattern: StatementCategorizer.patternFor(suggestion.merchant),
              categoryId: categoryId,
            );
        ref.invalidate(merchantRulesProvider);
      }
      await ref.read(bankSuggestionsProvider.notifier).remove(suggestion.id);
      ref.invalidate(transactionsProvider);
      return SuggestionSaved(queued: result is TransactionWriteQueued);
    case TransactionDuplicate():
      // Ktoś już to zapisał (drugi telefon) — propozycja jest zbędna.
      await ref.read(bankSuggestionsProvider.notifier).remove(suggestion.id);
      return const SuggestionAlreadyBooked();
    case TransactionWriteFailure(:final message):
      return SuggestionSaveFailed(message);
  }
}
