import 'dart:async';

import 'package:nasz_budzet_domowy/core/offline/local_db.dart';
import 'package:nasz_budzet_domowy/core/offline/pending_transaction.dart';
import 'package:sqflite/sqflite.dart';

/// CRUD na tabeli `pending_transactions` + stream zmian.
///
/// Stream jest tu broadcast'em na `StreamController` ręcznie pingowanym
/// przy każdej mutacji DAO. Sqflite nie ma natywnego notify-on-change,
/// więc utrzymujemy go w pamięci. Jeden DAO = jeden controller = OK
/// bo robimy singleton w providerze.
class PendingOpsDao {
  PendingOpsDao(this._db);

  final LocalDb _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Po tylu nieudanych próbach operacja jest traktowana jako "dead-letter"
  /// — nie próbujemy jej już synchronizować, ale zostaje w bazie do
  /// inspekcji / manualnej akcji usera. Bez tego limitu jedna trwale zła
  /// operacja (np. transakcja z usuniętą kategorią) blokowałaby kolejkę
  /// w nieskończoność.
  static const maxRetries = 5;

  /// Wstawia nowy pending — kolizja `client_op_id` (już zakolejkowany)
  /// jest ignorowana (idempotency: ten sam op zapisany dwa razy).
  Future<void> enqueue(PendingTransaction op) async {
    final db = await _db.database;
    await db.insert(
      'pending_transactions',
      op.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _changes.add(null);
  }

  Future<List<PendingTransaction>> listAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'pending_transactions',
      orderBy: 'enqueued_at ASC',
    );
    return rows.map(PendingTransaction.fromMap).toList();
  }

  Future<List<PendingTransaction>> listForHousehold(String householdId) async {
    final db = await _db.database;
    final rows = await db.query(
      'pending_transactions',
      where: 'household_id = ?',
      whereArgs: [householdId],
      orderBy: 'enqueued_at ASC',
    );
    return rows.map(PendingTransaction.fromMap).toList();
  }

  /// Pendingi danego usera, pomijając dead-lettery (po `maxRetries` próbach).
  /// Worker NIE PRÓBUJE ich już wysyłać — czekają tylko w bazie.
  ///
  /// Filtr po `created_by` zapobiega scenariuszowi: user A wpisał transakcję
  /// offline → wylogował się → user B zalogował na tym samym telefonie →
  /// worker próbuje wepchnąć op user-a A jako user B → RLS odrzuca wiecznie.
  Future<List<PendingTransaction>> listForUser(String userId) async {
    final db = await _db.database;
    final rows = await db.query(
      'pending_transactions',
      where: 'created_by = ? AND retry_count < ?',
      whereArgs: [userId, maxRetries],
      orderBy: 'enqueued_at ASC',
    );
    return rows.map(PendingTransaction.fromMap).toList();
  }

  Future<int> countAll() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM pending_transactions',
    );
    return (rows.first['n']! as num).toInt();
  }

  Future<int> countWithErrors() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM pending_transactions '
      'WHERE last_error IS NOT NULL',
    );
    return (rows.first['n']! as num).toInt();
  }

  Future<void> markFailure(String clientOpId, String error) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE pending_transactions '
      'SET last_error = ?, retry_count = retry_count + 1 '
      'WHERE client_op_id = ?',
      [error, clientOpId],
    );
    _changes.add(null);
  }

  Future<void> remove(String clientOpId) async {
    final db = await _db.database;
    await db.delete(
      'pending_transactions',
      where: 'client_op_id = ?',
      whereArgs: [clientOpId],
    );
    _changes.add(null);
  }

  /// Stream odpalany na każdą mutację — konsument robi `listForHousehold`
  /// żeby dostać świeżą listę. Pierwsza wartość emitowana natychmiast
  /// po subskrypcji żeby UI nie wisiał na pustym ekranie.
  Stream<List<PendingTransaction>> watchForHousehold(String householdId) {
    late StreamController<List<PendingTransaction>> ctrl;
    StreamSubscription<void>? sub;

    Future<void> emit() async {
      if (ctrl.isClosed) return;
      try {
        ctrl.add(await listForHousehold(householdId));
      } on Object catch (e, st) {
        // Bez tego odrzucony future z `listForHousehold` (np. uszkodzony
        // plik sqflite) jest porzucany w `onListen` — konsument nie
        // dostaje ani danych, ani błędu i wisi na spinnerze na zawsze.
        if (!ctrl.isClosed) ctrl.addError(e, st);
      }
    }

    ctrl = StreamController<List<PendingTransaction>>(
      onListen: () {
        sub = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return ctrl.stream;
  }

  /// Stream sumy operacji w kolejce (po household-zie nie filtrujemy —
  /// status indicator pokazuje globalny stan, nie per gospodarstwo).
  Stream<({int total, int errors})> watchCounts() {
    late StreamController<({int total, int errors})> ctrl;
    StreamSubscription<void>? sub;

    Future<void> emit() async {
      if (ctrl.isClosed) return;
      try {
        final total = await countAll();
        final errors = await countWithErrors();
        ctrl.add((total: total, errors: errors));
      } on Object catch (e, st) {
        // Jak w `watchForHousehold` — błąd zamiast wiecznej ciszy.
        if (!ctrl.isClosed) ctrl.addError(e, st);
      }
    }

    ctrl = StreamController<({int total, int errors})>(
      onListen: () {
        sub = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return ctrl.stream;
  }

  /// Tylko dla testów — nie używać w runtime.
  void dispose() {
    _changes.close();
  }
}
