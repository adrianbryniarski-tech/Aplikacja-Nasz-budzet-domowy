import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/investments/data/investment.dart';
import 'package:nasz_budzet_domowy/features/investments/data/investment_repository.dart';
import 'package:nasz_budzet_domowy/features/investments/data/price_service.dart';

final investmentRepositoryProvider = Provider<InvestmentRepository>((ref) {
  return const InvestmentRepository();
});

final priceServiceProvider = Provider<PriceService>((ref) {
  final svc = PriceService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Pozycje portfela gospodarstwa (realtime).
final investmentsProvider = StreamProvider<List<Investment>>((ref) {
  final householdId = ref.watch(currentHouseholdIdProvider).value;
  if (householdId == null) return Stream.value(const <Investment>[]);
  return ref.watch(investmentRepositoryProvider).watchAll(householdId);
});

/// Realizacje (sprzedaże) pozycji gospodarstwa (realtime).
final investmentSalesProvider = StreamProvider<List<InvestmentSale>>((ref) {
  final householdId = ref.watch(currentHouseholdIdProvider).value;
  if (householdId == null) return Stream.value(const <InvestmentSale>[]);
  return ref.watch(investmentRepositoryProvider).watchSales(householdId);
});

/// Łączny zrealizowany wynik w PLN (suma zysków/strat ze sprzedaży).
final realizedResultProvider = Provider<double>((ref) {
  final sales = ref.watch(investmentSalesProvider).value ?? const [];
  return sales.fold<double>(0, (s, sale) => s + sale.realizedPln);
});

/// Mapa `investmentId → sprzedana ilość` (suma realizacji per pozycja).
Map<String, double> _soldByInvestment(List<InvestmentSale> sales) {
  final out = <String, double>{};
  for (final s in sales) {
    out[s.investmentId] = (out[s.investmentId] ?? 0) + s.quantity;
  }
  return out;
}

/// Snapshoty wartości portfela w czasie (realtime, do wykresu).
final portfolioSnapshotsProvider =
    StreamProvider<List<PortfolioSnapshot>>((ref) {
  final householdId = ref.watch(currentHouseholdIdProvider).value;
  if (householdId == null) {
    return Stream.value(const <PortfolioSnapshot>[]);
  }
  return ref.watch(investmentRepositoryProvider).watchSnapshots(householdId);
});

/// Aktualne kursy dla symboli w portfelu (`symbol → PLN za jednostkę`).
/// FutureProvider — re-fetch przy invalidate (pull-to-refresh / wejście).
/// Zależy od `investmentsProvider` żeby wiedzieć które symbole pobrać.
final pricesProvider = FutureProvider<Map<String, double>>((ref) async {
  final items = ref.watch(investmentsProvider).value ?? const [];
  if (items.isEmpty) return const {};
  final prices = await ref.watch(priceServiceProvider).fetchPrices(items);

  // Po pobraniu kursów — zapisz dzienny snapshot wartości portfela.
  // (best-effort, nie blokuje gdy padnie)
  final householdId = ref.read(currentHouseholdIdProvider).value;
  if (householdId != null && prices.isNotEmpty) {
    // Liczymy tylko część POZOSTAŁĄ (po odjęciu tego co już sprzedane).
    final sold = _soldByInvestment(
      ref.read(investmentSalesProvider).value ?? const [],
    );
    var totalCents = 0;
    for (final inv in items) {
      final remaining = inv.quantity - (sold[inv.id] ?? 0);
      if (remaining <= 0) continue;
      final key =
          inv.assetType == AssetType.crypto ? inv.symbol : _metalKey(inv);
      final price = prices[key];
      final value = price == null
          ? remaining * inv.buyPriceCents / 100
          : remaining * price;
      totalCents += (value * 100).round();
    }
    await ref.read(investmentRepositoryProvider).upsertSnapshot(
          householdId: householdId,
          totalValueCents: totalCents,
        );
  }
  return prices;
});

/// Kiedy ostatnio realnie pobrano kursy z API (nie z cache) — do etykiety
/// „Kursy z HH:MM" pod wartością portfela.
final pricesFetchedAtProvider = Provider<DateTime?>((ref) {
  // Zależność od [pricesProvider] — po każdym fetchu etykieta przelicza
  // się na nowo (sam znacznik nie jest reaktywny).
  ref.watch(pricesProvider);
  return ref.watch(priceServiceProvider).lastFetchAt;
});

/// Pełne odświeżenie zakładki Inwestycje: pozycje, sprzedaże, snapshoty
/// oraz kursy z pominięciem cache TTL. Jedno wejście dla przycisku
/// „Odśwież kursy", pull-to-refresh i retry po błędzie — dzięki temu
/// ręczne odświeżenie potrafi też wskrzesić padnięty strumień realtime.
void refreshInvestments(WidgetRef ref) {
  ref.read(priceServiceProvider).invalidateCache();
  ref
    ..invalidate(investmentsProvider)
    ..invalidate(investmentSalesProvider)
    ..invalidate(portfolioSnapshotsProvider)
    ..invalidate(pricesProvider);
}

/// Wyceny pozycji (Investment + aktualny kurs). Sortowane: zysk malejąco.
final investmentValuationsProvider = Provider<List<InvestmentValuation>>((ref) {
  final items = ref.watch(investmentsProvider).value ?? const [];
  final prices = ref.watch(pricesProvider).value ?? const {};
  final sold = _soldByInvestment(
    ref.watch(investmentSalesProvider).value ?? const [],
  );
  final out = items.map((inv) {
    final key = inv.assetType == AssetType.crypto ? inv.symbol : _metalKey(inv);
    return InvestmentValuation(
      investment: inv,
      pricePln: prices[key],
      soldQuantity: sold[inv.id] ?? 0,
    );
  }).toList()
    ..sort((a, b) => b.currentValuePln.compareTo(a.currentValuePln));
  return out;
});

String _metalKey(Investment inv) =>
    inv.assetType == AssetType.gold ? 'XAU' : 'XAG';
