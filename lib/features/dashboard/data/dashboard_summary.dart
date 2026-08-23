import 'package:nasz_budzet_domowy/features/dashboard/application/date_range_filter.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

/// Wynik agregacji transakcji w danym zakresie dat.
class DashboardSummary {
  const DashboardSummary({
    required this.totalIncomeCents,
    required this.totalExpenseCents,
    required this.prevBalanceCents,
    required this.expenseByCategoryId,
    required this.barBuckets,
    required this.runningBalancePoints,
  });

  factory DashboardSummary.compute(
    List<Transaction> current,
    List<Transaction> previous,
    DateRangeFilter range,
  ) {
    var income = 0;
    var expense = 0;
    final byCategory = <String, int>{};

    for (final t in current) {
      if (t.type == TransactionType.income) {
        income += t.amountCents;
      } else {
        expense += t.amountCents;
        byCategory[t.categoryId] =
            (byCategory[t.categoryId] ?? 0) + t.amountCents;
      }
    }

    var prevIncome = 0;
    var prevExpense = 0;
    for (final t in previous) {
      if (t.type == TransactionType.income) {
        prevIncome += t.amountCents;
      } else {
        prevExpense += t.amountCents;
      }
    }

    return DashboardSummary(
      totalIncomeCents: income,
      totalExpenseCents: expense,
      prevBalanceCents: prevIncome - prevExpense,
      expenseByCategoryId: byCategory,
      barBuckets: _buildBarBuckets(current, range),
      runningBalancePoints: _buildRunningBalance(current, range),
    );
  }

  final int totalIncomeCents;
  final int totalExpenseCents;
  final Map<String, int> expenseByCategoryId;
  final List<BarBucket> barBuckets;
  final List<RunningBalancePoint> runningBalancePoints;

  /// Saldo poprzedniego równego okresu — do wyliczenia delty.
  final int prevBalanceCents;

  int get balanceCents => totalIncomeCents - totalExpenseCents;

  int get deltaCents => balanceCents - prevBalanceCents;

  // -------------------------------------------------------------------------

  static List<BarBucket> _buildBarBuckets(
    List<Transaction> txs,
    DateRangeFilter range,
  ) {
    final days = range.end.difference(range.start).inDays;
    final BucketMode mode;
    if (days <= 14) {
      mode = BucketMode.daily;
    } else if (days <= 90) {
      mode = BucketMode.weekly;
    } else {
      mode = BucketMode.monthly;
    }

    final buckets = <DateTime, (int, int)>{};
    for (final t in txs) {
      final key = _bucketKey(t.occurredAt, mode);
      final (inc, exp) = buckets[key] ?? (0, 0);
      if (t.type == TransactionType.income) {
        buckets[key] = (inc + t.amountCents, exp);
      } else {
        buckets[key] = (inc, exp + t.amountCents);
      }
    }

    final list = buckets.entries
        .map(
          (e) => BarBucket(
            date: e.key,
            incomeCents: e.value.$1,
            expenseCents: e.value.$2,
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  static DateTime _bucketKey(DateTime date, BucketMode mode) => switch (mode) {
        BucketMode.daily => DateTime(date.year, date.month, date.day),
        BucketMode.weekly => () {
            final monday = date.subtract(
              Duration(days: date.weekday - DateTime.monday),
            );
            return DateTime(monday.year, monday.month, monday.day);
          }(),
        BucketMode.monthly => DateTime(date.year, date.month),
      };

  static List<RunningBalancePoint> _buildRunningBalance(
    List<Transaction> txs,
    DateRangeFilter range,
  ) {
    if (txs.isEmpty) return [];

    final sorted = [...txs]..sort(
        (a, b) => a.occurredAt.compareTo(b.occurredAt),
      );

    final points = <RunningBalancePoint>[];
    var running = 0;

    // Grupuj po dniu, sumuj każdy dzień.
    DateTime? prevDay;
    var dayDelta = 0;

    for (final t in sorted) {
      final day = DateTime(
        t.occurredAt.year,
        t.occurredAt.month,
        t.occurredAt.day,
      );
      if (prevDay != null && day != prevDay) {
        running += dayDelta;
        points.add(RunningBalancePoint(date: prevDay, balanceCents: running));
        dayDelta = 0;
      }
      dayDelta +=
          t.type == TransactionType.income ? t.amountCents : -t.amountCents;
      prevDay = day;
    }
    if (prevDay != null) {
      running += dayDelta;
      points.add(RunningBalancePoint(date: prevDay, balanceCents: running));
    }

    return points;
  }
}

enum BucketMode { daily, weekly, monthly }

class BarBucket {
  const BarBucket({
    required this.date,
    required this.incomeCents,
    required this.expenseCents,
  });

  final DateTime date;
  final int incomeCents;
  final int expenseCents;
}

class RunningBalancePoint {
  const RunningBalancePoint({
    required this.date,
    required this.balanceCents,
  });

  final DateTime date;
  final int balanceCents;
}
