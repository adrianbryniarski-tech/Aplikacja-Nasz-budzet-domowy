import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/core/supabase/supabase_client.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/recurring_transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// CRUD szablonów cyklicznych + materializacja zaległych naliczeń.
class RecurringRepository {
  const RecurringRepository();

  static const _uuid = Uuid();

  Future<List<RecurringTransaction>> list(String householdId) async {
    final rows = await supabase
        .from('recurring_transactions')
        .select()
        .eq('household_id', householdId)
        .order('name', ascending: true)
        .timeout(kSupabaseWriteTimeout);
    return rows.map(RecurringTransaction.fromJson).toList();
  }

  Future<void> create({
    required String householdId,
    required String name,
    required int amountCents,
    required TransactionType type,
    required String categoryId,
    required int dayOfMonth,
    String? note,
  }) async {
    final user = supabase.auth.currentUser;
    await supabase.from('recurring_transactions').insert({
      'household_id': householdId,
      'name': name,
      'amount_cents': amountCents,
      'type': type.toDbValue(),
      'category_id': categoryId,
      'note': note,
      'day_of_month': dayOfMonth,
      'next_due': _dateOnly(firstDueDate(DateTime.now(), dayOfMonth)),
      'created_by': user?.id,
    }).timeout(kSupabaseWriteTimeout);
  }

  Future<void> setActive(String id, {required bool active}) async {
    await supabase
        .from('recurring_transactions')
        .update({'active': active})
        .eq('id', id)
        .timeout(kSupabaseWriteTimeout);
  }

  Future<void> delete(String id) async {
    await supabase
        .from('recurring_transactions')
        .delete()
        .eq('id', id)
        .timeout(kSupabaseWriteTimeout);
  }

  /// Nalicza zaległe transakcje cykliczne gospodarstwa.
  ///
  /// Dla każdego aktywnego szablonu z `next_due <= dziś`: INSERT
  /// transakcji na dzień naliczenia (source `recurring`, dedup_hash z
  /// (data|kwota|nazwa) — drugi telefon naliczający równolegle dostanie
  /// 23505 i pominie), potem przesunięcie `next_due` o miesiąc z guardem
  /// `eq(next_due, stara)` — przegrany wyścigu nic nie nadpisze.
  ///
  /// Zwraca liczbę WSTAWIONYCH transakcji (duble się nie liczą).
  /// Best-effort: błędy sieci są logowane, nie rzucane — naliczanie
  /// dokończy się przy kolejnym starcie apki.
  Future<int> materializeDue(String householdId) async {
    var inserted = 0;
    try {
      final today = DateTime.now();
      final rows = await supabase
          .from('recurring_transactions')
          .select()
          .eq('household_id', householdId)
          .eq('active', true)
          .lte('next_due', _dateOnly(today))
          .timeout(const Duration(seconds: 12));
      final due = rows.map(RecurringTransaction.fromJson).toList();

      for (final r in due) {
        var dueDate = r.nextDue;
        // Nadrabiamy też zaległe miesiące (apka nieotwierana dłużej);
        // limit 24 iteracji = bezpiecznik przed pętlą.
        var guard = 0;
        while (!dueDate.isAfter(today) && guard < 24) {
          guard++;
          if (await _insertOccurrence(r, dueDate)) inserted++;
          final next = nextDueAfter(dueDate, r.dayOfMonth);
          await supabase
              .from('recurring_transactions')
              .update({'next_due': _dateOnly(next)})
              .eq('id', r.id)
              .eq('next_due', _dateOnly(dueDate))
              .timeout(const Duration(seconds: 12));
          dueDate = next;
        }
      }
    } on Object catch (e) {
      debugPrint('recurring materialize: $e');
    }
    return inserted;
  }

  /// INSERT pojedynczego naliczenia. `true` = wstawiono, `false` = dubel
  /// (23505 — naliczone już z drugiego telefonu).
  Future<bool> _insertOccurrence(
    RecurringTransaction r,
    DateTime dueDate,
  ) async {
    final dedupHash = TransactionHasher.compute(
      occurredAt: dueDate,
      amountCents: r.amountCents,
      description: r.name,
    );
    try {
      await supabase.from('transactions').insert({
        'household_id': r.householdId,
        'occurred_at': _dateOnly(dueDate),
        'amount_cents': r.amountCents,
        'type': r.type.toDbValue(),
        'category_id': r.categoryId,
        'description': r.name,
        'note': r.note,
        'source': TransactionSource.recurring.toDbValue(),
        'dedup_hash': dedupHash,
        'client_op_id': _uuid.v4(),
        'created_by': supabase.auth.currentUser?.id,
      }).timeout(const Duration(seconds: 12));
      return true;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return false;
      rethrow;
    }
  }

  static String _dateOnly(DateTime dt) {
    final iso = DateTime.utc(dt.year, dt.month, dt.day).toIso8601String();
    return iso.substring(0, 10);
  }
}
