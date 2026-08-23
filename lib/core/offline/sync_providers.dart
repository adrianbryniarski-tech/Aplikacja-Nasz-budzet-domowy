import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/core/offline/local_db.dart';
import 'package:nasz_budzet_domowy/core/offline/pending_ops_dao.dart';
import 'package:nasz_budzet_domowy/core/offline/pending_transaction.dart';
import 'package:nasz_budzet_domowy/core/offline/sync_worker.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';

final localDbProvider = Provider<LocalDb>((ref) => LocalDb.instance);

final pendingOpsDaoProvider = Provider<PendingOpsDao>((ref) {
  return PendingOpsDao(ref.watch(localDbProvider));
});

/// Singleton workera. `keepAlive` żeby nie disposował przy braku
/// subskrybentów — worker ma żyć przez cały czas pracy apki.
final syncWorkerProvider = Provider<SyncWorker>((ref) {
  final worker = SyncWorker(ref.watch(pendingOpsDaoProvider));
  ref.onDispose(worker.dispose);
  return worker;
});

/// Lista pendingów dla bieżącego gospodarstwa.
final pendingTransactionsProvider =
    StreamProvider<List<PendingTransaction>>((ref) {
  final householdId = ref.watch(currentHouseholdIdProvider).value;
  if (householdId == null) {
    return Stream.value(const <PendingTransaction>[]);
  }
  return ref.watch(pendingOpsDaoProvider).watchForHousehold(householdId);
});

/// Globalny licznik (suma + liczba błędów) — używany przez status icon.
final pendingCountsProvider = StreamProvider<({int total, int errors})>((ref) {
  return ref.watch(pendingOpsDaoProvider).watchCounts();
});
