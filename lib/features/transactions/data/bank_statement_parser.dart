import 'dart:convert';

import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

/// Jedna pozycja sparsowana z wyciągu bankowego (przed kategoryzacją).
class StatementEntry {
  const StatementEntry({
    required this.occurredAt,
    required this.amountCents,
    required this.type,
    required this.description,
    this.source = TransactionSource.csvImport,
  });

  final DateTime occurredAt;

  /// Zawsze dodatnie — kierunek niesie [type].
  final int amountCents;
  final TransactionType type;
  final String description;

  /// Skąd wpis pochodzi — CSV vs PDF (widoczne potem w eksporcie CSV).
  final TransactionSource source;
}

/// Wynik parsowania całego pliku wyciągu.
class StatementParseResult {
  const StatementParseResult({
    required this.bank,
    required this.entries,
    this.skippedNonPln = 0,
    this.skippedOther = 0,
    this.skippedInternal = 0,
  });

  /// Wykryty bank — do pokazania w podglądzie („Wykryto: ING").
  final String bank;
  final List<StatementEntry> entries;

  /// Wiersze pominięte przez walutę inną niż PLN (np. EUR na Revolut).
  final int skippedNonPln;

  /// Wiersze pominięte z innych powodów (blokady, transakcje w toku,
  /// zerowe kwoty, nieparsowalne daty).
  final int skippedOther;

  /// Przelewy między własnymi kontami („Przelew własny" w PDF z ING) —
  /// pominięte, bo zawyżyłyby i dochody, i wydatki.
  final int skippedInternal;
}

/// Błąd parsowania z komunikatem po polsku — leci prosto do UI.
class StatementParseException implements Exception {
  const StatementParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parser wyciągów CSV: PKO BP (iPKO), ING (Moje ING), Revolut.
///
/// Formaty różnią się wszystkim: kodowaniem (PKO/ING → windows-1250,
/// Revolut → UTF-8), separatorem (PKO/Revolut → przecinek, ING → średnik),
/// przecinkiem vs kropką w kwotach i preambułą (ING ma metadane przed
/// tabelą). Bank wykrywamy po nagłówku kolumn, a kolumny mapujemy po
/// NAZWACH (nie pozycjach) — eksporty banków potrafią się przesuwać.
class BankStatementParser {
  const BankStatementParser._();

  static StatementParseResult parse(List<int> bytes) {
    final text = decodeBytes(bytes);

    // Revolut: nagłówek w pierwszej niepustej linii, po angielsku.
    final firstLine = text
        .split(RegExp(r'\r?\n'))
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (firstLine.contains('Type') &&
        firstLine.contains('Completed Date') &&
        firstLine.contains('Amount')) {
      return _parseRevolut(text);
    }
    // ING: tabela zaczyna się od "Data transakcji", separator ';'.
    if (text.contains('Data transakcji') && text.contains(';')) {
      return _parseIng(text);
    }
    // PKO BP (iPKO): nagłówek z "Data operacji", separator ','.
    if (text.contains('Data operacji')) {
      return _parsePko(text);
    }
    throw const StatementParseException(
      'Nie rozpoznano formatu pliku. Obsługiwane wyciągi CSV: '
      'PKO BP (iPKO), ING (Moje ING) i Revolut.',
    );
  }

  // ------------------------------------------------------------------
  // PKO BP (iPKO): CSV przecinkowy, windows-1250, kwoty z kropką,
  // opis rozbity na kilka kolumn z etykietami ("Tytuł: ...").
  // ------------------------------------------------------------------
  static StatementParseResult _parsePko(String text) {
    final rows = parseCsv(text, ',');
    final headerIdx = rows.indexWhere(
      (r) => r.any((c) => c.toLowerCase().contains('data operacji')),
    );
    if (headerIdx < 0) {
      throw const StatementParseException(
        'Plik wygląda na PKO BP, ale brakuje nagłówka „Data operacji".',
      );
    }
    final header = rows[headerIdx].map((c) => c.toLowerCase().trim()).toList();
    final dateIdx = header.indexWhere((c) => c.contains('data operacji'));
    final amountIdx = header.indexWhere((c) => c == 'kwota');
    final currencyIdx = header.indexWhere((c) => c == 'waluta');
    final descIdx = header.indexWhere((c) => c.contains('opis transakcji'));
    if (dateIdx < 0 || amountIdx < 0) {
      throw const StatementParseException(
        'Wyciąg PKO BP bez kolumn „Data operacji"/„Kwota" — '
        'wyeksportuj ponownie jako CSV.',
      );
    }

    final entries = <StatementEntry>[];
    var skippedNonPln = 0;
    var skippedOther = 0;
    for (final row in rows.skip(headerIdx + 1)) {
      if (row.every((c) => c.trim().isEmpty)) continue;
      final date = parseDate(_cell(row, dateIdx));
      final amount = parseAmountCents(_cell(row, amountIdx));
      if (date == null || amount == null || amount == 0) {
        skippedOther++;
        continue;
      }
      final currency = _cell(row, currencyIdx).trim().toUpperCase();
      if (currency.isNotEmpty && currency != 'PLN') {
        skippedNonPln++;
        continue;
      }
      // Opis: kolumna "Opis transakcji" + wszystkie kolumny za nią
      // (iPKO dokleja nienazwane kolumny z tytułem/lokalizacją).
      final descStart = descIdx >= 0 ? descIdx : amountIdx + 1;
      final description = cleanPkoDescription(
        row.skip(descStart).join(' '),
      );
      entries.add(
        StatementEntry(
          occurredAt: date,
          amountCents: amount.abs(),
          type: amount < 0 ? TransactionType.expense : TransactionType.income,
          description: description,
        ),
      );
    }
    return StatementParseResult(
      bank: 'PKO BP',
      entries: entries,
      skippedNonPln: skippedNonPln,
      skippedOther: skippedOther,
    );
  }

  /// Usuwa etykiety iPKO ("Tytuł:", "Lokalizacja:", …) i skleja resztę.
  static String cleanPkoDescription(String raw) {
    var s = raw;
    for (final label in const [
      'Tytuł:',
      'Tytul:',
      'Lokalizacja:',
      'Nazwa odbiorcy:',
      'Nazwa nadawcy:',
      'Rachunek odbiorcy:',
      'Rachunek nadawcy:',
      'Adres:',
      'Miasto:',
      'Kraj:',
      'Data i czas operacji:',
      'Oryginalna kwota operacji:',
      'Numer karty:',
      'Numer telefonu:',
      'Referencja własna zleceniodawcy:',
    ]) {
      s = s.replaceAll(label, ' ');
    }
    return _collapse(s);
  }

  // ------------------------------------------------------------------
  // ING (Moje ING): średniki, windows-1250, preambuła z metadanymi
  // przed tabelą, kwoty z przecinkiem. Puste kwoty = blokady (pomijamy —
  // zaksięgują się później i wtedy wejdą przy kolejnym imporcie).
  // ------------------------------------------------------------------
  static StatementParseResult _parseIng(String text) {
    final rows = parseCsv(text, ';');
    final headerIdx = rows.indexWhere(
      (r) => r.any((c) => c.toLowerCase().contains('data transakcji')),
    );
    if (headerIdx < 0) {
      throw const StatementParseException(
        'Plik wygląda na ING, ale brakuje nagłówka „Data transakcji".',
      );
    }
    final header = rows[headerIdx].map((c) => c.toLowerCase().trim()).toList();
    final dateIdx = header.indexWhere((c) => c.contains('data transakcji'));
    final amountIdx =
        header.indexWhere((c) => c.startsWith('kwota transakcji'));
    final counterpartyIdx = header.indexWhere((c) => c.contains('kontrahenta'));
    final titleIdx = header.indexWhere((c) => c == 'tytuł' || c == 'tytul');
    // Waluta rachunku to pierwsza kolumna "waluta" ZA kolumną kwoty.
    var currencyIdx = -1;
    for (var i = amountIdx + 1; i >= 0 && i < header.length; i++) {
      if (header[i] == 'waluta') {
        currencyIdx = i;
        break;
      }
    }
    if (dateIdx < 0 || amountIdx < 0) {
      throw const StatementParseException(
        'Wyciąg ING bez kolumn „Data transakcji"/„Kwota transakcji" — '
        'wyeksportuj ponownie jako CSV.',
      );
    }

    final entries = <StatementEntry>[];
    var skippedNonPln = 0;
    var skippedOther = 0;
    for (final row in rows.skip(headerIdx + 1)) {
      if (row.every((c) => c.trim().isEmpty)) continue;
      final date = parseDate(_cell(row, dateIdx));
      final amount = parseAmountCents(_cell(row, amountIdx));
      if (date == null || amount == null || amount == 0) {
        skippedOther++; // m.in. blokady z pustą kwotą transakcji
        continue;
      }
      final currency = _cell(row, currencyIdx).trim().toUpperCase();
      if (currency.isNotEmpty && currency != 'PLN') {
        skippedNonPln++;
        continue;
      }
      final description = _collapse(
        '${_cell(row, counterpartyIdx)} ${_cell(row, titleIdx)}',
      );
      entries.add(
        StatementEntry(
          occurredAt: date,
          amountCents: amount.abs(),
          type: amount < 0 ? TransactionType.expense : TransactionType.income,
          description: description,
        ),
      );
    }
    return StatementParseResult(
      bank: 'ING',
      entries: entries,
      skippedNonPln: skippedNonPln,
      skippedOther: skippedOther,
    );
  }

  // ------------------------------------------------------------------
  // Revolut: UTF-8, przecinki, angielski nagłówek. Importujemy tylko
  // COMPLETED w PLN; prowizję (Fee) doliczamy do wydatku, bo "Amount"
  // jej nie zawiera.
  // ------------------------------------------------------------------
  static StatementParseResult _parseRevolut(String text) {
    final rows = parseCsv(text, ',');
    final header = rows.first.map((c) => c.toLowerCase().trim()).toList();
    final completedIdx = header.indexOf('completed date');
    final startedIdx = header.indexOf('started date');
    final descIdx = header.indexOf('description');
    final amountIdx = header.indexOf('amount');
    final feeIdx = header.indexOf('fee');
    final currencyIdx = header.indexOf('currency');
    final stateIdx = header.indexOf('state');
    if (amountIdx < 0 || (completedIdx < 0 && startedIdx < 0)) {
      throw const StatementParseException(
        'Wyciąg Revolut bez kolumn „Amount"/„Completed Date" — '
        'wyeksportuj ponownie jako CSV (Excel).',
      );
    }

    final entries = <StatementEntry>[];
    var skippedNonPln = 0;
    var skippedOther = 0;
    for (final row in rows.skip(1)) {
      if (row.every((c) => c.trim().isEmpty)) continue;
      final state = _cell(row, stateIdx).trim().toUpperCase();
      if (state.isNotEmpty && state != 'COMPLETED') {
        skippedOther++;
        continue;
      }
      final currency = _cell(row, currencyIdx).trim().toUpperCase();
      if (currency.isNotEmpty && currency != 'PLN') {
        skippedNonPln++;
        continue;
      }
      final rawDate = _cell(row, completedIdx).trim().isNotEmpty
          ? _cell(row, completedIdx)
          : _cell(row, startedIdx);
      final date = parseDate(rawDate);
      final amount = parseAmountCents(_cell(row, amountIdx));
      final fee = parseAmountCents(_cell(row, feeIdx)) ?? 0;
      if (date == null || amount == null || amount == 0) {
        skippedOther++;
        continue;
      }
      final isExpense = amount < 0;
      // Fee jest zawsze kosztem — powiększa wydatek, pomniejsza wpływ.
      final cents =
          isExpense ? amount.abs() + fee.abs() : amount.abs() - fee.abs();
      if (cents <= 0) {
        skippedOther++;
        continue;
      }
      entries.add(
        StatementEntry(
          occurredAt: date,
          amountCents: cents,
          type: isExpense ? TransactionType.expense : TransactionType.income,
          description: _collapse(_cell(row, descIdx)),
        ),
      );
    }
    return StatementParseResult(
      bank: 'Revolut',
      entries: entries,
      skippedNonPln: skippedNonPln,
      skippedOther: skippedOther,
    );
  }

  // ------------------------------------------------------------------
  // Narzędzia wspólne (publiczne w obrębie pliku — testowane wprost).
  // ------------------------------------------------------------------

  /// UTF-8 z fallbackiem na windows-1250 (PKO/ING tak eksportują).
  static String decodeBytes(List<int> bytes) {
    // Zdejmij BOM UTF-8 jeśli jest.
    var b = bytes;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      b = b.sublist(3);
    }
    try {
      return utf8.decode(b);
    } on FormatException {
      return decodeCp1250(b);
    }
  }

  /// Minimalny dekoder windows-1250 — mapujemy polskie znaki, reszta
  /// stron kodowych jest nam obojętna (kwoty/daty to ASCII).
  static String decodeCp1250(List<int> bytes) {
    const map = <int, String>{
      0x8C: 'Ś',
      0x8F: 'Ź',
      0x9C: 'ś',
      0x9F: 'ź',
      0xA3: 'Ł',
      0xA5: 'Ą',
      0xAF: 'Ż',
      0xB3: 'ł',
      0xB9: 'ą',
      0xBF: 'ż',
      0xC6: 'Ć',
      0xCA: 'Ę',
      0xD1: 'Ń',
      0xD3: 'Ó',
      0xE6: 'ć',
      0xEA: 'ę',
      0xF1: 'ń',
      0xF3: 'ó',
      0xA0: ' ',
    };
    final sb = StringBuffer();
    for (final byte in bytes) {
      if (byte < 0x80) {
        sb.writeCharCode(byte);
      } else {
        sb.write(map[byte] ?? '');
      }
    }
    return sb.toString();
  }

  /// CSV z obsługą cudzysłowów (`"a,b"`, `""` jako escape) i nowych
  /// linii wewnątrz pól. Zwraca wiersze komórek.
  static List<List<String>> parseCsv(String text, String separator) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == separator) {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  /// Kwota → grosze (zachowuje znak). Akceptuje `-23,50`, `+23.50`,
  /// `1 234,56` (spacje i twarde spacje jako separatory tysięcy).
  static int? parseAmountCents(String raw) {
    var s = raw.trim().replaceAll(' ', '').replaceAll(' ', '');
    if (s.isEmpty) return null;
    s = s.replaceAll(',', '.');
    final value = double.tryParse(s);
    if (value == null) return null;
    return (value * 100).round();
  }

  /// Data: `YYYY-MM-DD`, `DD.MM.YYYY`, `DD-MM-YYYY`, także z godziną
  /// za spacją (Revolut: `2026-08-21 14:03:11`).
  static DateTime? parseDate(String raw) {
    final s = raw.trim().split(' ').first;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (iso != null) {
      return DateTime(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final pl = RegExp(r'^(\d{2})[.-](\d{2})[.-](\d{4})$').firstMatch(s);
    if (pl != null) {
      return DateTime(
        int.parse(pl.group(3)!),
        int.parse(pl.group(2)!),
        int.parse(pl.group(1)!),
      );
    }
    return null;
  }

  static String _cell(List<String> row, int idx) =>
      idx >= 0 && idx < row.length ? row[idx] : '';

  static String _collapse(String s) {
    final out = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out.length > 140 ? out.substring(0, 140) : out;
  }
}
