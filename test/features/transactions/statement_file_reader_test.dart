import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/statement_file_reader.dart';

// Jeden wiersz CSV łamany w kodzie na granicy średnika — brak spacji
// między sklejanymi kawałkami jest celowy.
// ignore: missing_whitespace_between_adjacent_strings
const _ingHeader = '"Data transakcji";"Dane kontrahenta";"Tytuł";'
    '"Kwota transakcji (waluta rachunku)";"Waluta"';

/// Minimalny wyciąg ING w CSV (nagłówek „Data transakcji", średniki).
Uint8List _ingCsv(List<String> rows) => Uint8List.fromList(
      utf8.encode(
        ['Lista transakcji;;;;', _ingHeader, ...rows].join('\n'),
      ),
    );

Uint8List _zip(Map<String, Uint8List> files) {
  final archive = Archive();
  files.forEach(
    (name, bytes) => archive.addFile(ArchiveFile(name, bytes.length, bytes)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  const rowA = '2026-03-01;SKLEP A;Zakupy spożywcze;-10,00;PLN';
  const rowB = '2026-03-02;SKLEP B;Buty;-20,00;PLN';
  const rowC = '2026-03-03;PRACODAWCA;Wypłata;3 000,00;PLN';

  group('StatementFileReader.isPdf / isZip', () {
    test('rozpoznaje sygnatury bajtów', () {
      expect(StatementFileReader.isPdf(utf8.encode('%PDF-1.7 x')), isTrue);
      expect(StatementFileReader.isPdf(utf8.encode('CSV;dane')), isFalse);
      expect(StatementFileReader.isZip([0x50, 0x4B, 0x03, 0x04, 0]), isTrue);
      expect(StatementFileReader.isZip(utf8.encode('%PDF')), isFalse);
    });
  });

  group('StatementFileReader.expand', () {
    test('plik niebędący ZIP-em wraca 1:1', () {
      final bytes = _ingCsv([rowA]);
      final out = StatementFileReader.expand('wyciag.csv', bytes);
      expect(out, hasLength(1));
      expect(out.single.name, 'wyciag.csv');
      expect(out.single.bytes, bytes);
    });

    test('ZIP rozpakowuje CSV, pomija śmieci z macOS', () {
      final zip = _zip({
        'wyciagi/marzec.csv': _ingCsv([rowA]),
        '__MACOSX/._marzec.csv': Uint8List.fromList([1, 2, 3]),
        'notatka.txt': Uint8List.fromList(utf8.encode('nie wyciąg')),
      });
      final out = StatementFileReader.expand('paczka.zip', zip);
      expect(out, hasLength(1));
      expect(out.single.name, 'marzec.csv');
    });

    test('ZIP bez wyciągów → czytelny błąd', () {
      final zip = _zip({
        'readme.txt': Uint8List.fromList(utf8.encode('hej')),
      });
      expect(
        () => StatementFileReader.expand('pusta.zip', zip),
        throwsA(isA<Object>()),
      );
    });
  });

  group('StatementFileReader.readPicked', () {
    test('ZIP + luźny plik: scala wpisy i sortuje po dacie', () {
      final merged = StatementFileReader.readPicked([
        StatementFile(
          name: 'paczka.zip',
          bytes: _zip({
            'luty.csv': _ingCsv([rowC]),
            'marzec.csv': _ingCsv([rowB]),
          }),
        ),
        StatementFile(name: 'osobny.csv', bytes: _ingCsv([rowA])),
      ]);
      expect(merged.parsedFiles, 3);
      expect(merged.entries, hasLength(3));
      expect(merged.fileErrors, isEmpty);
      expect(merged.banksLabel, 'ING');
      expect(
        [for (final e in merged.entries) e.occurredAt.day],
        [1, 2, 3], // posortowane datami, nie kolejnością plików
      );
    });

    test('identyczny plik dwa razy → parsujemy raz', () {
      final csv = _ingCsv([rowA, rowB]);
      final merged = StatementFileReader.readPicked([
        StatementFile(name: 'a.csv', bytes: csv),
        StatementFile(name: 'kopia.csv', bytes: csv),
      ]);
      expect(merged.duplicateFiles, 1);
      expect(merged.parsedFiles, 1);
      expect(merged.entries, hasLength(2));
    });

    test(
        'ta sama transakcja w dwóch plikach → jedna (różnice spacji '
        'w opisie nie przeszkadzają)', () {
      final merged = StatementFileReader.readPicked([
        StatementFile(
          name: 'a.csv',
          bytes: _ingCsv(['2026-03-01;SP. Z O.O. X;Zakupy;-10,00;PLN']),
        ),
        StatementFile(
          name: 'b.csv',
          // Inne rozmieszczenie spacji (tak różnią się parsery PDF/CSV).
          bytes: _ingCsv(['2026-03-01;SP . Z O.O. X;Zakupy;-10,00;PLN']),
        ),
      ]);
      expect(merged.entries, hasLength(1));
      expect(merged.crossFileDuplicates, 1);
    });

    test('dwa identyczne zakupy w JEDNYM pliku zostają oba', () {
      final merged = StatementFileReader.readPicked([
        StatementFile(name: 'a.csv', bytes: _ingCsv([rowA, rowA])),
      ]);
      expect(merged.entries, hasLength(2));
      expect(merged.crossFileDuplicates, 0);
    });

    test('błąd jednego pliku nie psuje reszty', () {
      final merged = StatementFileReader.readPicked([
        StatementFile(
          name: 'smieci.bin',
          bytes: Uint8List.fromList(List.filled(16, 7)),
        ),
        StatementFile(
          name: 'zepsuty.zip',
          bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 9, 9, 9]),
        ),
        StatementFile(name: 'dobry.csv', bytes: _ingCsv([rowA])),
      ]);
      expect(merged.entries, hasLength(1));
      expect(merged.fileErrors, hasLength(2));
      expect(merged.fileErrors.join(), contains('smieci.bin'));
      expect(merged.fileErrors.join(), contains('zepsuty.zip'));
    });
  });
}
