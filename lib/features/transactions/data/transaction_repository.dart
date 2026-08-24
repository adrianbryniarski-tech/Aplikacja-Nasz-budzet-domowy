import 'dart:async';

import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/core/offline/pending_ops_dao.dart';
import 'package:nasz_budzet_domowy/core/offline/pending_transaction.dart';
import 'package:nasz_budzet_domowy/core/offline/sync_worker.dart';
import 'package:nasz_budzet_domowy/core/supabase/supabase_client.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Wynik próby zapisu transakcji.
sealed class TransactionWriteResult {
  const TransactionWriteResult();
}

class TransactionWriteSuccess extends TransactionWriteResult {
  const TransactionWriteSuccess(this.transaction);
  final Transaction transaction;
}

/// Zapisane lokalnie — czeka na wysyłkę gdy wróci sieć.
class TransactionWriteQueued extends TransactionWriteResult {
  const TransactionWriteQueued(this.pending);
  final PendingTransaction pending;
}

/// Duplikat — `UNIQUE(household_id, dedup_hash)` zwrócił 23505.
class TransactionDuplicate extends TransactionWriteResult {
  const TransactionDuplicate();
}

class TransactionWriteFailure extends TransactionWriteResult {
  const TransactionWriteFailure(this.message);
  final String message;
}

/// CRUD + realtime na `transactions` z fallbackiem do lokalnej kolejki.
///
/// Flow `insert()`:
/// 1. Liczy `dedup_hash` + `client_op_id`.
/// 2. Próbuje wepchnąć do Supabase.
/// 3a. Sukces → `TransactionWriteSuccess` (Supabase realtime przyniesie
///     rekord do listy w drugim kanale).
/// 3b. 23505 → `TransactionDuplicate` (UI: "ten zapis już jest").
/// 3c. Sieciowy błąd → zapis w lokalnej kolejce + `TransactionWriteQueued`
///     (UI: "Zapisane offline — zsynchronizuje gdy wróci internet").
/// 3d. RLS / inny błąd PG → `TransactionWriteFailure(message)`.
class TransactionRepository {
  TransactionRepository(this._pendingOpsDao, this._syncWorker)
      : _uuid = const Uuid();

  final PendingOpsDao _pendingOpsDao;
  final SyncWorker _syncWorker;
  final Uuid _uuid;

  /// Strumień transakcji gospodarstwa, sortowany malejąco po dacie.
  Stream<List<Transaction>> watchAll(String householdId) {
    return supabase
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .order('occurred_at')
        .map((rows) => rows.map(Transaction.fromJson).toList());
  }

  Future<TransactionWriteResult> insert({
    required String householdId,
    required DateTime occurredAt,
    required int amountCents,
    required TransactionType type,
    required String categoryId,
    required TransactionSource source,
    String? description,
    String? note,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return const TransactionWriteFailure('Brak sesji — zaloguj się.');
    }

    final dedupHash = TransactionHasher.compute(
      occurredAt: occurredAt,
      amountCents: amountCents,
      description: description,
    );
    final clientOpId = _uuid.v4();

    final pending = PendingTransaction(
      clientOpId: clientOpId,
      householdId: householdId,
      createdBy: user.id,
      occurredAt: occurredAt,
      amountCents: amountCents,
      type: type,
      categoryId: categoryId,
      description: description,
      note: note,
      source: source,
      dedupHash: dedupHash,
      enqueuedAt: DateTime.now(),
      retryCount: 0,
    );

    try {
      final row = await supabase
          .from('transactions')
          .insert(pending.toSupabaseInsert())
          .select()
          .single()
          // Zawieszony socket → TimeoutException → gałąź `on Object`
          // niżej, czyli zapis do lokalnej kolejki zamiast wiecznego
          // kręcenia na przycisku „Zapisz".
          .timeout(kSupabaseWriteTimeout);
      return TransactionWriteSuccess(Transaction.fromJson(row));
    } on PostgrestException catch (e) {
      // 23505 = duplikat (dedup_hash lub client_op_id). UX: "już jest".
      if (e.code == '23505') return const TransactionDuplicate();
      // Inny błąd PG (RLS, foreign key, walidacja) — nie ma sensu kolejkować,
      // bo retry da ten sam wynik.
      return TransactionWriteFailure('Nie udało się zapisać: ${e.message}');
    } on Object catch (_) {
      // Sieciowy / SocketException / timeout — kolejkujemy lokalnie.
      // SyncWorker spróbuje ponownie po odzyskaniu połączenia.
      await _pendingOpsDao.enqueue(pending);
      // Trigger drain — jeśli sieć już wróciła w międzyczasie, od razu
      // złapiemy okazję bez czekania na connectivity event.
      unawaited(_syncWorker.syncNow());
      return TransactionWriteQueued(pending);
    }
  }

  /// Edycja istniejącej transakcji. Przelicza `dedup_hash` (kwota/data/opis
  /// to składniki odcisku). Bez kolejki offline — edycja wymaga sieci,
  /// w razie braku user dostaje ludzki komunikat i może spróbować później.
  Future<TransactionWriteResult> update({
    required String id,
    required DateTime occurredAt,
    required int amountCents,
    required TransactionType type,
    required String categoryId,
    String? description,
    String? note,
  }) async {
    final dedupHash = TransactionHasher.compute(
      occurredAt: occurredAt,
      amountCents: amountCents,
      description: description,
    );
    try {
      final row = await supabase
          .from('transactions')
          .update({
            'occurred_at': _dateOnly(occurredAt),
            'amount_cents': amountCents,
            'type': type.toDbValue(),
            'category_id': categoryId,
            'description': description,
            'note': note,
            'dedup_hash': dedupHash,
          })
          .eq('id', id)
          .select()
          .single()
          .timeout(kSupabaseWriteTimeout);
      return TransactionWriteSuccess(Transaction.fromJson(row));
    } on PostgrestException catch (e) {
      if (e.code == '23505') return const TransactionDuplicate();
      return TransactionWriteFailure('Nie udało się zapisać: ${e.message}');
    } on Object catch (e) {
      return TransactionWriteFailure(humanizeError(e));
    }
  }

  /// Transakcje gospodarstwa z tego samego DNIA o tej samej kwocie i typie.
  ///
  /// Miękka detekcja dubli przy zapisie z propozycji powiadomienia: o jednej
  /// płatności mogą powiadomić dwa telefony (mąż i żona) różnym tekstem,
  /// więc twardy `dedup_hash` (liczy opis) ich nie złapie. Best-effort —
  /// błąd sieci zwraca pustą listę i nie blokuje zapisu.
  Future<List<Transaction>> findSameDay({
    required String householdId,
    required int amountCents,
    required TransactionType type,
    required DateTime occurredAt,
  }) async {
    try {
      final rows = await supabase
          .from('transactions')
          .select()
          .eq('household_id', householdId)
          .eq('amount_cents', amountCents)
          .eq('type', type.toDbValue())
          .eq('occurred_at', _dateOnly(occurredAt))
          .limit(3)
          .timeout(const Duration(seconds: 8));
      return rows.map(Transaction.fromJson).toList();
    } on Object {
      return const [];
    }
  }

  Future<void> delete(String id) async {
    await supabase
        .from('transactions')
        .delete()
        .eq('id', id)
        .timeout(kSupabaseWriteTimeout);
  }

  /// „Zacznij od nowa": usuwa WSZYSTKIE transakcje gospodarstwa (u obojga
  /// domowników — dane są wspólne). Nie dotyka inwestycji, kategorii,
  /// budżetów, cyklicznych ani nauczonych reguł importu. Zwraca liczbę
  /// usuniętych wpisów. Dłuższy timeout — to setki wierszy naraz.
  Future<int> deleteAllForHousehold(String householdId) async {
    final rows = await supabase
        .from('transactions')
        .delete()
        .eq('household_id', householdId)
        .select('id')
        .timeout(const Duration(seconds: 30));
    return rows.length;
  }

  /// `occurred_at` w bazie to kolumna `date` — serializacja identyczna jak
  /// w [PendingTransaction.toSupabaseInsert] (data UTC, bez godziny).
  static String _dateOnly(DateTime dt) {
    final iso = DateTime.utc(dt.year, dt.month, dt.day).toIso8601String();
    return iso.substring(0, 10);
  }
}
