import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nasz_budzet_domowy/app/router.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/core/env.dart';
import 'package:nasz_budzet_domowy/core/offline/sync_providers.dart';
import 'package:nasz_budzet_domowy/features/budgets/application/budget_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/settings/application/theme_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Env.assertConfigured();

  // Inicjalizacja danych locale dla DateFormat — bez tego polskie nazwy
  // miesięcy/dni rzucają `LocaleDataException`.
  await initializeDateFormatting('pl_PL');

  await Supabase.initialize(
    url: Env.supabaseUrl,
    // `anonKey` jest deprecated (CI z --fatal-infos by się wywalił);
    // `publishableKey` przyjmuje ten sam legacy klucz anon — w pakiecie
    // oba parametry lądują w tym samym `effectiveKey`.
    publishableKey: Env.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
  );

  runApp(const ProviderScope(child: NaszBudzetDomowyApp()));
}

class NaszBudzetDomowyApp extends ConsumerStatefulWidget {
  const NaszBudzetDomowyApp({super.key});

  @override
  ConsumerState<NaszBudzetDomowyApp> createState() =>
      _NaszBudzetDomowyAppState();
}

class _NaszBudzetDomowyAppState extends ConsumerState<NaszBudzetDomowyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Worker odpalamy raz przy starcie. Subskrypcja na connectivity
    // żyje przez cały lifecycle apki — nie ma sensu re-startować jej
    // przy każdym rebuildzie widgeta.
    ref.read(syncWorkerProvider).start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Gdy apka wraca z tła, wymuszamy odświeżenie wszystkich stream'ów.
    // Bez tego Supabase realtime subscribe może wisieć w zerwanym stanie
    // (telefon szedł w deep sleep, socket padł) — nowe wiersze od drugiego
    // małżonka nigdy nie dotrą. Re-subscribe = nowe połączenie + pierwszy
    // SELECT z aktualnym stanem.
    if (state == AppLifecycleState.resumed) {
      // Od razu spróbuj wysłać zaległą kolejkę offline. Bez tego, gdy
      // telefon był cały czas online a padał tylko serwer, kolejka
      // czekała aż do zmiany connectivity albo ręcznego tapnięcia.
      unawaited(ref.read(syncWorkerProvider).syncNow());
      ref
        ..invalidate(transactionsProvider)
        ..invalidate(categoriesProvider)
        ..invalidate(budgetsProvider)
        // hh-providers też — żeby po dołączeniu/odejściu partnera
        // członkostwo było aktualne (mimo Realtime na household_members).
        ..invalidate(currentHouseholdIdProvider)
        ..invalidate(householdInfoProvider)
        ..invalidate(householdMembersProvider)
        ..invalidate(householdMemberEmailsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final variant = ref.watch(themeVariantProvider);
    final mode = ref.watch(themeModeProvider);
    // Zestaw kolorów dla Mangi (tło + akcent); inne motywy ignorują.
    final mangaPalette = variant == AppThemeVariant.manga
        ? ref.watch(mangaPaletteProvider)
        : null;
    return MaterialApp.router(
      title: 'Nasz budżet domowy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(variant, mangaPalette: mangaPalette),
      darkTheme: AppTheme.dark(variant, mangaPalette: mangaPalette),
      themeMode: mode,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pl', 'PL'), Locale('en', 'US')],
      locale: const Locale('pl', 'PL'),
    );
  }
}
