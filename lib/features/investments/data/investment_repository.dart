import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/core/supabase/supabase_client.dart';
import 'package:nasz_budzet_domowy/features/investments/data/investment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

sealed class InvestmentWriteResult {
  const InvestmentWriteResult();
}

class InvestmentWriteSuccess extends InvestmentWriteResult {
  const InvestmentWriteSuccess();
}

class InvestmentWriteFailure extends InvestmentWriteResult {
  const InvestmentWriteFailure(this.message);
  final String message;
}

class InvestmentRepository {
  const InvestmentRepository();

  Stream<List<Investment>> watchAll(String householdId) {
    return supabase
        .from('investments')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .order('created_at')
        .map((rows) => rows.map(Investment.fromJson).toList());
  }

  /// Dodaje pozycję. Jeśli to samo aktywo (asset_type + symbol) już jest w
  /// portfelu — scala: nowa ilość = suma, nowa cena = średnia ważona w PLN,
  /// data zakupu = wcześniejsza z dwóch. Dzięki temu kilka dokupień jednego
  /// coina/metalu to jedna pozycja z uśrednioną ceną.
  Future<InvestmentWriteResult> insert(Investment inv) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return const InvestmentWriteFailure('Brak sesji — zaloguj się.');
    }
    try {
      final existingRow = await supabase
          .from('investments')
          .select()
          .eq('household_id', inv.householdId)
          .eq('asset_type', inv.assetType.toDbValue())
          .eq('symbol', inv.symbol)
          .maybeSingle()
          .timeout(kSupabaseWriteTimeout);

      if (existingRow != null) {
        final ex = Investment.fromJson(existingRow);
        final totalQty = ex.quantity + inv.quantity;
        final avgCents = totalQty == 0
            ? inv.buyPriceCents
            : ((ex.quantity * ex.buyPriceCents +
                        inv.quantity * inv.buyPriceCents) /
                    totalQty)
                .round();
        final earliest = inv.purchasedAt.isBefore(ex.purchasedAt)
            ? inv.purchasedAt
            : ex.purchasedAt;
        await supabase
            .from('investments')
            .update({
              'quantity': totalQty,
              'buy_price_cents': avgCents,
              'purchased_at': investmentDateOnly(earliest),
              // Uzupełnij ticker jeśli stary wiersz go nie miał.
              if (ex.ticker == null && inv.ticker != null) 'ticker': inv.ticker,
            })
            .eq('id', ex.id)
            .timeout(kSupabaseWriteTimeout);
        return const InvestmentWriteSuccess();
      }

      await supabase
          .from('investments')
          .insert(inv.toInsert(user.id))
          .timeout(kSupabaseWriteTimeout);
      return const InvestmentWriteSuccess();
    } on PostgrestException catch (e) {
      return InvestmentWriteFailure('${e.code ?? "?"} ${e.message}');
    } on Object catch (e) {
      // Timeout / brak sieci — po ludzku, zamiast nieobsłużonego wyjątku,
      // który zostawiał przycisk „Zapisz" kręcący się bez końca.
      return InvestmentWriteFailure(humanizeError(e));
    }
  }

  Future<InvestmentWriteResult> update({
    required String id,
    required double quantity,
    required int buyPriceCents,
  }) async {
    try {
      await supabase
          .from('investments')
          .update({
            'quantity': quantity,
            'buy_price_cents': buyPriceCents,
          })
          .eq('id', id)
          .timeout(kSupabaseWriteTimeout);
      return const InvestmentWriteSuccess();
    } on PostgrestException catch (e) {
      return InvestmentWriteFailure('${e.code ?? "?"} ${e.message}');
    } on Object catch (e) {
      // Timeout / brak sieci — po ludzku, zamiast nieobsłużonego wyjątku,
      // który zostawiał przycisk „Zapisz" kręcący się bez końca.
      return InvestmentWriteFailure(humanizeError(e));
    }
  }

  Future<InvestmentWriteResult> delete(String id) async {
    try {
      await supabase
          .from('investments')
          .delete()
          .eq('id', id)
          .timeout(kSupabaseWriteTimeout);
      return const InvestmentWriteSuccess();
    } on PostgrestException catch (e) {
      return InvestmentWriteFailure(e.message);
    } on Object catch (e) {
      return InvestmentWriteFailure(humanizeError(e));
    }
  }

  /// Strumień realizacji (sprzedaży) gospodarstwa (realtime).
  Stream<List<InvestmentSale>> watchSales(String householdId) {
    return supabase
        .from('investment_sales')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .order('sold_at')
        .map((rows) => rows.map(InvestmentSale.fromJson).toList());
  }

  /// Zapisuje sprzedaż (całości lub części) pozycji [investment].
  ///
  /// `quantity`      — ile jednostek sprzedano.
  /// `proceedsCents` — ile odzyskano łącznie w PLN (przy całkowitej
  ///                   stracie = 0).
  /// `soldAt`        — data sprzedaży.
  /// Koszt zakupu sprzedanej części liczymy tu (snapshot), żeby wynik nie
  /// zmienił się gdy później zmieni się średnia cena zakupu pozycji.
  Future<InvestmentWriteResult> recordSale({
    required Investment investment,
    required double quantity,
    required int proceedsCents,
    required DateTime soldAt,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return const InvestmentWriteFailure('Brak sesji — zaloguj się.');
    }
    try {
      final costBasisCents = (quantity * investment.buyPriceCents).round();
      await supabase.from('investment_sales').insert({
        'household_id': investment.householdId,
        'investment_id': investment.id,
        'created_by': user.id,
        'quantity': quantity,
        'proceeds_cents': proceedsCents,
        'cost_basis_cents': costBasisCents,
        'sold_at': investmentDateOnly(soldAt),
      }).timeout(kSupabaseWriteTimeout);
      return const InvestmentWriteSuccess();
    } on PostgrestException catch (e) {
      return InvestmentWriteFailure('${e.code ?? "?"} ${e.message}');
    } on Object catch (e) {
      // Timeout / brak sieci — po ludzku, zamiast nieobsłużonego wyjątku,
      // który zostawiał przycisk „Zapisz" kręcący się bez końca.
      return InvestmentWriteFailure(humanizeError(e));
    }
  }

  /// Cofa zapisaną sprzedaż (przywraca sprzedaną ilość do pozycji).
  Future<InvestmentWriteResult> deleteSale(String id) async {
    try {
      await supabase
          .from('investment_sales')
          .delete()
          .eq('id', id)
          .timeout(kSupabaseWriteTimeout);
      return const InvestmentWriteSuccess();
    } on PostgrestException catch (e) {
      return InvestmentWriteFailure(e.message);
    } on Object catch (e) {
      return InvestmentWriteFailure(humanizeError(e));
    }
  }

  /// Strumień dziennych snapshotów wartości portfela (do wykresu).
  Stream<List<PortfolioSnapshot>> watchSnapshots(String householdId) {
    return supabase
        .from('portfolio_snapshots')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .order('captured_at')
        .map((rows) => rows.map(PortfolioSnapshot.fromJson).toList());
  }

  /// Upsert dziennego snapshotu (jeden na (gospodarstwo, dzień)).
  /// Wywoływane po przeliczeniu wartości portfela.
  Future<void> upsertSnapshot({
    required String householdId,
    required int totalValueCents,
  }) async {
    final today = DateTime.now();
    final date = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    try {
      await supabase.from('portfolio_snapshots').upsert(
        {
          'household_id': householdId,
          'total_value_cents': totalValueCents,
          'captured_at': date,
        },
        onConflict: 'household_id,captured_at',
      ).timeout(kSupabaseWriteTimeout);
    } on Object {
      // snapshot to bonus — błąd nie blokuje wyświetlania portfela
    }
  }
}
