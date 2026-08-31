import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_notifications.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';
import 'package:shared_preferences/shared_preferences.dart';

RawBankNotification _raw({
  String package = 'com.google.android.apps.walletnfcrel',
  int id = 1,
  int? postTimeMs,
  String? title = 'Zapłacono 23,50 zł',
  String? content = 'Biedronka',
}) =>
    RawBankNotification(
      packageName: package,
      id: id,
      postTimeMs:
          postTimeMs ?? DateTime(2026, 8, 25, 14, 30).millisecondsSinceEpoch,
      title: title,
      content: content,
    );

void main() {
  group('seenKeyFor', () {
    test('klucz to pakiet|id|czas — to samo powiadomienie = ten sam klucz', () {
      final a = _raw();
      final b = _raw();
      expect(seenKeyFor(a), seenKeyFor(b));
      expect(seenKeyFor(a), contains('walletnfcrel'));
    });

    test('inne id albo inny czas → inny klucz', () {
      expect(seenKeyFor(_raw(id: 2)), isNot(seenKeyFor(_raw())));
      expect(
        seenKeyFor(_raw(postTimeMs: 111)),
        isNot(seenKeyFor(_raw(postTimeMs: 222))),
      );
    });
  });

  group('suggestionsFromRaw', () {
    test('bierze obsługiwane banki, z godziną z powiadomienia', () {
      final posted = DateTime(2026, 8, 25, 9, 15);
      final out = suggestionsFromRaw(
        [_raw(postTimeMs: posted.millisecondsSinceEpoch)],
        {},
      );
      expect(out, hasLength(1));
      expect(out.single.amountCents, 2350);
      expect(out.single.type, TransactionType.expense);
      expect(out.single.bank, 'Portfel Google');
      // Data wpisu = moment płatności, nie moment wejścia do apki.
      expect(out.single.capturedAt, posted);
    });

    test('pomija apki poza listą banków', () {
      final out = suggestionsFromRaw(
        [_raw(package: 'com.whatsapp', title: 'Ktoś przysłał 50,00 zł')],
        {},
      );
      expect(out, isEmpty);
    });

    test('pomija powiadomienia bez kwoty', () {
      final out = suggestionsFromRaw(
        [_raw(title: 'Zaloguj się do aplikacji', content: 'Nowe urządzenie')],
        {},
      );
      expect(out, isEmpty);
    });

    test(
        'POMIJA już przetworzone — powiadomienie wiszące w panelu nie '
        'wraca przy kolejnym wejściu do apki', () {
      final raw = _raw();
      final first = suggestionsFromRaw([raw], {});
      expect(first, hasLength(1));

      final second = suggestionsFromRaw([raw], {seenKeyFor(raw)});
      expect(second, isEmpty, reason: 'ten sam push = brak duplikatu');
    });

    test('wpływ rozpoznany po słowie kluczowym', () {
      final out = suggestionsFromRaw(
        [
          _raw(
            package: 'pl.ing.mojeing',
            title: 'Przelew przychodzący',
            content: 'Wpłynęło 1 500,00 zł od GMINA',
          ),
        ],
        {},
      );
      expect(out.single.type, TransactionType.income);
      expect(out.single.amountCents, 150000);
      expect(out.single.bank, 'ING');
    });

    test('kilka powiadomień naraz: dwie płatności = dwie propozycje', () {
      final out = suggestionsFromRaw(
        [
          _raw(),
          _raw(
            id: 2,
            package: 'pl.pkobp.iko',
            title: 'Płatność kartą 99,99 zł',
            content: 'Orlen',
          ),
        ],
        {},
      );
      expect(out, hasLength(2));
      expect(out.map((s) => s.amountCents), containsAll([2350, 9999]));
    });
  });

  group('BankSuggestionsNotifier.ingest (trwały dedup przez prefs)', () {
    test('to samo powiadomienie dwa razy → jedna propozycja', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(bankSuggestionsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final notifier = container.read(bankSuggestionsProvider.notifier);
      final raw = _raw();

      expect(await notifier.ingest([raw]), 1);
      expect(container.read(bankSuggestionsProvider), hasLength(1));

      // Drugie zajrzenie do panelu (kolejne wejście do apki).
      expect(await notifier.ingest([raw]), 0);
      expect(container.read(bankSuggestionsProvider), hasLength(1));

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('bank_seen_notifications'),
        contains(seenKeyFor(raw)),
      );
    });

    test(
        'klucz zapisujemy też dla pushy bez kwoty (nie parsujemy '
        'ich w kółko)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(bankSuggestionsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final notifier = container.read(bankSuggestionsProvider.notifier);
      final raw = _raw(title: 'Zaloguj się', content: 'Nowe urządzenie');
      expect(await notifier.ingest([raw]), 0);
      expect(notifier.seenKeys, contains(seenKeyFor(raw)));
    });

    test('powiadomienie z innej apki nie zaśmieca pamięci kluczy', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(bankSuggestionsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final notifier = container.read(bankSuggestionsProvider.notifier);
      final raw = _raw(package: 'com.whatsapp');
      expect(await notifier.ingest([raw]), 0);
      expect(notifier.seenKeys, isEmpty);
    });
  });
}
