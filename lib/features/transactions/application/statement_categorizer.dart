import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/transactions/data/transaction.dart';

/// Nauczona reguła kategoryzacji (wiersz tabeli `merchant_rules`).
class MerchantRule {
  const MerchantRule({required this.pattern, required this.categoryId});

  factory MerchantRule.fromJson(Map<String, dynamic> json) {
    return MerchantRule(
      pattern: json['pattern'] as String,
      categoryId: json['category_id'] as String,
    );
  }

  /// Znormalizowany fragment opisu (jak [TransactionHasher.normalize]).
  final String pattern;
  final String categoryId;
}

/// Przypisuje kategorie pozycjom z wyciągu.
///
/// Kolejność dopasowania:
/// 1. Reguły nauczone od domowników (`merchant_rules`) — najdłuższy
///    pasujący wzorzec wygrywa (dłuższy = bardziej specyficzny).
/// 2. Wbudowana lista popularnych polskich sieci → kategorie seedowe
///    (po NAZWIE, więc działa też gdy id kategorii różni się między
///    gospodarstwami).
/// Zwraca null gdy nic nie pasuje — UI podstawia wtedy „Inne"
/// i wyróżnia wiersz do ręcznego przejrzenia.
class StatementCategorizer {
  StatementCategorizer({
    required List<Category> categories,
    required List<MerchantRule> learnedRules,
  })  : _categoriesById = {for (final c in categories) c.id: c},
        _rules = [...learnedRules]
          ..sort((a, b) => b.pattern.length.compareTo(a.pattern.length)) {
    for (final c in categories) {
      _categoryIdByNormName['${c.type.name}|${_norm(c.name)}'] = c.id;
    }
  }

  final Map<String, Category> _categoriesById;
  final List<MerchantRule> _rules;
  final Map<String, String> _categoryIdByNormName = {};

  /// Wbudowane wzorce (znormalizowane) → nazwa kategorii seedowej.
  /// Rozszerzaj śmiało — reguły nauczone i tak mają pierwszeństwo.
  static const Map<String, String> builtinExpense = {
    // Spożywcze
    'biedronka': 'Spożywcze',
    'lidl': 'Spożywcze',
    'zabka': 'Spożywcze',
    'kaufland': 'Spożywcze',
    'auchan': 'Spożywcze',
    'carrefour': 'Spożywcze',
    'aldi': 'Spożywcze',
    'netto': 'Spożywcze',
    'dino': 'Spożywcze',
    'stokrotka': 'Spożywcze',
    'lewiatan': 'Spożywcze',
    'intermarche': 'Spożywcze',
    'spolem': 'Spożywcze',
    'piekarnia': 'Spożywcze',
    'cukiernia': 'Spożywcze',
    'delikatesy': 'Spożywcze',
    // Transport
    'orlen': 'Transport',
    'shell': 'Transport',
    'circle k': 'Transport',
    'moya': 'Transport',
    'lotos': 'Transport',
    'stacja paliw': 'Transport',
    'mpk': 'Transport',
    'ztm': 'Transport',
    'pkp': 'Transport',
    'intercity': 'Transport',
    'koleo': 'Transport',
    'jakdojade': 'Transport',
    'uber ': 'Transport',
    'bolt': 'Transport',
    'freenow': 'Transport',
    'parking': 'Transport',
    'autostrada': 'Transport',
    'autopay': 'Transport',
    // Rachunki
    'tauron': 'Rachunki',
    'pge ': 'Rachunki',
    'enea': 'Rachunki',
    'energa': 'Rachunki',
    'pgnig': 'Rachunki',
    'orange': 'Rachunki',
    'play ': 'Rachunki',
    't-mobile': 'Rachunki',
    'tmobile': 'Rachunki',
    'netia': 'Rachunki',
    'vectra': 'Rachunki',
    'upc': 'Rachunki',
    'netflix': 'Rachunki',
    'spotify': 'Rachunki',
    'hbo': 'Rachunki',
    'disney': 'Rachunki',
    'wodociagi': 'Rachunki',
    'faktura': 'Rachunki',
    // Zdrowie
    'apteka': 'Zdrowie',
    'gemini': 'Zdrowie',
    'doz ': 'Zdrowie',
    'ziko': 'Zdrowie',
    'super-pharm': 'Zdrowie',
    'superpharm': 'Zdrowie',
    'luxmed': 'Zdrowie',
    'medicover': 'Zdrowie',
    'enel-med': 'Zdrowie',
    'przychodnia': 'Zdrowie',
    'stomatolog': 'Zdrowie',
    'dentysta': 'Zdrowie',
    // Mieszkanie
    'castorama': 'Mieszkanie',
    'leroy': 'Mieszkanie',
    'obi ': 'Mieszkanie',
    'ikea': 'Mieszkanie',
    'jysk': 'Mieszkanie',
    'bricomarche': 'Mieszkanie',
    'czynsz': 'Mieszkanie',
    'wspolnota': 'Mieszkanie',
    'spoldzielnia': 'Mieszkanie',
    // Ubrania
    'h&m': 'Ubrania',
    'zara': 'Ubrania',
    'reserved': 'Ubrania',
    'sinsay': 'Ubrania',
    'cropp': 'Ubrania',
    'mohito': 'Ubrania',
    'ccc': 'Ubrania',
    'deichmann': 'Ubrania',
    'pepco': 'Ubrania',
    'decathlon': 'Ubrania',
    // Dzieci
    'smyk': 'Dzieci',
    'zlobek': 'Dzieci',
    'przedszkole': 'Dzieci',
    'szkola': 'Dzieci',
    // Rozrywka (w tym jedzenie na mieście / dowozy)
    'multikino': 'Rozrywka',
    'helios': 'Rozrywka',
    'cinema': 'Rozrywka',
    'kino': 'Rozrywka',
    'empik': 'Rozrywka',
    'steam': 'Rozrywka',
    'playstation': 'Rozrywka',
    'mcdonald': 'Rozrywka',
    'kfc': 'Rozrywka',
    'burger king': 'Rozrywka',
    'pyszne': 'Rozrywka',
    'glovo': 'Rozrywka',
    'wolt': 'Rozrywka',
    'uber eats': 'Rozrywka',
    'restauracja': 'Rozrywka',
    'pizzeria': 'Rozrywka',
  };

  static const Map<String, String> builtinIncome = {
    'wynagrodzenie': 'Pensja',
    'pensja': 'Pensja',
    'wyplata': 'Pensja',
    'zus': 'Inne dochody',
    '800+': 'Inne dochody',
    'zwrot': 'Inne dochody',
  };

  /// Id kategorii dla opisu, albo null gdy nic nie pasuje.
  String? categoryIdFor(String description, TransactionType type) {
    final norm = ' ${_norm(description)} ';

    // 1. Nauczone reguły (posortowane malejąco po długości wzorca).
    for (final rule in _rules) {
      if (!norm.contains(rule.pattern)) continue;
      final category = _categoriesById[rule.categoryId];
      if (category != null && category.type == type) return rule.categoryId;
    }

    // 2. Wbudowane wzorce → kategoria po nazwie seedowej.
    final builtin =
        type == TransactionType.expense ? builtinExpense : builtinIncome;
    String? bestName;
    var bestLen = 0;
    for (final entry in builtin.entries) {
      if (entry.key.length > bestLen && norm.contains(entry.key)) {
        bestName = entry.value;
        bestLen = entry.key.length;
      }
    }
    if (bestName == null) return null;
    return _categoryIdByNormName['${type.name}|${_norm(bestName)}'];
  }

  /// Wzorzec do zapamiętania jako reguła, gdy user poprawi kategorię:
  /// pierwsze 3 znormalizowane słowa opisu (max 60 znaków — limit DB).
  static String patternFor(String description) {
    final words = _norm(description).split(' ')..removeWhere((w) => w.isEmpty);
    final pattern = words.take(3).join(' ');
    return pattern.length > 60 ? pattern.substring(0, 60) : pattern;
  }

  static String _norm(String s) => TransactionHasher.normalize(s);
}
