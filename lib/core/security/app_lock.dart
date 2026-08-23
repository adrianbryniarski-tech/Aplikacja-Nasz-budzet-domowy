import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Blokada apki: PIN (obowiązkowy fundament) + opcjonalnie biometria.
///
/// PIN nie jest przechowywany wprost — tylko SHA-256 z solą. To finansowa
/// apka domowa, nie bank: celem jest, żeby dziecko albo znajomy z
/// pożyczonym telefonem nie buszowali po budżecie, nie odporność na
/// laboratorium kryminalistyczne.
String hashPin(String pin) {
  final bytes = utf8.encode('nbd-app-lock-v1|$pin');
  return sha256.convert(bytes).toString();
}

/// Ustawienia blokady. `loaded` = odczyt z dysku zakończony (do tego
/// czasu bramka pokazuje pusty ekran zamiast mignięcia treścią).
class AppLockSettings {
  const AppLockSettings({
    required this.loaded,
    required this.pinHash,
    required this.biometricsEnabled,
  });

  final bool loaded;
  final String? pinHash;
  final bool biometricsEnabled;

  bool get enabled => pinHash != null;

  AppLockSettings copyWith({
    bool? loaded,
    String? Function()? pinHash,
    bool? biometricsEnabled,
  }) {
    return AppLockSettings(
      loaded: loaded ?? this.loaded,
      pinHash: pinHash != null ? pinHash() : this.pinHash,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
    );
  }
}

final appLockSettingsProvider =
    NotifierProvider<AppLockSettingsNotifier, AppLockSettings>(
  AppLockSettingsNotifier.new,
);

class AppLockSettingsNotifier extends Notifier<AppLockSettings> {
  static const _pinKey = 'app_lock_pin_hash';
  static const _bioKey = 'app_lock_biometrics';

  @override
  AppLockSettings build() {
    unawaited(_load());
    return const AppLockSettings(
      loaded: false,
      pinHash: null,
      biometricsEnabled: false,
    );
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AppLockSettings(
        loaded: true,
        pinHash: prefs.getString(_pinKey),
        biometricsEnabled: prefs.getBool(_bioKey) ?? false,
      );
    } on Object {
      // Uszkodzone prefs nie mogą zablokować apki na stałe.
      state = state.copyWith(loaded: true);
    }
  }

  /// Włącza blokadę z nowym PIN-em (4–6 cyfr, walidacja w UI).
  Future<void> enable(String pin) async {
    final hash = hashPin(pin);
    state = state.copyWith(pinHash: () => hash);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, hash);
  }

  Future<void> disable() async {
    state = state.copyWith(pinHash: () => null, biometricsEnabled: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
    await prefs.setBool(_bioKey, false);
  }

  Future<void> setBiometrics({required bool enabled}) async {
    state = state.copyWith(biometricsEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bioKey, enabled);
  }

  bool verifyPin(String pin) => hashPin(pin) == state.pinHash;
}

/// Czy apka jest AKTUALNIE zablokowana. Startuje jako `true` — bramka
/// odblokowuje od razu, gdy blokada okaże się wyłączona.
final appLockedProvider = NotifierProvider<AppLockedNotifier, bool>(
  AppLockedNotifier.new,
);

class AppLockedNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void unlock() => state = false;
  void lock() => state = true;
}

/// Biometria: czy telefon ją wspiera (i ma skonfigurowaną).
Future<bool> biometricsAvailable() async {
  if (kIsWeb) return false;
  try {
    final auth = LocalAuthentication();
    return await auth.isDeviceSupported() && await auth.canCheckBiometrics;
  } on Object {
    return false;
  }
}

/// Systemowy dialog biometrii. `true` = potwierdzono tożsamość.
Future<bool> authenticateWithBiometrics() async {
  if (kIsWeb) return false;
  try {
    return await LocalAuthentication().authenticate(
      localizedReason: 'Odblokuj „Nasz budżet domowy"',
      biometricOnly: true,
    );
  } on Object {
    return false;
  }
}

/// Bramka blokady — opakowuje CAŁĄ apkę (builder w MaterialApp.router).
///
/// Stany: ustawienia się ładują → pusty ekran; blokada wyłączona → treść;
/// włączona i zablokowana → ekran PIN; odblokowana → treść.
/// Po powrocie z tła po >2 min blokuje ponownie.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget? child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  static const _relockAfter = Duration(minutes: 2);
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      final settings = ref.read(appLockSettingsProvider);
      if (settings.enabled &&
          pausedAt != null &&
          DateTime.now().difference(pausedAt) > _relockAfter) {
        ref.read(appLockedProvider.notifier).lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appLockSettingsProvider);
    final locked = ref.watch(appLockedProvider);

    if (!settings.loaded) {
      // Krótki neutralny ekran zamiast mignięcia treścią przed blokadą.
      return const Scaffold(body: SizedBox.shrink());
    }
    if (!settings.enabled || !locked) {
      return widget.child ?? const SizedBox.shrink();
    }
    return const _LockScreen();
  }
}

/// Ekran odblokowania: pole PIN + (opcjonalnie) przycisk biometrii.
class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen();

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  bool _bioAvailable = false;
  bool _bioTried = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initBiometrics());
  }

  Future<void> _initBiometrics() async {
    final settings = ref.read(appLockSettingsProvider);
    if (!settings.biometricsEnabled) return;
    final available = await biometricsAvailable();
    if (!mounted) return;
    setState(() => _bioAvailable = available);
    // Od razu proponujemy odcisk — PIN zostaje jako fallback.
    if (available && !_bioTried) {
      _bioTried = true;
      await _tryBiometrics();
    }
  }

  Future<void> _tryBiometrics() async {
    final ok = await authenticateWithBiometrics();
    if (!mounted) return;
    if (ok) ref.read(appLockedProvider.notifier).unlock();
  }

  void _submitPin() {
    final notifier = ref.read(appLockSettingsProvider.notifier);
    if (notifier.verifyPin(_pinController.text.trim())) {
      ref.read(appLockedProvider.notifier).unlock();
    } else {
      setState(() => _error = 'Zły PIN — spróbuj jeszcze raz.');
      _pinController.clear();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Nasz budżet domowy',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Podaj PIN, żeby odblokować.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pinController,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••',
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _submitPin(),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submitPin,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Odblokuj'),
                ),
                if (_bioAvailable) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _tryBiometrics,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Użyj odcisku palca / twarzy'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
