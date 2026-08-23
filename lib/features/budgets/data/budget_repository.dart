import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/core/supabase/supabase_client.dart';
import 'package:nasz_budzet_domowy/features/budgets/data/budget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

sealed class BudgetWriteResult {
  const BudgetWriteResult();
}

class BudgetWriteSuccess extends BudgetWriteResult {
  const BudgetWriteSuccess();
}

class BudgetDuplicate extends BudgetWriteResult {
  const BudgetDuplicate();
}

class BudgetWriteFailure extends BudgetWriteResult {
  const BudgetWriteFailure(this.message);
  final String message;
}

class BudgetRepository {
  const BudgetRepository();

  /// Strumień wszystkich budżetów gospodarstwa.
  Stream<List<Budget>> watchAll(String householdId) {
    return supabase
        .from('budgets')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .order('starts_on')
        .map((rows) => rows.map(Budget.fromJson).toList());
  }

  /// Tworzy nowy budżet. `startsOn` to pierwszy dzień miesiąca.
  /// Schema ma `UNIQUE(household_id, category_id, starts_on)` — duplikat
  /// dla tego samego (kategoria, miesiąc) zwraca [BudgetDuplicate].
  Future<BudgetWriteResult> insert({
    required String householdId,
    required String categoryId,
    required int amountCents,
    required DateTime startsOn,
  }) async {
    try {
      await supabase.from('budgets').insert({
        'household_id': householdId,
        'category_id': categoryId,
        'amount_cents': amountCents,
        'period': 'monthly',
        'starts_on': _formatDate(startsOn),
      }).timeout(kSupabaseWriteTimeout);
      return const BudgetWriteSuccess();
    } on PostgrestException catch (e) {
      if (e.code == '23505') return const BudgetDuplicate();
      return BudgetWriteFailure(e.message);
    } on Object catch (e) {
      // Timeout / brak sieci — po ludzku zamiast nieobsłużonego wyjątku.
      return BudgetWriteFailure(humanizeError(e));
    }
  }

  Future<BudgetWriteResult> updateAmount({
    required String id,
    required int amountCents,
  }) async {
    try {
      await supabase
          .from('budgets')
          .update({'amount_cents': amountCents})
          .eq('id', id)
          .timeout(kSupabaseWriteTimeout);
      return const BudgetWriteSuccess();
    } on PostgrestException catch (e) {
      return BudgetWriteFailure(e.message);
    } on Object catch (e) {
      return BudgetWriteFailure(humanizeError(e));
    }
  }

  Future<BudgetWriteResult> delete(String id) async {
    try {
      await supabase
          .from('budgets')
          .delete()
          .eq('id', id)
          .timeout(kSupabaseWriteTimeout);
      return const BudgetWriteSuccess();
    } on PostgrestException catch (e) {
      return BudgetWriteFailure(e.message);
    } on Object catch (e) {
      return BudgetWriteFailure(humanizeError(e));
    }
  }

  String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
