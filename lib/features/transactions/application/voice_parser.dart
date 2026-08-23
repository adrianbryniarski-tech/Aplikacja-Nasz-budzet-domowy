import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

/// Wynik parsowania transkryptu głosowego.
///
/// Pola null = nie rozpoznane — formularz zostawia je puste,
/// użytkownik dopisuje ręcznie.
class VoiceParseResult {
  const VoiceParseResult({
    this.amountCents,
    this.occurredAt,
    this.categoryId,
    this.categoryName,
    this.description,
    this.type = TransactionType.expense,
  });

  final int? amountCents;
  final DateTime? occurredAt;
  final String? categoryId;
  final String? categoryName;
  final String? description;
  final TransactionType type;

  bool get hasAmount => amountCents != null;
  bool get hasDate => occurredAt != null;
  bool get hasCategory => categoryId != null;

  VoiceParseResult copyWith({
    int? amountCents,
    DateTime? occurredAt,
    String? categoryId,
    String? categoryName,
    String? description,
    TransactionType? type,
  }) =>
      VoiceParseResult(
        amountCents: amountCents ?? this.amountCents,
        occurredAt: occurredAt ?? this.occurredAt,
        categoryId: categoryId ?? this.categoryId,
        categoryName: categoryName ?? this.categoryName,
        description: description ?? this.description,
        type: type ?? this.type,
      );
}

/// Parser głosowy — regex + heurystyki PL.
///
/// Wejście: surowy transkrypt z Vosk (lowercase string).
/// Cel: wyłuskać kwotę, datę i kategorię bez LLM (offline, 0 zł).
///
/// Stały regex-only — rozszerzyć gdy >20% głosów nie jest parsowanych.
class VoiceParser {
  const VoiceParser(this._categories);

  final List<Category> _categories;

  // -----------------------------------------------------------------------
  // Kwota
  // -----------------------------------------------------------------------

  static final _amountRe = RegExp(
    r'(\d+(?:[.,]\d{1,2})?)'
    r'\s*(?:zł|złotych|złote|pln|złoty)?',
    caseSensitive: false,
  );

  static int? _parseAmount(String text) {
    final match = _amountRe.firstMatch(text);
    if (match == null) return null;
    final raw = match.group(1)!.replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  // -----------------------------------------------------------------------
  // Data
  // -----------------------------------------------------------------------

  static final _dateKeywords = <String, int Function(DateTime)>{
    'dziś': (now) => 0,
    'dzisiaj': (now) => 0,
    'dzis': (now) => 0,
    'wczoraj': (now) => -1,
    'przedwczoraj': (now) => -2,
    'pojutrze': (now) => 2,
    'jutro': (now) => 1,
    'poniedziałek': (now) => _daysToWeekday(now, DateTime.monday),
    'poniedzialek': (now) => _daysToWeekday(now, DateTime.monday),
    'wtorek': (now) => _daysToWeekday(now, DateTime.tuesday),
    'środa': (now) => _daysToWeekday(now, DateTime.wednesday),
    'sroda': (now) => _daysToWeekday(now, DateTime.wednesday),
    'czwartek': (now) => _daysToWeekday(now, DateTime.thursday),
    'piątek': (now) => _daysToWeekday(now, DateTime.friday),
    'piatek': (now) => _daysToWeekday(now, DateTime.friday),
    'sobota': (now) => _daysToWeekday(now, DateTime.saturday),
    'niedziela': (now) => _daysToWeekday(now, DateTime.sunday),
  };

  static int _daysToWeekday(DateTime now, int targetWeekday) {
    var diff = now.weekday - targetWeekday;
    if (diff <= 0) diff += 7;
    return -diff;
  }

  static DateTime? _parseDate(String text) {
    final lower = text.toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final entry in _dateKeywords.entries) {
      if (lower.contains(entry.key)) {
        final delta = entry.value(now);
        return today.add(Duration(days: delta));
      }
    }

    // Konkretna data: "12 marca", "5 maja 2024"
    final dateRe = RegExp(
      r'(\d{1,2})\s+(?:stycznia|lutego|marca|kwietnia|maja|czerwca|'
      'lipca|sierpnia|września|wrz|października|paź|listopada|grudnia)'
      r'(?:\s+(\d{4}))?',
      caseSensitive: false,
    );
    final m = dateRe.firstMatch(lower);
    if (m != null) {
      final day = int.tryParse(m.group(1)!);
      final year = int.tryParse(m.group(2) ?? '') ?? now.year;
      final monthStr = m.group(0)!;
      final month = _monthNumber(monthStr);
      if (day != null && month != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  static int? _monthNumber(String text) {
    const months = {
      'stycznia': 1,
      'styczeń': 1,
      'styczen': 1,
      'lutego': 2,
      'luty': 2,
      'marca': 3,
      'marzec': 3,
      'kwietnia': 4,
      'kwiecień': 4,
      'kwiecien': 4,
      'maja': 5,
      'maj': 5,
      'czerwca': 6,
      'czerwiec': 6,
      'lipca': 7,
      'lipiec': 7,
      'sierpnia': 8,
      'sierpień': 8,
      'sierpien': 8,
      'września': 9,
      'wrz': 9,
      'wrzesień': 9,
      'wrzesien': 9,
      'października': 10,
      'paź': 10,
      'październik': 10,
      'pazdziernik': 10,
      'listopada': 11,
      'listopad': 11,
      'grudnia': 12,
      'grudzień': 12,
      'grudzien': 12,
    };
    for (final entry in months.entries) {
      if (text.toLowerCase().contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Kategoria — aliasy merchant → kategoria
  // -----------------------------------------------------------------------

  // Wyrazy kluczowe dla kategorii systemowych + popularne nazwy sklepów/firm.
  static const _merchantAliases = <String, String>{
    // Spożywcze
    'biedronka': 'Spożywcze',
    'lidl': 'Spożywcze',
    'aldi': 'Spożywcze',
    'netto': 'Spożywcze',
    'żabka': 'Spożywcze',
    'zabka': 'Spożywcze',
    'carrefour': 'Spożywcze',
    'kaufland': 'Spożywcze',
    'dino': 'Spożywcze',
    'spar': 'Spożywcze',
    'market': 'Spożywcze',
    'sklep': 'Spożywcze',
    'zakupy': 'Spożywcze',
    'spożywcze': 'Spożywcze',
    'spozywcze': 'Spożywcze',
    'warzywa': 'Spożywcze',
    'owoce': 'Spożywcze',
    // Paliwo / Transport
    'orlen': 'Transport',
    'bp': 'Transport',
    'shell': 'Transport',
    'circle k': 'Transport',
    'lotos': 'Transport',
    'paliwo': 'Transport',
    'benzyna': 'Transport',
    'diesel': 'Transport',
    'autostrada': 'Transport',
    'mpk': 'Transport',
    'ztm': 'Transport',
    'bilet': 'Transport',
    'taksówka': 'Transport',
    'taksowka': 'Transport',
    'uber': 'Transport',
    'bolt': 'Transport',
    // Zdrowie
    'apteka': 'Zdrowie',
    'doz': 'Zdrowie',
    'dbam o zdrowie': 'Zdrowie',
    'leki': 'Zdrowie',
    'lekarz': 'Zdrowie',
    'dentysta': 'Zdrowie',
    'szpital': 'Zdrowie',
    'przychodnia': 'Zdrowie',
    // Rachunki
    'prąd': 'Rachunki',
    'prad': 'Rachunki',
    'gaz': 'Rachunki',
    'czynsz': 'Rachunki',
    'internet': 'Rachunki',
    'telefon': 'Rachunki',
    'abonament': 'Rachunki',
    'woda': 'Rachunki',
    // Rozrywka
    'kino': 'Rozrywka',
    'netflix': 'Rozrywka',
    'spotify': 'Rozrywka',
    'disney': 'Rozrywka',
    'hbo': 'Rozrywka',
    'bilety': 'Rozrywka',
    'restauracja': 'Rozrywka',
    'pizzeria': 'Rozrywka',
    'pizza': 'Rozrywka',
    'pub': 'Rozrywka',
    'bar': 'Rozrywka',
    // Ubrania
    'zara': 'Ubrania',
    'h&m': 'Ubrania',
    'reserved': 'Ubrania',
    'buty': 'Ubrania',
    'ubrania': 'Ubrania',
    'odzież': 'Ubrania',
    'odziez': 'Ubrania',
    // Dochody
    'pensja': 'Pensja',
    'wynagrodzenie': 'Pensja',
    'premia': 'Inne dochody',
    'zwrot': 'Inne dochody',
    // Dzieci
    'zabawka': 'Dzieci',
    'przedszkole': 'Dzieci',
    'szkoła': 'Dzieci',
    'szkola': 'Dzieci',
    'podręcznik': 'Dzieci',
    'podrecznik': 'Dzieci',
  };

  Category? _matchCategory(String text) {
    final lower = text.toLowerCase();

    // 1. Szukaj aliasów merchant.
    for (final entry in _merchantAliases.entries) {
      if (lower.contains(entry.key)) {
        final found = _categories.firstWhere(
          (c) => c.name.toLowerCase() == entry.value.toLowerCase(),
          orElse: () => _categories.first,
        );
        if (found.name.toLowerCase() == entry.value.toLowerCase()) {
          return found;
        }
      }
    }

    // 2. Fuzzy: czy nazwa kategorii dosłownie pada w tekście.
    for (final cat in _categories) {
      if (lower.contains(cat.name.toLowerCase())) {
        return cat;
      }
    }

    return null;
  }

  // -----------------------------------------------------------------------
  // Typ (income vs expense)
  // -----------------------------------------------------------------------

  static const _incomeKeywords = [
    'dostałem',
    'dostalam',
    'zarobiłem',
    'zarobil',
    'zarobił',
    'wpłynęło',
    'wplynelo',
    'pensja',
    'wynagrodzenie',
    'premia',
    'dochód',
    'dochod',
    'przychód',
    'przychod',
    'zasilenie',
    'przelew przychodzący',
    'wpłata',
    'wplata',
  ];

  static TransactionType _parseType(String text) {
    final lower = text.toLowerCase();
    for (final kw in _incomeKeywords) {
      if (lower.contains(kw)) return TransactionType.income;
    }
    return TransactionType.expense;
  }

  // -----------------------------------------------------------------------
  // Główna metoda
  // -----------------------------------------------------------------------

  VoiceParseResult parse(String transcript) {
    final amount = _parseAmount(transcript);
    final date = _parseDate(transcript);
    final type = _parseType(transcript);
    final cat = _matchCategory(transcript);

    // Opis = cały transkrypt (użytkownik może go skrócić w formularzu).
    final description = transcript.trim().isNotEmpty ? transcript.trim() : null;

    return VoiceParseResult(
      amountCents: amount,
      occurredAt: date ?? DateTime.now(),
      categoryId: cat?.id,
      categoryName: cat?.name,
      description: description,
      type: type,
    );
  }
}
