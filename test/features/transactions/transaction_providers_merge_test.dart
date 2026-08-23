import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/core/offline/pending_transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

void main() {
  group('mergeRemoteAndPending', () {
    Transaction remoteTx({
      required String id,
      required String clientOpId,
      DateTime? occurredAt,
    }) {
      return Transaction(
        id: id,
        householdId: 'h-1',
        occurredAt: occurredAt ?? DateTime(2026, 5, 17),
        amountCents: 1500,
        type: TransactionType.expense,
        categoryId: 'cat-1',
        source: TransactionSource.manual,
        dedupHash: 'hash-$id',
        clientOpId: clientOpId,
        createdAt: DateTime(2026, 5, 17, 12),
      );
    }

    PendingTransaction pendingOp({
      required String clientOpId,
      DateTime? occurredAt,
    }) {
      return PendingTransaction(
        clientOpId: clientOpId,
        householdId: 'h-1',
        occurredAt: occurredAt ?? DateTime(2026, 5, 18),
        amountCents: 2500,
        type: TransactionType.expense,
        categoryId: 'cat-1',
        source: TransactionSource.manual,
        dedupHash: 'hash-$clientOpId',
        enqueuedAt: DateTime(2026, 5, 18, 9),
        retryCount: 0,
      );
    }

    test('pending bez odpowiednika w remote → widoczny jako pending', () async {
      final remoteCtrl = StreamController<List<Transaction>>();
      final pendingCtrl = StreamController<List<PendingTransaction>>();

      final merged = mergeRemoteAndPending(
        remoteCtrl.stream,
        pendingCtrl.stream,
      );
      final events = <List<Transaction>>[];
      final sub = merged.listen(events.add);

      remoteCtrl.add([remoteTx(id: 'r1', clientOpId: 'op-r1')]);
      pendingCtrl.add([pendingOp(clientOpId: 'op-p1')]);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final last = events.last;
      expect(last, hasLength(2));
      // Pending ma późniejszą datę → na początku po sort desc.
      expect(last.first.id, 'op-p1');
      expect(last.first.isPending, isTrue);
      expect(last[1].id, 'r1');
      expect(last[1].isPending, isFalse);

      await sub.cancel();
      await remoteCtrl.close();
      await pendingCtrl.close();
    });

    test('pending już zsynchronizowany (te samo client_op_id) → nie duplikat',
        () async {
      final remoteCtrl = StreamController<List<Transaction>>();
      final pendingCtrl = StreamController<List<PendingTransaction>>();

      final merged = mergeRemoteAndPending(
        remoteCtrl.stream,
        pendingCtrl.stream,
      );
      final events = <List<Transaction>>[];
      final sub = merged.listen(events.add);

      // Race window: Supabase już ma rekord (z client_op_id = 'shared'),
      // a lokalny worker jeszcze nie zdążył usunąć z kolejki.
      remoteCtrl.add([remoteTx(id: 'r1', clientOpId: 'shared')]);
      pendingCtrl.add([pendingOp(clientOpId: 'shared')]);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final last = events.last;
      // Widoczna jedna transakcja — wersja z Supabase (synced).
      expect(last, hasLength(1));
      expect(last.first.id, 'r1');
      expect(last.first.isPending, isFalse);

      await sub.cancel();
      await remoteCtrl.close();
      await pendingCtrl.close();
    });

    test('błąd kolejki lokalnej → lista jedzie na samym remote', () async {
      final remoteCtrl = StreamController<List<Transaction>>();
      final pendingCtrl = StreamController<List<PendingTransaction>>();

      final merged = mergeRemoteAndPending(
        remoteCtrl.stream,
        pendingCtrl.stream,
      );
      final events = <List<Transaction>>[];
      final errors = <Object>[];
      final sub = merged.listen(events.add, onError: errors.add);

      // Uszkodzona lokalna baza: kolejka rzuca zamiast danych. Wcześniej
      // brak onError zabijał merge, a brak `primed` wieszał spinner.
      remoteCtrl.add([remoteTx(id: 'r1', clientOpId: 'op-r1')]);
      pendingCtrl.addError(StateError('sqflite padł'));

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(errors, isEmpty);
      expect(events, hasLength(1));
      expect(events.first.single.id, 'r1');

      await sub.cancel();
      await remoteCtrl.close();
      await pendingCtrl.close();
    });

    test('emit dopiero gdy oba źródła odpowiedzą (avoid blink)', () async {
      final remoteCtrl = StreamController<List<Transaction>>();
      final pendingCtrl = StreamController<List<PendingTransaction>>();

      final merged = mergeRemoteAndPending(
        remoteCtrl.stream,
        pendingCtrl.stream,
      );
      final events = <List<Transaction>>[];
      final sub = merged.listen(events.add);

      remoteCtrl.add([remoteTx(id: 'r1', clientOpId: 'a')]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Pending stream nie odpowiedział → brak emitu.
      expect(events, isEmpty);

      pendingCtrl.add(const <PendingTransaction>[]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events, hasLength(1));
      expect(events.first, hasLength(1));

      await sub.cancel();
      await remoteCtrl.close();
      await pendingCtrl.close();
    });
  });
}
