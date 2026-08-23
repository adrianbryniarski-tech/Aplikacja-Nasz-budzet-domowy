import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/core/security/app_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hashPin', () {
    test('deterministyczny i różny dla różnych PIN-ów', () {
      expect(hashPin('1234'), hashPin('1234'));
      expect(hashPin('1234'), isNot(hashPin('1235')));
      expect(hashPin('1234'), hasLength(64)); // sha256 hex
    });
  });

  group('AppLockSettingsNotifier', () {
    test('domyślnie wyłączona; enable ustawia hash i persystuje', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appLockSettingsProvider.notifier);

      // Poczekaj na _load() z prefs.
      await Future<void>.delayed(Duration.zero);
      expect(container.read(appLockSettingsProvider).enabled, isFalse);

      await notifier.enable('1234');
      expect(container.read(appLockSettingsProvider).enabled, isTrue);
      expect(notifier.verifyPin('1234'), isTrue);
      expect(notifier.verifyPin('0000'), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_lock_pin_hash'), hashPin('1234'));
    });

    test('wczytuje zapisany PIN z dysku', () async {
      SharedPreferences.setMockInitialValues({
        'app_lock_pin_hash': hashPin('4321'),
        'app_lock_biometrics': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appLockSettingsProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final s = container.read(appLockSettingsProvider);
      expect(s.loaded, isTrue);
      expect(s.enabled, isTrue);
      expect(s.biometricsEnabled, isTrue);
      expect(notifier.verifyPin('4321'), isTrue);
    });

    test('disable czyści PIN i biometrię', () async {
      SharedPreferences.setMockInitialValues({
        'app_lock_pin_hash': hashPin('4321'),
        'app_lock_biometrics': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appLockSettingsProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      await notifier.disable();
      final s = container.read(appLockSettingsProvider);
      expect(s.enabled, isFalse);
      expect(s.biometricsEnabled, isFalse);
    });
  });

  group('appLockedProvider', () {
    test('startuje zablokowany; unlock/lock przełączają', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appLockedProvider), isTrue);
      container.read(appLockedProvider.notifier).unlock();
      expect(container.read(appLockedProvider), isFalse);
      container.read(appLockedProvider.notifier).lock();
      expect(container.read(appLockedProvider), isTrue);
    });
  });
}
