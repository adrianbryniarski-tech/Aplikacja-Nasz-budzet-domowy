import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/core/offline/local_db.dart';
import 'package:nasz_budzet_domowy/core/offline/pending_ops_dao.dart';
import 'package:nasz_budzet_domowy/core/offline/pending_transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  late PendingOpsDao dao;

  setUp(() async {
    db = LocalDb(fixedPath: inMemoryDatabasePath);
    dao = PendingOpsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  PendingTransaction makeOp({
    String clientOpId = 'op-1',
    String householdId = 'h-1',
    int amountCents = 1500,
    String? createdBy,
  }) {
    return PendingTransaction(
      clientOpId: clientOpId,
      householdId: householdId,
      createdBy: createdBy,
      occurredAt: DateTime(2026, 5, 17),
      amountCents: amountCents,
      type: TransactionType.expense,
      categoryId: 'cat-1',
      source: TransactionSource.manual,
      dedupHash: 'hash-$clientOpId-$amountCents',
      enqueuedAt: DateTime(2026, 5, 17, 12),
      retryCount: 0,
    );
  }

  test('enqueue + listAll round-trip', () async {
    await dao.enqueue(makeOp());
    final all = await dao.listAll();
    expect(all, hasLength(1));
    expect(all.first.clientOpId, 'op-1');
    expect(all.first.amountCents, 1500);
  });

  test('enqueue tego samego client_op_id — ignored (idempotency)', () async {
    await dao.enqueue(makeOp());
    await dao.enqueue(makeOp(amountCents: 9999));
    final all = await dao.listAll();
    expect(all, hasLength(1));
    // Zachowany pierwszy zapis — drugi został zignorowany.
    expect(all.first.amountCents, 1500);
  });

  test('listForHousehold filtruje po household_id', () async {
    await dao.enqueue(makeOp(clientOpId: 'a'));
    await dao.enqueue(makeOp(clientOpId: 'b', householdId: 'h-2'));
    final h1 = await dao.listForHousehold('h-1');
    expect(h1, hasLength(1));
    expect(h1.first.clientOpId, 'a');
  });

  test('remove kasuje rekord', () async {
    await dao.enqueue(makeOp());
    await dao.remove('op-1');
    expect(await dao.listAll(), isEmpty);
  });

  test('markFailure ustawia error + zwiększa retry_count', () async {
    await dao.enqueue(makeOp());
    await dao.markFailure('op-1', 'network timeout');
    await dao.markFailure('op-1', 'network timeout');
    final all = await dao.listAll();
    expect(all.first.lastError, 'network timeout');
    expect(all.first.retryCount, 2);
  });

  test('countWithErrors zlicza tylko z lastError', () async {
    await dao.enqueue(makeOp(clientOpId: 'a'));
    await dao.enqueue(makeOp(clientOpId: 'b'));
    await dao.markFailure('a', 'boom');
    expect(await dao.countAll(), 2);
    expect(await dao.countWithErrors(), 1);
  });

  test('listForUser filtruje po created_by — nie miesza userów', () async {
    await dao.enqueue(makeOp(clientOpId: 'a', createdBy: 'user-A'));
    await dao.enqueue(makeOp(clientOpId: 'b', createdBy: 'user-B'));
    final forA = await dao.listForUser('user-A');
    final forB = await dao.listForUser('user-B');
    expect(forA, hasLength(1));
    expect(forA.first.clientOpId, 'a');
    expect(forB, hasLength(1));
    expect(forB.first.clientOpId, 'b');
  });

  test('listForUser pomija dead-lettery (retry_count >= maxRetries)', () async {
    await dao.enqueue(makeOp(clientOpId: 'fresh', createdBy: 'u1'));
    await dao.enqueue(makeOp(clientOpId: 'dead', createdBy: 'u1'));
    // Symulujemy maxRetries nieudanych prób dla 'dead'.
    for (var i = 0; i < PendingOpsDao.maxRetries; i++) {
      await dao.markFailure('dead', 'transient');
    }
    final list = await dao.listForUser('u1');
    expect(list, hasLength(1));
    expect(list.first.clientOpId, 'fresh');
    // Dead-letter ZOSTAŁ w bazie (do inspekcji), ale nie idzie do retry.
    expect(await dao.countAll(), 2);
  });

  test('watchForHousehold emituje stan po każdej zmianie', () async {
    // StreamIterator pobiera kolejne emisje czekając aż FAKTYCZNIE nadejdą
    // (zamiast sztywnych `Future.delayed`) — deterministycznie, bez flaky.
    // Każda operacja DAO pinguje stream dokładnie raz, więc emisje i
    // moveNext() są w jednoznacznej relacji 1:1.
    final it = StreamIterator(dao.watchForHousehold('h-1'));

    expect(await it.moveNext(), isTrue);
    expect(it.current, isEmpty); // stan początkowy

    await dao.enqueue(makeOp(clientOpId: 'a'));
    expect(await it.moveNext(), isTrue);
    expect(it.current, hasLength(1));

    await dao.enqueue(makeOp(clientOpId: 'b'));
    expect(await it.moveNext(), isTrue);
    expect(it.current, hasLength(2));

    await dao.remove('a');
    expect(await it.moveNext(), isTrue);
    expect(it.current, hasLength(1));

    await it.cancel();
  });
}
