import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Source rekordu — odpowiada typu PG `tx_source`.
enum TransactionSource {
  manual,
  voice,
  csvImport,
  pdfImport,
  recurring;

  String toDbValue() => switch (this) {
        TransactionSource.manual => 'manual',
        TransactionSource.voice => 'voice',
        TransactionSource.csvImport => 'csv_import',
        TransactionSource.pdfImport => 'pdf_import',
        TransactionSource.recurring => 'recurring',
      };

  static TransactionSource fromDbValue(String raw) => switch (raw) {
        'manual' => TransactionSource.manual,
        'voice' => TransactionSource.voice,
        'csv_import' => TransactionSource.csvImport,
        'pdf_import' => TransactionSource.pdfImport,
        'recurring' => TransactionSource.recurring,
        _ => throw ArgumentError('Unknown tx_source: $raw'),
      };
}

/// Income vs expense — odpowiada typu PG `tx_type`.
enum TransactionType {
  income,
  expense;

  String toDbValue() => name;

  bool get isIncome => this == TransactionType.income;
  bool get isExpense => this == TransactionType.expense;

  static TransactionType fromDbValue(String raw) => switch (raw) {
        'income' => TransactionType.income,
        'expense' => TransactionType.expense,
        _ => throw ArgumentError('Unknown tx_type: $raw'),
      };
}

/// Pojedyncza transakcja. Mirror schematu PG `transactions`.
///
/// `amountCents` jest zawsze **dodatnia** — znak determinuje `type`.
/// Trzymanie int (bigint w PG) eliminuje błędy zaokrąglenia floata
/// na operacjach budżetowych.
class Transaction {
  const Transaction({
    required this.id,
    required this.householdId,
    required this.occurredAt,
    required this.amountCents,
    required this.type,
    required this.categoryId,
    required this.source,
    required this.dedupHash,
    required this.createdAt,
    this.createdBy,
    this.description,
    this.note,
    this.importId,
    this.clientOpId,
    this.isPending = false,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      householdId: json['household_id'] as String,
      createdBy: json['created_by'] as String?,
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      amountCents: (json['amount_cents'] as num).toInt(),
      type: TransactionType.fromDbValue(json['type'] as String),
      categoryId: json['category_id'] as String,
      description: json['description'] as String?,
      note: json['note'] as String?,
      source: TransactionSource.fromDbValue(json['source'] as String),
      importId: json['import_id'] as String?,
      dedupHash: json['dedup_hash'] as String,
      clientOpId: json['client_op_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String householdId;
  final String? createdBy;
  final DateTime occurredAt;
  final int amountCents;
  final TransactionType type;
  final String categoryId;
  final String? description;
  final String? note;
  final TransactionSource source;
  final String? importId;
  final String dedupHash;
  final String? clientOpId;
  final DateTime createdAt;

  /// `true` gdy transakcja siedzi w lokalnej kolejce i nie była jeszcze
  /// wepchnięta do Supabase. Tylko dla wyświetlania w UI (⏳ vs ☁️).
  final bool isPending;
}

/// Hashowanie do twardej deduplikacji.
///
/// Wzór z `docs/plan.md`:
/// ```text
/// dedup_hash = sha256( date_iso || amount_cents || normalize(description) )
/// normalize  = lower + strip polish diacritics + collapse whitespace
///              + remove punctuation
/// ```
///
/// Wynik **MUSI** być deterministyczny — ten sam hash dla tej samej
/// transakcji z dowolnego urządzenia (klucz
/// `UNIQUE(household_id, dedup_hash)` w DB to wymusza).
class TransactionHasher {
  const TransactionHasher._();

  /// Zwraca SHA-256 hex (64 znaki). Wynik → `transactions.dedup_hash`.
  static String compute({
    required DateTime occurredAt,
    required int amountCents,
    required String? description,
  }) {
    final dateIso = _dateOnly(occurredAt);
    final normalized = normalize(description ?? '');
    final input = '$dateIso|$amountCents|$normalized';
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  /// Lower-case, strip polskich znaków, zostaw tylko alfanumery + spacje,
  /// collapse whitespace. Stała deterministyczna na różnych platformach.
  static String normalize(String text) {
    const map = {
      'ą': 'a',
      'ć': 'c',
      'ę': 'e',
      'ł': 'l',
      'ń': 'n',
      'ó': 'o',
      'ś': 's',
      'ź': 'z',
      'ż': 'z',
    };
    var s = text.toLowerCase();
    map.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _dateOnly(DateTime dt) {
    // YYYY-MM-DD (UTC date — local time-of-day NIE wpływa na hash).
    final utc = DateTime.utc(dt.year, dt.month, dt.day);
    return utc.toIso8601String().substring(0, 10);
  }
}
