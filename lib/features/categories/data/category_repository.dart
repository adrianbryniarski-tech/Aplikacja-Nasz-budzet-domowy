import 'package:flutter/foundation.dart' hide Category;
import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/core/supabase/supabase_client.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wynik próby zapisu kategorii.
sealed class CategoryWriteResult {
  const CategoryWriteResult();
}

class CategoryWriteSuccess extends CategoryWriteResult {
  const CategoryWriteSuccess();
}

class CategoryDuplicateName extends CategoryWriteResult {
  const CategoryDuplicateName();
}

class CategoryWriteFailure extends CategoryWriteResult {
  const CategoryWriteFailure(this.message);
  final String message;
}

class CategoryRepository {
  const CategoryRepository();

  /// Realtime stream wszystkich kategorii gospodarstwa.
  Stream<List<Category>> watchAll(String householdId) {
    return supabase
        .from('categories')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .order('name')
        .map((rows) => rows.map(Category.fromJson).toList());
  }

  /// Dodaje nową własną kategorię. RLS blokuje insert z `is_system=true`.
  /// `parentId` != null → podkategoria (musi być ten sam typ co rodzic).
  Future<CategoryWriteResult> insert({
    required String householdId,
    required String name,
    required String icon,
    required String colorHex,
    required TransactionType type,
    String? parentId,
  }) async {
    try {
      await supabase.from('categories').insert({
        'household_id': householdId,
        'name': name,
        'icon': icon,
        'color': colorHex,
        'type': type.toDbValue(),
        'is_system': false,
        'parent_id': parentId,
      }).timeout(kSupabaseWriteTimeout);
      return const CategoryWriteSuccess();
    } on PostgrestException catch (e) {
      if (e.code == '23505') return const CategoryDuplicateName();
      return CategoryWriteFailure(e.message);
    } on Object catch (e) {
      // Timeout / brak sieci — po ludzku zamiast nieobsłużonego wyjątku.
      return CategoryWriteFailure(humanizeError(e));
    }
  }

  /// Aktualizuje własną kategorię. System (`is_system=true`) jest blokowany
  /// przez RLS — UI nie powinien w ogóle pokazywać edycji. `parentId`
  /// ustawia/zmienia kategorię nadrzędną (null = kategoria główna).
  Future<CategoryWriteResult> update({
    required String id,
    required String name,
    required String icon,
    required String colorHex,
    required TransactionType type,
    String? parentId,
  }) async {
    try {
      await supabase
          .from('categories')
          .update({
            'name': name,
            'icon': icon,
            'color': colorHex,
            'type': type.toDbValue(),
            'parent_id': parentId,
          })
          .eq('id', id)
          .timeout(kSupabaseWriteTimeout);
      return const CategoryWriteSuccess();
    } on PostgrestException catch (e) {
      if (e.code == '23505') return const CategoryDuplicateName();
      return CategoryWriteFailure(e.message);
    } on Object catch (e) {
      // Timeout / brak sieci — po ludzku zamiast nieobsłużonego wyjątku.
      return CategoryWriteFailure(humanizeError(e));
    }
  }

  /// Usuwa kategorię bez transakcji. Zakłada, że caller sprawdził pusty
  /// licznik — jeśli są transakcje, FK constraint zwróci błąd.
  Future<CategoryWriteResult> delete(String id) async {
    try {
      await supabase
          .from('categories')
          .delete()
          .eq('id', id)
          .timeout(kSupabaseWriteTimeout);
      return const CategoryWriteSuccess();
    } on PostgrestException catch (e) {
      return CategoryWriteFailure(e.message);
    } on Object catch (e) {
      return CategoryWriteFailure(humanizeError(e));
    }
  }

  /// Usuwa kategorię z transakcjami — najpierw atomowo reasignuje
  /// transakcje do `targetId` przez RPC `delete_category_with_reassign`.
  Future<CategoryWriteResult> deleteWithReassign({
    required String oldId,
    required String targetId,
  }) async {
    try {
      await supabase.rpc<void>(
        'delete_category_with_reassign',
        params: {'p_old_id': oldId, 'p_target_id': targetId},
      ).timeout(kSupabaseWriteTimeout);
      return const CategoryWriteSuccess();
    } on PostgrestException catch (e) {
      return CategoryWriteFailure(humanizeRpcError(e));
    } on Object catch (e) {
      return CategoryWriteFailure(humanizeError(e));
    }
  }

  /// Tłumaczy kody błędów RPC `delete_category_with_reassign` na komunikaty
  /// po polsku. Publiczne wyłącznie dla testów.
  @visibleForTesting
  String humanizeRpcError(PostgrestException e) {
    return switch (e.code) {
      'P0010' => 'Nie można usunąć kategorii systemowej.',
      'P0011' => 'Kategoria docelowa należy do innego gospodarstwa.',
      'P0012' => 'Kategoria docelowa ma inny typ (dochód/wydatek) niż usuwana.',
      '42501' => 'Brak uprawnień.',
      _ => e.message,
    };
  }
}
