import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/core/offline/pending_transaction.dart';
import 'package:nasz_budzet_domowy/core/offline/sync_providers.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/import_repository.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/recurring_repository.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/recurring_transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction_repository.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository(
    ref.watch(pendingOpsDaoProvider),
    ref.watch(syncWorkerProvider),
  );
});

/// Import wyciągów bankowych (CSV) + reguły kategoryzacji.
final importRepositoryProvider = Provider<ImportRepository>((ref) {
  return const ImportRepository();
});

/// Szablony transakcji cyklicznych (czynsz, abonamenty, wypłata).
final recurringRepositoryProvider = Provider<RecurringRepository>((ref) {
  return const RecurringRepository();
});

/// Lista szablonów cyklicznych gospodarstwa. Po każdej zmianie (dodanie,
/// pauza, usunięcie) ekran robi `ref.invalidate(recurringListProvider)`.
final recurringListProvider =
    FutureProvider<List<RecurringTransaction>>((ref) async {
  final householdId = ref.watch(currentHouseholdIdProvider).value;
  if (householdId == null) return const [];
  return ref.watch(recurringRepositoryProvider).list(householdId);
});

/// Naliczanie zaległych transakcji cyklicznych.
///
/// Obserwowane od startu apki (listenManual w main.dart): przelicza się
/// przy pierwszym załadowaniu gospodarstwa ORAZ po każdym invalidate
/// `currentHouseholdIdProvider` (czyli m.in. przy każdym powrocie apki
/// z tła). Dedup_hash gwarantuje brak dubli między telefonami.
final recurringMaterializerProvider = FutureProvider<void>((ref) async {
  final householdId = ref.watch(currentHouseholdIdProvider).value;
  if (householdId == null) return;
  final inserted =
      await ref.read(recurringRepositoryProvider).materializeDue(householdId);
  if (inserted > 0) {
    // Świeżo naliczone wpisy mają się od razu pojawić na liście.
    ref.invalidate(transactionsProvider);
  }
});

/// Lista transakcji = merge realtime Supabase + lokalna kolejka.
///
/// Po sukcesie sync workera lokalny rekord jest usuwany; w trakcie tej
/// "luki" Supabase już może mieć realtime emit z `client_op_id` —
/// deduplikujemy po `client_op_id` (preferując wersję z Supabase).
final transactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final householdId = ref.watch(currentHouseholdIdProvider).value;
  if (householdId == null) {
    return Stream.value(const <Transaction>[]);
  }

  final remote = ref.watch(transactionRepositoryProvider).watchAll(householdId);
  final pending =
      ref.watch(pendingOpsDaoProvider).watchForHousehold(householdId);

  return mergeRemoteAndPending(remote, pending);
});

/// Merge dwóch źródeł: realtime z Supabase + lokalna kolejka.
///
/// Wynikowa lista zawiera wszystkie rekordy zdalne + te z kolejki które
/// jeszcze nie pojawiły się w realtime (deduplikacja po `client_op_id`).
/// Wystawione jako top-level żeby było testowalne bez ProviderContainer.
Stream<List<Transaction>> mergeRemoteAndPending(
  Stream<List<Transaction>> remote,
  Stream<List<PendingTransaction>> pending,
) {
  late StreamController<List<Transaction>> ctrl;
  StreamSubscription<List<Transaction>>? remoteSub;
  StreamSubscription<List<PendingTransaction>>? pendingSub;

  var lastRemote = const <Transaction>[];
  var lastPending = const <PendingTransaction>[];
  var primed = false;

  void emit() {
    if (!primed) return;
    final remoteOpIds = <String>{
      for (final t in lastRemote)
        if (t.clientOpId != null) t.clientOpId!,
    };
    // Lokalne pendingi, które jeszcze NIE pojawiły się w realtime — reszta
    // jest już w `lastRemote` (i ma `isPending = false`, czyli ☁️).
    final visiblePending = lastPending
        .where((p) => !remoteOpIds.contains(p.clientOpId))
        .map((p) => p.toDisplayTransaction());

    final merged = [...lastRemote, ...visiblePending]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    ctrl.add(merged);
  }

  ctrl = StreamController<List<Transaction>>(
    onListen: () {
      var remoteReady = false;
      var pendingReady = false;

      remoteSub = remote.listen(
        (data) {
          lastRemote = data;
          remoteReady = true;
          if (!primed && pendingReady) primed = true;
          emit();
        },
        onError: ctrl.addError,
      );

      pendingSub = pending.listen(
        (data) {
          lastPending = data;
          pendingReady = true;
          if (!primed && remoteReady) primed = true;
          emit();
        },
        // Awaria lokalnej kolejki (np. uszkodzony plik sqflite) nie może
        // ani wieszać listy (brak `primed`), ani jej ubijać — dane z
        // serwera są ważniejsze niż kolejka. Degradacja: pusta kolejka.
        onError: (Object e, StackTrace st) {
          lastPending = const [];
          pendingReady = true;
          if (!primed && remoteReady) primed = true;
          emit();
        },
      );
    },
    onCancel: () async {
      await remoteSub?.cancel();
      await pendingSub?.cancel();
    },
  );
  return ctrl.stream;
}
