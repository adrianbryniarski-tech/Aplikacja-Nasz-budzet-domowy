import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

/// Szablon transakcji cyklicznej. Mirror tabeli PG `recurring_transactions`.
///
/// `nextDue` to data najbliższego naliczenia; materializacja przesuwa ją
/// o miesiąc do przodu (z clampem dnia — 31. w lutym naliczy się 28./29.).
class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.householdId,
    required this.name,
    required this.amountCents,
    required this.type,
    required this.categoryId,
    required this.dayOfMonth,
    required this.nextDue,
    required this.active,
    this.note,
  });

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) {
    return RecurringTransaction(
      id: json['id'] as String,
      householdId: json['household_id'] as String,
      name: json['name'] as String,
      amountCents: (json['amount_cents'] as num).toInt(),
      type: TransactionType.fromDbValue(json['type'] as String),
      categoryId: json['category_id'] as String,
      note: json['note'] as String?,
      dayOfMonth: (json['day_of_month'] as num).toInt(),
      nextDue: DateTime.parse(json['next_due'] as String),
      active: json['active'] as bool,
    );
  }

  final String id;
  final String householdId;
  final String name;
  final int amountCents;
  final TransactionType type;
  final String categoryId;
  final String? note;
  final int dayOfMonth;
  final DateTime nextDue;
  final bool active;
}

/// Data pierwszego naliczenia dla nowego szablonu: najbliższy `dayOfMonth`
/// (dzisiaj, jeśli dziś jest ten dzień; w krótszych miesiącach — ostatni
/// dzień miesiąca).
DateTime firstDueDate(DateTime today, int dayOfMonth) {
  final thisMonth = clampedDate(today.year, today.month, dayOfMonth);
  final todayDate = DateTime(today.year, today.month, today.day);
  if (!thisMonth.isBefore(todayDate)) return thisMonth;
  return clampedDate(today.year, today.month + 1, dayOfMonth);
}

/// Następne naliczenie po [due] — miesiąc dalej, dzień z clampem.
DateTime nextDueAfter(DateTime due, int dayOfMonth) {
  return clampedDate(due.year, due.month + 1, dayOfMonth);
}

/// `DateTime(y, m, day)` z dniem przyciętym do długości miesiąca
/// (np. 31 → 30 kwietnia, 31 → 28/29 lutego).
DateTime clampedDate(int year, int month, int day) {
  // Dzień 0 następnego miesiąca = ostatni dzień bieżącego.
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}
