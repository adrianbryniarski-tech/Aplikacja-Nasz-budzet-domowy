import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nasz_budzet_domowy/features/investments/data/investment.dart';
import 'package:nasz_budzet_domowy/features/investments/data/price_service.dart';

void main() {
  Investment crypto(String symbol) {
    return Investment.fromJson({
      'id': 'i-$symbol',
      'household_id': 'h1',
      'created_by': 'u1',
      'asset_type': 'crypto',
      'symbol': symbol,
      'display_name': symbol,
      'quantity': 1.0,
      'buy_price_cents': 100000,
      'created_at': '2025-03-10T12:00:00Z',
    });
  }

  /// Fake CoinGecko: odpowiada ceną `1000 + indeks` dla każdego żądanego
  /// id i zlicza requesty (do asercji na cache).
  MockClient coinGecko(List<String> knownIds, void Function() onCall) {
    return MockClient((request) async {
      onCall();
      final ids = (request.url.queryParameters['ids'] ?? '').split(',');
      final body = [
        for (final id in ids)
          if (knownIds.contains(id))
            {'id': id, 'current_price': 1000 + knownIds.indexOf(id)},
      ];
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  group('PriceService cache', () {
    test('drugi fetch w oknie TTL z tym samym zestawem → bez requestu',
        () async {
      var calls = 0;
      final svc = PriceService(
        client: coinGecko(['bitcoin'], () => calls++),
      );

      final first = await svc.fetchPrices([crypto('bitcoin')]);
      final second = await svc.fetchPrices([crypto('bitcoin')]);

      expect(first['bitcoin'], 1000);
      expect(second['bitcoin'], 1000);
      expect(calls, 1, reason: 'drugi fetch powinien iść z cache');
    });

    test('nowe aktywo w oknie TTL → jednak pyta API (pokrycie symboli)',
        () async {
      var calls = 0;
      final svc = PriceService(
        client: coinGecko(['bitcoin', 'ethereum'], () => calls++),
      );

      await svc.fetchPrices([crypto('bitcoin')]);
      final second = await svc.fetchPrices([
        crypto('bitcoin'),
        crypto('ethereum'),
      ]);

      expect(calls, 2, reason: 'cache nie pokrywa ethereum → nowy request');
      expect(
        second['ethereum'],
        1001,
        reason: 'świeżo dodane aktywo od razu ma kurs',
      );
    });

    test('invalidateCache() wymusza request mimo świeżego TTL', () async {
      var calls = 0;
      final svc = PriceService(
        client: coinGecko(['bitcoin'], () => calls++),
      );

      await svc.fetchPrices([crypto('bitcoin')]);
      svc.invalidateCache();
      await svc.fetchPrices([crypto('bitcoin')]);

      expect(calls, 2, reason: '„Odśwież kursy" nie może być no-opem');
    });

    test('lastFetchAt ustawiane po realnym pobraniu', () async {
      final svc = PriceService(client: coinGecko(['bitcoin'], () {}));
      expect(svc.lastFetchAt, isNull);

      await svc.fetchPrices([crypto('bitcoin')]);

      expect(svc.lastFetchAt, isNotNull);
    });
  });
}
