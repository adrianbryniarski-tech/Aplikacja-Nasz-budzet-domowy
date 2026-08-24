import 'package:flutter/material.dart';

/// Warianty motywu graficznego. Każdy zachowuje Material 3 jako fundament,
/// ale różni się paletą, tłem, kształtami i typografią. User wybiera w
/// Ustawieniach; wybór persistowany w `shared_preferences`.
///
/// Trendy 2026 (zgodnie z research'em):
/// - Material 3 Expressive — żywe kolory, customizable themes
/// - Glassmorphism refined — szkło używane "chirurgicznie" na cards
/// - Minimalism with functionality — biel/przestrzeń, big typography
/// - Bold typography — duże nagłówki, czytelne cyfry
/// - Dark mode native — first class citizen
enum AppThemeVariant {
  spokojny(
    label: 'Spokojny',
    description: 'Niskobodźcowe pastele, kremowe tło. Dla skupionej pracy.',
  ),
  expressive(
    label: 'Material You',
    description: 'Żywe kolory Material 3 Expressive. Domyślny Android 2026.',
  ),
  szklo(
    label: 'Szkło',
    description: 'Pastele i półprzezroczystości w stylu glassmorphism.',
  ),
  zachod(
    label: 'Zachód',
    description: 'Ciepłe gradienty koralu i bursztynu. Domowa atmosfera.',
  ),
  mono(
    label: 'Mono',
    description: 'Czarno-białe minimum z jednym akcentem. Brutalist 2026.',
  ),
  cyber(
    label: 'Cyber',
    description: 'Neonowy zielony + czarne OLED. Cyberpunk 2026 — najlepszy w '
        'trybie ciemnym.',
  ),
  synthwave(
    label: 'Synthwave',
    description: 'Magenta + cyan retro 80s. Mocny vibe, świetlist w ciemnym.',
  ),
  galaktyka(
    label: 'Galaktyka',
    description:
        'Deep space purple/indigo + neonowe gwiazdy. Głęboka czerń OLED '
        'z fioletowymi akcentami.',
  ),
  kredka(
    label: 'Kredka',
    description:
        'Kreskówka: grube kontury, soczyste kolory, zaokrąglona czcionka. '
        'Zabawowy neubrutalism.',
  ),
  plastelina(
    label: 'Plastelina',
    description: 'Miękkie, puszyste karty jak z gliny (claymorphism). Ciepłe '
        'pastele, delikatne cienie.',
  ),
  aurora(
    label: 'Aurora',
    description: 'Minimal premium: dużo bieli/czerni, wielka typografia, jeden '
        'żywy akcent. Czysto i nowocześnie.',
  ),
  neo(
    label: 'Neo',
    description: 'Elektryczny indygo + cyjan na czerni OLED, neonowy gradient '
        'i glow. Zaprojektowany w parze z nowym pulpitem.',
  ),
  dragonBall(
    label: 'Dragon Ball',
    description: 'Świat Dragon Ball: pomarańcz gi i energia ki, złote akcenty, '
        'gruba „anime" typografia. Smocza kula w rogu.',
  ),
  pokemon(
    label: 'Pokémon',
    description:
        'Świat Pokémon: błękit i czerwień Poké Ball, elektryczny żółty, '
        'okrągła przyjazna czcionka. Poké Ball w rogu.',
  ),
  manga(
    label: 'Manga',
    description: 'Czarno-biały komiks: grube czarne kontury, kropkowy raster '
        '(screentone), czerwony akcent, komiksowe ikony i czcionka.',
  );

  const AppThemeVariant({required this.label, required this.description});

  final String label;
  final String description;

  /// Motywy „komiksowe" — grube czarne kontury, kropkowy raster (halftone)
  /// i twardy przesunięty cień kart. Kredka i Manga.
  bool get isComic =>
      this == AppThemeVariant.kredka || this == AppThemeVariant.manga;

  /// Czy motyw używa "premium" efektów neon: glow buttons, animated borders.
  bool get hasNeonEffects =>
      this == AppThemeVariant.cyber ||
      this == AppThemeVariant.synthwave ||
      this == AppThemeVariant.galaktyka ||
      this == AppThemeVariant.neo;

  /// Czy rysujemy subtelne dwukolorowe tło-gradient (neon + Dragon Ball,
  /// Pokémon). Szersze niż [hasNeonEffects] — nie pociąga glow/animated.
  bool get hasGradientBackground =>
      hasNeonEffects ||
      this == AppThemeVariant.dragonBall ||
      this == AppThemeVariant.pokemon;

  /// Drugi kolor dla gradientu tła (poza primary z ColorScheme).
  /// Używany w `NeonGradientBackground` do subtle gradient'u.
  Color get gradientAccent => switch (this) {
        AppThemeVariant.cyber => const Color(0xFF00D9C0),
        AppThemeVariant.synthwave => const Color(0xFF6CC7FF),
        AppThemeVariant.galaktyka => const Color(0xFFFF6CD9),
        AppThemeVariant.neo => const Color(0xFF22D3EE), // cyjan

        AppThemeVariant.dragonBall => const Color(0xFFFFC400), // złota energia
        AppThemeVariant.pokemon => const Color(0xFFFFCB05), // elektryczny żółty
        _ => const Color(0xFF000000),
      };
}

/// Zestawy kolorów dla motywu „Manga" (jak wersje zegarków GA-2100 MNG).
/// Każdy ma kolor akcentu (przyciski/akcje) i kolor tła w trybie jasnym.
/// W trybie ciemnym tło zawsze = czysta czerń OLED.
enum MangaPalette {
  biel('Biel', accent: Color(0xFFFF3366), background: Color(0xFFFFFFFF)),
  blekit('Błękit', accent: Color(0xFFFF3366), background: Color(0xFF59C2ED)),
  volt('Volt', accent: Color(0xFFCBD400), background: Color(0xFFFFFFFF)),
  klasyk('Czerwień', accent: Color(0xFFE5241B), background: Color(0xFFFFFFFF));

  const MangaPalette(
    this.label, {
    required this.accent,
    required this.background,
  });

  final String label;
  final Color accent;
  final Color background;
}

/// Builder ThemeData dla wszystkich wariantów [AppThemeVariant]
/// + jasny/ciemny tryb.
class AppTheme {
  const AppTheme._();

  // Akcenty INCOME/EXPENSE są STAŁE między motywami — finanse muszą być
  // czytelne jednakowo wszędzie (zielony = dochód, czerwony = wydatek).
  static const Color incomeAccent = Color(0xFF4AE89E);
  static const Color expenseAccent = Color(0xFFE07A7A);

  static ThemeData light(
    AppThemeVariant variant, {
    MangaPalette? mangaPalette,
  }) =>
      _build(variant, Brightness.light, mangaPalette);
  static ThemeData dark(
    AppThemeVariant variant, {
    MangaPalette? mangaPalette,
  }) =>
      _build(variant, Brightness.dark, mangaPalette);

  static ThemeData _build(
    AppThemeVariant variant,
    Brightness brightness, [
    MangaPalette? mangaPalette,
  ]) {
    final spec = _specFor(variant, brightness, mangaPalette);

    // Gdy tło jest ciemne (np. paleta „Czerń" w trybie jasnym), wymuszamy
    // ciemny schemat — inaczej tekst (onSurface) byłby czarny na czerni.
    final effBrightness = spec.background.computeLuminance() < 0.25
        ? Brightness.dark
        : brightness;

    var colorScheme = ColorScheme.fromSeed(
      seedColor: spec.seed,
      brightness: effBrightness,
    ).copyWith(surface: spec.surface);

    // Manga = „krzykliwy" komiks: kolor akcentu MUSI być żywy (Material
    // domyślnie go przygasza), a tekst na nim czarny/biały wg jasności.
    if (variant == AppThemeVariant.manga) {
      final onAccent =
          spec.seed.computeLuminance() > 0.5 ? Colors.black : Colors.white;
      // Wszystkie warstwy powierzchni = kolor karty (spójna czerń/biel na
      // kafelkach i wykresach, bez szarych „uniesionych" warstw Material).
      colorScheme = colorScheme.copyWith(
        primary: spec.seed,
        onPrimary: onAccent,
        secondary: spec.seed,
        onSecondary: onAccent,
        surfaceContainerLowest: spec.surface,
        surfaceContainerLow: spec.surface,
        surfaceContainer: spec.surface,
        surfaceContainerHigh: spec.surface,
        surfaceContainerHighest: spec.surface,
      );
    }

    final base = effBrightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);

    final textTheme = _textThemeFor(base.textTheme, variant, spec);
    final borderRadius = _borderRadiusFor(variant);

    // Kontur kart/pól — tylko motywy z `cardBorder` (Kredka). Reszta: brak.
    final borderSide = spec.cardBorder != null
        ? BorderSide(color: spec.cardBorder!, width: spec.cardBorderWidth)
        : BorderSide.none;
    final isComic = variant.isComic;
    final isManga = variant == AppThemeVariant.manga;

    // Kształt przycisków zależny od motywu: pigułka (clay), ośmiokąt „CasiOak"
    // (Manga — ścięte rogi), ostre prostokąty (mono/cyber), zaokrąglone (reszta).
    final buttonShape = switch (variant) {
      AppThemeVariant.plastelina => StadiumBorder(side: borderSide),
      AppThemeVariant.manga => BeveledRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: borderSide,
        ),
      AppThemeVariant.mono || AppThemeVariant.cyber => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: borderSide,
        ),
      _ => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius * 0.8),
          side: borderSide,
        ),
    };

    // Kształt kart: Manga = ośmiokątna koperta (bevel), reszta = zaokrąglona.
    final ShapeBorder cardShape = isManga
        ? BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: borderSide,
          )
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: borderSide,
          );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: spec.background,
      textTheme: textTheme,
      // Nowoczesne przejścia między ekranami (Android 15 „fade forwards"
      // zamiast domyślnego zoomu). Tylko Android — apka nie buduje się na
      // iOS, a builder Cupertino wyleciał z nowszych wersji Fluttera
      // (build padał na „Method not found" przy stable 3.47).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: spec.surface,
        elevation: spec.cardElevation,
        shadowColor:
            spec.cardElevation > 0 ? colorScheme.shadow : Colors.transparent,
        shape: cardShape,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: spec.background,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: buttonShape,
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: isComic ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: buttonShape,
          side: isComic ? borderSide : null,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: spec.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius * 0.7),
          borderSide: borderSide,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius * 0.7),
          borderSide: borderSide,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius * 0.7),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: spec.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius * 1.2),
          side: isComic
              ? borderSide
              : BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
    );
  }

  static _ThemeSpec _specFor(
    AppThemeVariant variant,
    Brightness brightness, [
    MangaPalette? mangaPalette,
  ]) {
    final isDark = brightness == Brightness.dark;
    return switch (variant) {
      AppThemeVariant.spokojny => _ThemeSpec(
          seed: isDark ? const Color(0xFF8FA8E0) : const Color(0xFF5B7AB9),
          background:
              isDark ? const Color(0xFF121317) : const Color(0xFFF7F6F2),
          surface: isDark ? const Color(0xFF1A1C22) : const Color(0xFFFCFBF8),
          cardElevation: 0,
        ),
      AppThemeVariant.expressive => _ThemeSpec(
          seed: const Color(0xFF6750A4),
          background:
              isDark ? const Color(0xFF1C1B1F) : const Color(0xFFFEF7FF),
          surface: isDark ? const Color(0xFF2B2930) : const Color(0xFFF7F2FA),
          cardElevation: 1,
        ),
      AppThemeVariant.szklo => _ThemeSpec(
          seed: isDark ? const Color(0xFF8FCFEC) : const Color(0xFF5BA8D9),
          background:
              isDark ? const Color(0xFF0F1620) : const Color(0xFFEEF4FB),
          surface: isDark
              ? const Color(0xFF1A2330).withValues(alpha: 0.85)
              : const Color(0xFFFFFFFF).withValues(alpha: 0.7),
          cardElevation: 2,
        ),
      AppThemeVariant.zachod => _ThemeSpec(
          seed: isDark ? const Color(0xFFFFAB8E) : const Color(0xFFE07A4F),
          background:
              isDark ? const Color(0xFF1E1612) : const Color(0xFFFDF4ED),
          surface: isDark ? const Color(0xFF2A1F18) : const Color(0xFFFFF8F1),
          cardElevation: 0,
        ),
      AppThemeVariant.mono => _ThemeSpec(
          seed: const Color(0xFF65D946),
          background:
              isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          surface: isDark ? const Color(0xFF111111) : const Color(0xFFF2F2F2),
          cardElevation: 0,
        ),

      // Cyberpunk neon — najjaskrawszy w dark mode, OLED-friendly czerń.
      // Neonowy zielony (jak Matrix) na pure black tle.
      AppThemeVariant.cyber => _ThemeSpec(
          seed: isDark ? const Color(0xFF00FF88) : const Color(0xFF00C46A),
          background:
              isDark ? const Color(0xFF000000) : const Color(0xFFF0FAF5),
          surface: isDark ? const Color(0xFF0A1410) : const Color(0xFFE0F7E8),
          cardElevation: isDark ? 0 : 1,
          fontFamily: 'SpaceMono',
        ),

      // Synthwave / retro 80s — magenta + cyan, neonowy glow w ciemnym.
      AppThemeVariant.synthwave => _ThemeSpec(
          seed: isDark ? const Color(0xFFFF3EA5) : const Color(0xFFE91E63),
          background:
              isDark ? const Color(0xFF0D0421) : const Color(0xFFFFF0F8),
          surface: isDark ? const Color(0xFF1A0935) : const Color(0xFFFEE0F0),
          cardElevation: isDark ? 0 : 1,
          headingFontFamily: 'Orbitron',
        ),

      // Deep space / galaxy — fioletowo-indigo na pure black, neonowe
      // gwiazdy. Wow factor dla dark, lekkie pastele dla light.
      AppThemeVariant.galaktyka => _ThemeSpec(
          seed: isDark ? const Color(0xFFB36CFF) : const Color(0xFF7C4DFF),
          background:
              isDark ? const Color(0xFF030014) : const Color(0xFFF5F0FF),
          surface: isDark ? const Color(0xFF120829) : const Color(0xFFEAE0FF),
          cardElevation: isDark ? 0 : 1,
        ),

      // Kreskówka / neubrutalism — soczysty pomarańcz na kremowym tle,
      // grube kontury kart i pól, zero cieni. Czcionka Fredoka (zaokrąglona).
      AppThemeVariant.kredka => _ThemeSpec(
          seed: isDark ? const Color(0xFFFF8A4C) : const Color(0xFFFF5C2B),
          background:
              isDark ? const Color(0xFF1A1410) : const Color(0xFFFFF6E9),
          surface: isDark ? const Color(0xFF241B14) : const Color(0xFFFFFFFF),
          cardElevation: 0,
          cardBorder:
              isDark ? const Color(0xFFFFE0C2) : const Color(0xFF231A12),
          cardBorderWidth: 2.5,
          fontFamily: 'Fredoka',
        ),

      // Claymorphism — miękki fiolet, puszyste karty (elevation = miękki
      // cień), bardzo duże zaokrąglenia, ciepłe pastelowe tło.
      AppThemeVariant.plastelina => _ThemeSpec(
          seed: isDark ? const Color(0xFFB3A8FF) : const Color(0xFF8B7CF6),
          background:
              isDark ? const Color(0xFF15131F) : const Color(0xFFF3F0FA),
          surface: isDark ? const Color(0xFF221E30) : const Color(0xFFFBFAFF),
          cardElevation: 3,
        ),

      // Aurora — minimal premium: prawie biel / prawie czerń, mocny indygo
      // akcent, brak cieni i konturów, duży oddech.
      AppThemeVariant.aurora => _ThemeSpec(
          seed: isDark ? const Color(0xFF8B82FF) : const Color(0xFF4F46E5),
          background:
              isDark ? const Color(0xFF08080F) : const Color(0xFFFAFAFD),
          surface: isDark ? const Color(0xFF14141F) : const Color(0xFFFFFFFF),
          cardElevation: 0,
        ),

      // Neo — „kozacki" motyw w parze z nowym pulpitem: elektryczny
      // indygo + cyjanowy gradient, czerń OLED w ciemnym, chłodna biel
      // w jasnym. Neonowe glow/animowane bordery (hasNeonEffects).
      AppThemeVariant.neo => _ThemeSpec(
          seed: isDark ? const Color(0xFF7C6CFF) : const Color(0xFF5B4CFF),
          background:
              isDark ? const Color(0xFF05060E) : const Color(0xFFF4F5FB),
          surface: isDark ? const Color(0xFF10131F) : const Color(0xFFFFFFFF),
          cardElevation: isDark ? 0 : 1,
        ),

      // Dragon Ball — pomarańcz gi Goku + złota energia ki, ciepłe tło,
      // gruba „anime" typografia w nagłówkach (Russo One). Energetycznie.
      AppThemeVariant.dragonBall => _ThemeSpec(
          seed: isDark ? const Color(0xFFFF9D3D) : const Color(0xFFEF6C00),
          background:
              isDark ? const Color(0xFF160E06) : const Color(0xFFFFF4E6),
          surface: isDark ? const Color(0xFF241809) : const Color(0xFFFFFFFF),
          cardElevation: isDark ? 0 : 1,
          headingFontFamily: 'RussoOne',
        ),

      // Pokémon — błękit logo + czerwień/żółty Poké Ball, jasne „niebo",
      // okrągła przyjazna czcionka (Baloo 2). Wesoło i czytelnie.
      AppThemeVariant.pokemon => _ThemeSpec(
          seed: isDark ? const Color(0xFF5BA3E0) : const Color(0xFF2A75BB),
          background:
              isDark ? const Color(0xFF0B1420) : const Color(0xFFF0F7FF),
          surface: isDark ? const Color(0xFF14202E) : const Color(0xFFFFFFFF),
          cardElevation: 1,
          fontFamily: 'Baloo2',
        ),

      // Manga / komiks — biel + czerń (lub czysta czerń OLED w trybie ciemnym),
      // akcent z palety, grube kontury, gęsty raster, ostre panele (radius 0)
      // i komiksowe nagłówki (Bangers). Tryb ciemny = „manga nocą".
      AppThemeVariant.manga => _mangaSpec(isDark, mangaPalette),
    };
  }

  /// Spec motywu Manga. Tryb CIEMNY = głęboka czerń OLED wszędzie (tło,
  /// karty, wykresy). Tryb JASNY = tło wg palety (biel / sky blue). Kolor
  /// kart i konturu dobrany do jasności tła; kontur czysto biały/czarny 3.5px.
  static _ThemeSpec _mangaSpec(bool isDark, MangaPalette? palette) {
    final background = isDark
        ? const Color(0xFF000000)
        : (palette?.background ?? const Color(0xFFFFFFFF));
    final darkBg = background.computeLuminance() < 0.25;
    return _ThemeSpec(
      seed: palette?.accent ?? const Color(0xFFFF3366),
      background: background,
      // Karta ledwie odróżnialna od tła — to gruby kontur ją definiuje.
      surface: darkBg ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF),
      cardElevation: 0,
      cardBorder: darkBg ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      cardBorderWidth: 4,
      fontFamily: 'SpaceMono',
      headingFontFamily: 'ArchivoBlack',
    );
  }

  static double _borderRadiusFor(AppThemeVariant variant) {
    return switch (variant) {
      AppThemeVariant.spokojny => 20,
      AppThemeVariant.expressive => 24,
      AppThemeVariant.szklo => 28,
      AppThemeVariant.zachod => 22,
      AppThemeVariant.mono => 4,
      AppThemeVariant.cyber => 8, // ostry, terminal-like
      AppThemeVariant.synthwave => 16,
      AppThemeVariant.galaktyka => 24,
      AppThemeVariant.kredka => 16, // pyzate, ale nie owalne
      AppThemeVariant.plastelina => 30, // mocno zaokrąglone, „z gliny"
      AppThemeVariant.aurora => 20,
      AppThemeVariant.neo => 24, // duże, „premium" zaokrąglenia
      AppThemeVariant.dragonBall => 14, // chunky, energetyczne
      AppThemeVariant.pokemon => 18, // przyjazne, okrągławe
      AppThemeVariant.manga => 0, // ostre panele jak bezel zegarka G-Shock
    };
  }

  static TextTheme _textThemeFor(
    TextTheme base,
    AppThemeVariant variant,
    _ThemeSpec spec,
  ) {
    var common = base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );

    // Czcionka całego motywu (np. Fredoka, Baloo2, SpaceMono).
    if (spec.fontFamily != null) {
      common = common.apply(fontFamily: spec.fontFamily);
    }
    // Czcionka tylko nagłówków (ozdobny krój: Russo One, Orbitron) — body
    // zostaje domyślne dla czytelności.
    final heading = spec.headingFontFamily;
    if (heading != null) {
      common = common.copyWith(
        displayLarge: common.displayLarge?.copyWith(fontFamily: heading),
        displayMedium: common.displayMedium?.copyWith(fontFamily: heading),
        displaySmall: common.displaySmall?.copyWith(fontFamily: heading),
        headlineLarge: common.headlineLarge?.copyWith(fontFamily: heading),
        headlineMedium: common.headlineMedium?.copyWith(fontFamily: heading),
        headlineSmall: common.headlineSmall?.copyWith(fontFamily: heading),
        titleLarge: common.titleLarge?.copyWith(fontFamily: heading),
      );
    }

    if (variant == AppThemeVariant.mono) {
      return common.copyWith(
        displayLarge: common.displayLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -2.5,
        ),
        displayMedium: common.displayMedium?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
        ),
        headlineMedium: common.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        titleLarge: common.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      );
    }

    // Kredka — Fredoka (ze speca) + grube wagi dla „bajkowego" charakteru.
    if (variant == AppThemeVariant.kredka) {
      return common.copyWith(
        displayLarge: common.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        displayMedium: common.displayMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        headlineMedium:
            common.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        titleLarge: common.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      );
    }

    // Cyber — szerokie letter-spacing dla "terminal" feel.
    if (variant == AppThemeVariant.cyber) {
      return common.copyWith(
        displayLarge: common.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
        displayMedium: common.displayMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      );
    }

    return common;
  }
}

class _ThemeSpec {
  const _ThemeSpec({
    required this.seed,
    required this.background,
    required this.surface,
    required this.cardElevation,
    this.cardBorder,
    this.cardBorderWidth = 0,
    this.fontFamily,
    this.headingFontFamily,
  });

  final Color seed;
  final Color background;
  final Color surface;
  final double cardElevation;

  /// Widoczny kontur kart i pól (motyw „Kredka"). `null` = brak konturu.
  final Color? cardBorder;
  final double cardBorderWidth;

  /// Czcionka dla CAŁEJ typografii motywu. `null` = domyślna (Roboto).
  final String? fontFamily;

  /// Czcionka tylko dla nagłówków (display/headline/title) — gdy krój jest
  /// ozdobny i nieczytelny w długim tekście (np. Russo One, Orbitron).
  final String? headingFontFamily;
}

/// Paleta 12 odcieni dla kategorii (spójna z seedem migracji SQL).
class CategoryPalette {
  const CategoryPalette._();

  static const List<Color> palette = [
    Color(0xFF7AB87A),
    Color(0xFF5B8FB9),
    Color(0xFFE8A24A),
    Color(0xFFB97AB8),
    Color(0xFFE07A7A),
    Color(0xFFE8C24A),
    Color(0xFF8B7355),
    Color(0xFFB95B8F),
    Color(0xFF4AE89E),
    Color(0xFF7AE0D5),
    Color(0xFF5B7AB9),
    Color(0xFF94A3B8),
  ];

  static const Color fallback = Color(0xFF94A3B8);

  static Color fromHex(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }
}
