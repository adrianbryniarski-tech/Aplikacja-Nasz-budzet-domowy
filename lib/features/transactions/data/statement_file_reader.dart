import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/bank_statement_parser.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/ing_pdf_statement_parser.dart';

/// Jeden plik gotowy do parsowania (już po rozpakowaniu ZIP-ów).
class StatementFile {
  const StatementFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Zbiorczy wynik wczytania wielu plików wyciągów naraz.
class MergedStatements {
  const MergedStatements({
    required this.entries,
    required this.banksLabel,
    required this.parsedFiles,
    required this.skippedNonPln,
    required this.skippedOther,
    required this.skippedInternal,
    required this.crossFileDuplicates,
    required this.duplicateFiles,
    required this.fileErrors,
  });

  /// Wszystkie wpisy, posortowane po dacie (stabilnie).
  final List<StatementEntry> entries;

  /// Np. „ING (PDF)" albo „ING, ING (PDF)" przy mieszance plików.
  final String banksLabel;

  /// Ile plików udało się sparsować.
  final int parsedFiles;

  final int skippedNonPln;
  final int skippedOther;

  /// Przelewy własne (między swoimi kontami) pominięte przez parser PDF.
  final int skippedInternal;

  /// Identyczne transakcje powtórzone w RÓŻNYCH plikach (np. ten sam
  /// wyciąg raz luzem, raz w ZIP-ie) — bierzemy jedną.
  final int crossFileDuplicates;

  /// Pliki o identycznej zawartości (bajt w bajt) — parsujemy raz.
  final int duplicateFiles;

  /// Komunikaty per plik, którego nie udało się przeczytać.
  final List<String> fileErrors;
}

/// Wczytywanie wielu plików wyciągów: CSV, PDF (ING) i ZIP z takimi
/// plikami w środku.
///
/// Typ pliku poznajemy po SYGNATURZE bajtów (%PDF / PK), nie po
/// rozszerzeniu — nazwy plików z banków bywają mylące. Błąd jednego
/// pliku nie przerywa reszty: zbieramy komunikaty per plik, a podgląd
/// dostaje wszystko, co dało się przeczytać.
class StatementFileReader {
  const StatementFileReader._();

  /// Bezpieczniki na ZIP-y: wyciąg to kilkadziesiąt KB, więc pojedynczy
  /// wpis >10 MB albo archiwum z setkami plików to nie wyciągi.
  static const _maxZipEntryBytes = 10 * 1024 * 1024;
  static const _maxZipEntries = 200;

  /// Sygnatura `%PDF`.
  static bool isPdf(List<int> b) =>
      b.length >= 4 &&
      b[0] == 0x25 &&
      b[1] == 0x50 &&
      b[2] == 0x44 &&
      b[3] == 0x46;

  /// Sygnatura `PK\x03\x04`.
  static bool isZip(List<int> b) =>
      b.length >= 4 &&
      b[0] == 0x50 &&
      b[1] == 0x4B &&
      b[2] == 0x03 &&
      b[3] == 0x04;

  /// Rozpakowuje ZIP do listy plików (PDF po sygnaturze, CSV po
  /// rozszerzeniu); plik niebędący ZIP-em wraca 1:1.
  static List<StatementFile> expand(String name, Uint8List bytes) {
    if (!isZip(bytes)) return [StatementFile(name: name, bytes: bytes)];

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw StatementParseException(
        'Nie udało się rozpakować archiwum „$name" — uszkodzony ZIP?',
      );
    }
    final out = <StatementFile>[];
    var entries = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (++entries > _maxZipEntries) break;
      final baseName = f.name.split('/').last;
      // Śmieci z macOS i pliki ukryte.
      if (f.name.contains('__MACOSX') || baseName.startsWith('.')) continue;
      final content = f.content as List<int>;
      if (content.length > _maxZipEntryBytes) continue;
      if (isPdf(content) || baseName.toLowerCase().endsWith('.csv')) {
        out.add(
          StatementFile(
            name: baseName,
            bytes: content is Uint8List ? content : Uint8List.fromList(content),
          ),
        );
      }
    }
    if (out.isEmpty) {
      throw StatementParseException(
        'W archiwum „$name" nie znalazłem żadnych wyciągów (PDF ani CSV).',
      );
    }
    return out;
  }

  /// Pełny przebieg: rozpakowanie ZIP-ów → deduplikacja identycznych
  /// plików → parsowanie każdego → scalenie wpisów.
  ///
  /// Powtórki MIĘDZY plikami (ta sama transakcja w dwóch plikach, np.
  /// wyciąg wrzucony luzem i w ZIP-ie) odpadają tutaj — zapis liczy
  /// identyczne wiersze w paczce jako osobne zakupy, więc nie może ich
  /// dostać podwójnie. Powtórki WEWNĄTRZ jednego pliku zostają: dwa
  /// identyczne zakupy jednego dnia to normalna rzecz.
  static MergedStatements readPicked(List<StatementFile> picked) {
    final files = <StatementFile>[];
    final fileErrors = <String>[];
    for (final p in picked) {
      try {
        files.addAll(expand(p.name, p.bytes));
      } on StatementParseException catch (e) {
        fileErrors.add(e.message);
      }
    }

    // Identyczne pliki (bajt w bajt) parsujemy raz.
    final seenDigests = <String>{};
    var duplicateFiles = 0;
    final unique = <StatementFile>[];
    for (final f in files) {
      if (seenDigests.add(sha256.convert(f.bytes).toString())) {
        unique.add(f);
      } else {
        duplicateFiles++;
      }
    }

    final results = <StatementParseResult>[];
    for (final f in unique) {
      try {
        results.add(
          isPdf(f.bytes)
              ? IngPdfStatementParser.parsePdf(f.bytes)
              : BankStatementParser.parse(f.bytes),
        );
      } on StatementParseException catch (e) {
        fileErrors.add('${f.name}: ${e.message}');
      }
    }

    final merged = <StatementEntry>[];
    final seenMax = <String, int>{};
    var crossFileDuplicates = 0;
    for (final result in results) {
      final local = <String, int>{};
      for (final e in result.entries) {
        final key = _crossFileKey(e);
        final n = (local[key] ?? 0) + 1;
        local[key] = n;
        if (n > (seenMax[key] ?? 0)) {
          merged.add(e);
          seenMax[key] = n;
        } else {
          crossFileDuplicates++;
        }
      }
    }
    // Stabilne sortowanie po dacie (przy remisie: kolejność plików).
    final indexed = merged.asMap().entries.toList()
      ..sort((a, b) {
        final byDate = a.value.occurredAt.compareTo(b.value.occurredAt);
        return byDate != 0 ? byDate : a.key.compareTo(b.key);
      });

    final banks = <String>{for (final r in results) r.bank};
    return MergedStatements(
      entries: [for (final e in indexed) e.value],
      banksLabel: banks.join(', '),
      parsedFiles: results.length,
      skippedNonPln: results.fold(0, (s, r) => s + r.skippedNonPln),
      skippedOther: results.fold(0, (s, r) => s + r.skippedOther),
      skippedInternal: results.fold(0, (s, r) => s + r.skippedInternal),
      crossFileDuplicates: crossFileDuplicates,
      duplicateFiles: duplicateFiles,
      fileErrors: fileErrors,
    );
  }

  /// Klucz powtórki między plikami: dzień + kwota + typ + opis bez
  /// białych znaków (różne parsery różnie sklejają spacje w opisie).
  static String _crossFileKey(StatementEntry e) {
    final d = e.occurredAt;
    final desc = e.description.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return '${d.year}-${d.month}-${d.day}|${e.amountCents}'
        '|${e.type.name}|$desc';
  }
}
