import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/animations/data/sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton SoundService — reuse 1 AudioPlayer dla całej apki.
final soundServiceProvider = Provider<SoundService>((ref) {
  final svc = SoundService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Pojedyncza animacja-eyecandy. Każdą można niezależnie wyłączyć w
/// Ustawieniach (gdy komuś się nie podoba albo telefon słabo radzi).
enum AppAnimation {
  moneyRainOnIncome(
    label: 'Deszcz monet przy dochodzie',
    description:
        'Po dodaniu dochodu z nieba lecą banknoty i monety. ~1.5 sekundy.',
  ),
  expenseFlashOnExpense(
    label: 'Czerwony błysk przy wydatku',
    description: 'Krótki czerwony pulse na ekranie po zapisaniu wydatku.',
  ),
  budgetSparkleOnCreate(
    label: 'Iskry przy nowym budżecie',
    description: 'Sparkle gdy utworzysz miesięczny limit.',
  ),
  trexFoodFeast(
    label: 'T-rex zżerający hamburgera',
    description:
        'Spożywcze: 🦖 przebiega przez ekran i pożera 🍔 z beknięciem.',
  ),
  carRushOnTransport(
    label: 'Samochód z dymem i pieniędzmi',
    description: 'Transport / Paliwo: 🚗 przelatuje przez ekran zostawiając '
        '💨 i 💸 za sobą.',
  ),
  pharmacyHealOnHealth(
    label: 'Leczenie pigułkami',
    description:
        'Zdrowie / Apteka: pigułki 💊 zlatują z 6 stron na chorego 🤧, '
        'który po dawce zmienia się w 😎.',
  ),
  billsAttackOnBills(
    label: 'Rachunki w ogniu',
    description: 'Rachunki / Internet / Prąd: 📄 spadają z każdej strony do '
        'środka, zapalają się 🔥, a pieniądze 💸 ulatują w górę.',
  ),
  categoryEmojiRain(
    label: 'Eksplodujące emoji dla pozostałych kategorii',
    description: 'Pozostałe kategorie (Dzieci, Rozrywka, Mieszkanie itd.): '
        'tematyczne emoji wybuchają ze środka ekranu z rotacją '
        'i pulsem skali.',
  ),
  chaChingOnIncome(
    label: 'Cash register "cha-ching!" przy dochodzie',
    description: 'Krótki dźwięk dzwonka kasy fiskalnej (~0.5s) gdy zapiszesz '
        'dochód. Razem z deszczem monet to brzmi jak ABBA bez ABBY.',
  );

  const AppAnimation({required this.label, required this.description});

  final String label;
  final String description;
}

class AnimationSettings {
  const AnimationSettings(this.enabled);

  factory AnimationSettings.defaults() {
    return AnimationSettings({
      for (final a in AppAnimation.values) a: true,
    });
  }

  final Map<AppAnimation, bool> enabled;

  bool isOn(AppAnimation a) => enabled[a] ?? true;

  AnimationSettings toggle(AppAnimation a, {required bool value}) {
    return AnimationSettings({...enabled, a: value});
  }
}

final animationSettingsProvider =
    NotifierProvider<AnimationSettingsNotifier, AnimationSettings>(
  AnimationSettingsNotifier.new,
);

class AnimationSettingsNotifier extends Notifier<AnimationSettings> {
  static const _prefix = 'anim_';

  @override
  AnimationSettings build() {
    _load();
    return AnimationSettings.defaults();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <AppAnimation, bool>{};
    for (final a in AppAnimation.values) {
      final v = prefs.getBool('$_prefix${a.name}');
      map[a] = v ?? true;
    }
    state = AnimationSettings(map);
  }

  Future<void> set(AppAnimation a, {required bool enabled}) async {
    state = state.toggle(a, value: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix${a.name}', enabled);
  }
}
