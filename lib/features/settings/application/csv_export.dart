import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

/// BOM UTF-8 — bez niego Excel wyświetla polskie znaki jako krzaczki.
const _bom = '﻿';

/// Buduje CSV z transakcji — pod Excela po polsku: średniki jako
/// separator, przecinek dziesiętny w kwotach i BOM UTF-8 na starcie.
///
/// Wiersze rosnąco po dacie. Czysta funkcja — testowalna bez Fluttera.
String buildTransactionsCsv(
  List<Transaction> transactions,
  Map<String, Category> categoriesById,
) {
  final buffer = StringBuffer(_bom)
    ..writeln('Data;Typ;Kwota;Kategoria;Opis;Notatka;Źródło');
  final sorted = [...transactions]
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  for (final t in sorted) {
    final amount =
        (t.amountCents / 100).toStringAsFixed(2).replaceAll('.', ',');
    final typeLabel = t.type == TransactionType.income ? 'Dochód' : 'Wydatek';
    buffer.writeln(
      [
        _date(t.occurredAt),
        typeLabel,
        amount,
        _cell(categoriesById[t.categoryId]?.name ?? ''),
        _cell(t.description ?? ''),
        _cell(t.note ?? ''),
        _sourceLabel(t.source),
      ].join(';'),
    );
  }
  return buffer.toString();
}

String _date(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// Cytowanie pola CSV, gdy zawiera separator, cudzysłów albo nową linię.
String _cell(String value) {
  if (value.contains(';') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _sourceLabel(TransactionSource source) => switch (source) {
      TransactionSource.manual => 'ręcznie',
      TransactionSource.voice => 'głosem',
      TransactionSource.csvImport => 'import z banku',
      TransactionSource.pdfImport => 'import PDF',
      TransactionSource.recurring => 'cykliczna',
    };
