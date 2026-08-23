import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/core/supabase/supabase_client.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/statement_categorizer.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/bank_statement_parser.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Wynik zapisu importu.
sealed class ImportSaveResult {
  const ImportSaveResult();
}

class ImportSaveSuccess extends ImportSaveResult {
  const ImportSaveSuccess({required this.inserted, required this.duplicates});

  /// Ile wierszy faktycznie trafiło do bazy.
  final int inserted;

  /// Ile pominięto, bo już były w bazie (dedup po hashu).
  final int duplicates;
}

class ImportSaveFailure extends ImportSaveResult {
  const ImportSaveFailure(this.message);

  final String message;
}

/// Zapis importu wyciągu + reguły kategoryzacji (`merchant_rules`).
class ImportRepository {
  const ImportRepository();

  /// Timeout dłuższy niż przy pojedynczym zapisie — wyciąg to setki
  /// wierszy w jednym request-cie.
  static const _bulkTimeout = Duration(seconds: 30);

  Future<List<MerchantRule>> merchantRules(String householdId) async {
    final rows = await supabase
        .from('merchant_rules')
        .select('pattern, category_id')
        .eq('household_id', householdId)
        .timeout(kSupabaseWriteTimeout);
    return rows.map(MerchantRule.fromJson).toList();
  }

  /// Zapamiętuje poprawkę usera: wzorzec → kategoria. Nadpisuje istniejącą
  /// regułę dla tego samego wzorca (upsert po (household_id, pattern)).
  Future<void> upsertMerchantRule({
    required String householdId,
    required String pattern,
    required String categoryId,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null || pattern.length < 2) return;
    try {
      await supabase.from('merchant_rules').upsert(
        {
          'household_id': householdId,
          'pattern': pattern,
          'category_id': categoryId,
          'created_by': user.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'household_id,pattern',
      ).timeout(kSupabaseWriteTimeout);
    } on Object {
      // Reguła to bonus (usprawnia NASTĘPNY import) — jej błąd nie może
      // psuć zapisu transakcji, który już się powiódł.
    }
  }

  /// Zapisuje zaznaczone wiersze importu jedną paczką.
  ///
  /// Duplikaty pomijane po stronie bazy: upsert z `ignoreDuplicates` na
  /// UNIQUE (household_id, dedup_hash) — dzięki temu ponowny import tego
  /// samego pliku (albo nakładających się okresów) niczego nie dubluje.
  /// Identyczne wiersze WEWNĄTRZ pliku (dwa te same zakupy jednego dnia)
  /// dostają do hasha przyrostek "#2", "#3"… — kolejność parsowania jest
  /// deterministyczna, więc re-import dalej trafia w te same hashe.
  Future<ImportSaveResult> saveEntries({
    required String householdId,
    required List<({StatementEntry entry, String categoryId})> rows,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return const ImportSaveFailure('Brak sesji — zaloguj się.');
    }
    if (rows.isEmpty) {
      return const ImportSaveSuccess(inserted: 0, duplicates: 0);
    }

    const uuid = Uuid();
    final seenHashes = <String, int>{};
    final inserts = <Map<String, Object?>>[];
    for (final row in rows) {
      final e = row.entry;
      final baseDescription = e.description.isEmpty ? null : e.description;
      var hashDescription = baseDescription;
      final baseHash = TransactionHasher.compute(
        occurredAt: e.occurredAt,
        amountCents: e.amountCents,
        description: baseDescription,
      );
      final occurrence = (seenHashes[baseHash] ?? 0) + 1;
      seenHashes[baseHash] = occurrence;
      if (occurrence > 1) {
        hashDescription = '${baseDescription ?? ''} #$occurrence';
      }
      inserts.add({
        'household_id': householdId,
        'created_by': user.id,
        'occurred_at': _dateOnly(e.occurredAt),
        'amount_cents': e.amountCents,
        'type': e.type.toDbValue(),
        'category_id': row.categoryId,
        'description': baseDescription,
        'note': null,
        'source': TransactionSource.csvImport.toDbValue(),
        'dedup_hash': occurrence == 1
            ? baseHash
            : TransactionHasher.compute(
                occurredAt: e.occurredAt,
                amountCents: e.amountCents,
                description: hashDescription,
              ),
        'client_op_id': uuid.v4(),
      });
    }

    try {
      final insertedRows = await supabase
          .from('transactions')
          .upsert(
            inserts,
            onConflict: 'household_id,dedup_hash',
            ignoreDuplicates: true,
          )
          .select('id')
          .timeout(_bulkTimeout);
      final inserted = insertedRows.length;
      return ImportSaveSuccess(
        inserted: inserted,
        duplicates: inserts.length - inserted,
      );
    } on PostgrestException catch (e) {
      return ImportSaveFailure('${e.code ?? "?"} ${e.message}');
    } on Object catch (e) {
      return ImportSaveFailure(humanizeError(e));
    }
  }

  static String _dateOnly(DateTime dt) {
    final utc = DateTime.utc(dt.year, dt.month, dt.day);
    return utc.toIso8601String().substring(0, 10);
  }
}
