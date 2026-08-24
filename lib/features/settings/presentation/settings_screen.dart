import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/core/haptics.dart';
import 'package:nasz_budzet_domowy/core/offline/sync_providers.dart';
import 'package:nasz_budzet_domowy/core/security/app_lock.dart';
import 'package:nasz_budzet_domowy/features/animations/application/animation_settings.dart';
import 'package:nasz_budzet_domowy/features/auth/application/auth_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/application/category_providers.dart';
import 'package:nasz_budzet_domowy/features/categories/data/category.dart';
import 'package:nasz_budzet_domowy/features/dashboard/application/dashboard_v2_providers.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/features/settings/application/csv_export.dart';
import 'package:nasz_budzet_domowy/features/settings/application/theme_providers.dart';
import 'package:nasz_budzet_domowy/features/settings/presentation/reset_transactions_dialog.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/bank_notifications.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/transaction_providers.dart';
import 'package:nasz_budzet_domowy/features/transactions/application/voice_input_service.dart';
import 'package:nasz_budzet_domowy/shared/widgets/comic_shadow.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(themeVariantProvider);
    final mode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia'),
        actions: [
          IconButton(
            tooltip: 'Odśwież',
            icon: const AppIcon(Icons.refresh),
            onPressed: () {
              // Inwaliduje wszystkie hh-providers + transactions/categories.
              // Bez tego po dołączeniu żony moja apka nie wiedziała.
              ref
                ..invalidate(currentHouseholdIdProvider)
                ..invalidate(householdInfoProvider)
                ..invalidate(householdMembersProvider)
                ..invalidate(householdMemberEmailsProvider)
                ..invalidate(activeInvitationsProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Odświeżam…'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text(
            'Motyw',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Wybierz styl który najbardziej Wam pasuje.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.7,
            ),
            itemCount: AppThemeVariant.values.length,
            itemBuilder: (context, index) {
              final v = AppThemeVariant.values[index];
              return _ThemePreviewCard(
                variant: v,
                isSelected: v == variant,
                onTap: () => ref.read(themeVariantProvider.notifier).set(v),
              );
            },
          ),
          if (variant == AppThemeVariant.manga) ...[
            const SizedBox(height: 20),
            Text(
              'Kolor motywu Manga',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const _MangaPaletteRow(),
          ],
          const SizedBox(height: 32),
          Text(
            'Tryb jasny / ciemny',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('Auto'),
                icon: AppIcon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Jasny'),
                icon: AppIcon(Icons.light_mode),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Ciemny'),
                icon: AppIcon(Icons.dark_mode),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 32),
          Text(
            'Pulpit',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const _DashboardV2Tile(),
          const SizedBox(height: 32),
          Text(
            'Gospodarstwo',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Wszyscy członkowie tego gospodarstwa widzą te same transakcje. '
            'Jeśli Twojej żony/męża nie ma na liście — to znaczy że nie '
            'dołączyła/dołączył do tego samego gospodarstwa.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          const _HouseholdInfoCard(),
          const SizedBox(height: 32),
          Text(
            'Animacje',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Każdą można wyłączyć osobno gdy ktoś woli czysty interfejs.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ...AppAnimation.values.map(
            (a) => _AnimationTile(animation: a),
          ),
          const _HapticsTile(),
          const SizedBox(height: 32),
          Text(
            'Sterowanie głosem',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Dyktowanie wydatków działa offline dzięki polskiemu modelowi '
            'Vosk (~50 MB). Pobierz go raz — potem mikrofon na ekranie nowej '
            'transakcji będzie aktywny.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          const _VoiceModelCard(),
          const SizedBox(height: 32),
          Text(
            'Import z banku',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const _BankListenerCard(),
          const SizedBox(height: 32),
          Text(
            'Transakcje cykliczne',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ComicCard(
            child: ListTile(
              leading: const AppIcon(Icons.event_repeat),
              title: const Text('Czynsz, abonamenty, wypłata…'),
              subtitle: const Text(
                'Stałe wpisy dopisują się same w wybranym dniu miesiąca.',
              ),
              trailing: const AppIcon(Icons.chevron_right),
              onTap: () => context.push('/recurring'),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Bezpieczeństwo',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const _AppLockCard(),
          const SizedBox(height: 32),
          Text(
            'Twoje dane',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const _ExportCsvCard(),
          const SizedBox(height: 8),
          const _ResetTransactionsCard(),
          const SizedBox(height: 32),
          Text(
            'Info',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ComicCard(
            child: ListTile(
              leading: const AppIcon(Icons.help_outline),
              title: const Text('Pomoc — jak to działa'),
              subtitle: const Text(
                'Instrukcja krok po kroku: łączenie z partnerem, '
                'voice, budżety…',
              ),
              trailing: const AppIcon(Icons.chevron_right),
              onTap: () => context.push('/help'),
            ),
          ),
          const SizedBox(height: 8),
          ComicCard(
            child: ListTile(
              leading: const AppIcon(Icons.auto_awesome_outlined),
              title: const Text('Co nowego'),
              subtitle: const Text(
                'Co się zmieniło w ostatnich aktualizacjach.',
              ),
              trailing: const AppIcon(Icons.chevron_right),
              onTap: () => context.push('/whats-new'),
            ),
          ),
          const SizedBox(height: 8),
          ComicCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Aplikacja: Nasz budżet domowy\n'
                'Dla rodziny Bryniarskich (Adrian + Andzia + córeczka)\n'
                'Wszystko AB.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kafelek z miniaturką motywu — pokazuje paletę kolorów + nazwę.
/// Stuknięcie ustawia ten motyw.
class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    required this.variant,
    required this.isSelected,
    required this.onTap,
  });

  final AppThemeVariant variant;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Budujemy "miniaturkę" używając tego samego buildera co prawdziwy
    // motyw — dla light brightness (preview ma być czytelny niezależnie
    // od aktualnego trybu apki).
    final preview = AppTheme.light(variant);
    final scheme = preview.colorScheme;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: preview.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 3 kolorowe kółka pokazujące paletę
            Row(
              children: [
                _Dot(color: scheme.primary),
                const SizedBox(width: 5),
                _Dot(color: scheme.secondary),
                const SizedBox(width: 5),
                _Dot(color: scheme.tertiary),
                const Spacer(),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              variant.label,
              style: preview.textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              variant.description,
              style: preview.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Rząd próbek kolorów akcentu dla motywu „Manga".
class _MangaPaletteRow extends ConsumerWidget {
  const _MangaPaletteRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(mangaPaletteProvider);
    final ink = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        for (final p in MangaPalette.values)
          Builder(
            builder: (context) {
              // Kolor wyróżniający: Błękit = tło, reszta = akcent.
              final swatch = p.background == const Color(0xFFFFFFFF)
                  ? p.accent
                  : p.background;
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: GestureDetector(
                  onTap: () => ref.read(mangaPaletteProvider.notifier).set(p),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: swatch,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ink,
                            width: selected == p ? 3.5 : 1.5,
                          ),
                        ),
                        child: selected == p
                            ? Icon(
                                Icons.check,
                                color: _onAccent(swatch),
                                size: 22,
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // Czarny lub biały „ptaszek" zależnie od jasności akcentu.
  Color _onAccent(Color c) =>
      c.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

class _HouseholdInfoCard extends ConsumerWidget {
  const _HouseholdInfoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final householdAsync = ref.watch(currentHouseholdIdProvider);
    final currentUser = ref.watch(currentUserProvider);

    return householdAsync.when(
      loading: () => const ComicCard(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => ComicCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            humanizeError(e),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ),
      data: (householdId) {
        if (householdId == null) {
          return const ComicCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nie należysz do żadnego gospodarstwa.'),
            ),
          );
        }
        final infoAsync = ref.watch(householdInfoProvider(householdId));
        final membersAsync = ref.watch(householdMembersProvider(householdId));
        final emails =
            ref.watch(householdMemberEmailsProvider(householdId)).value ??
                const <String, String>{};
        return ComicCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kvRow(
                  context,
                  label: 'Nazwa',
                  value: infoAsync.value?.name ?? '—',
                ),
                const SizedBox(height: 8),
                _kvRow(
                  context,
                  label: 'ID gospodarstwa',
                  value: householdId,
                  copyable: true,
                ),
                const SizedBox(height: 8),
                _kvRow(
                  context,
                  label: 'Twój user ID',
                  value: currentUser?.id ?? '—',
                  copyable: true,
                ),
                const SizedBox(height: 8),
                _kvRow(
                  context,
                  label: 'Twój email',
                  value: currentUser?.email ?? '—',
                ),
                const Divider(height: 32),
                Text(
                  'Członkowie',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                membersAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  ),
                  error: (e, _) => Text(
                    humanizeError(e),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  data: (members) {
                    if (members.isEmpty) {
                      return const Text('Brak członków (?)');
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final m in members)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  m.isOwner ? Icons.star : Icons.person_outline,
                                  size: 18,
                                  color: m.isOwner
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    emails[m.userId] ?? m.userId,
                                    style: emails.containsKey(m.userId)
                                        ? theme.textTheme.bodyMedium
                                        : theme.textTheme.bodySmall?.copyWith(
                                            fontFamily: 'monospace',
                                          ),
                                  ),
                                ),
                                Text(
                                  m.isOwner ? 'owner' : 'member',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            members.length == 1
                                ? 'Tylko Ty jesteś w tym gospodarstwie. '
                                    'Żona musi się dołączyć przez kod '
                                    'zaproszenia (zakładka Pulpit → 👤+).'
                                : 'W gospodarstwie ${members.length} '
                                    'członków — transakcje są wspólne.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _confirmLeave(context, ref, householdId),
                          icon: const AppIcon(Icons.logout),
                          label: const Text('Opuść gospodarstwo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLeave(
    BuildContext context,
    WidgetRef ref,
    String householdId,
  ) async {
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Opuścić gospodarstwo?'),
        content: const Text(
          'Stracisz dostęp do transakcji tego gospodarstwa. '
          'Po opuszczeniu wrócisz do ekranu onboardingu — możesz tam '
          'wpisać kod zaproszenia do innego gospodarstwa albo stworzyć '
          'nowe.\n\n'
          'Transakcje pozostają w gospodarstwie — pozostali członkowie '
          'nadal je widzą. Jeśli byłeś jedynym członkiem, gospodarstwo '
          'pozostaje niewidoczne (nikogo w nim nie ma).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Opuść'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final goRouter = GoRouter.of(context);
    try {
      await ref.read(householdRepositoryProvider).leaveHousehold(householdId);
      // Inwaliduje WSZYSTKIE hh providers, żeby router wykrył brak hh
      // i nie pokazywał starych członków.
      ref
        ..invalidate(currentHouseholdIdProvider)
        ..invalidate(householdInfoProvider)
        ..invalidate(householdMembersProvider)
        ..invalidate(householdMemberEmailsProvider)
        ..invalidate(activeInvitationsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Opuszczono gospodarstwo.')),
      );
      // Zamiast wracać na onboarding-choice, idziemy bezpośrednio na
      // formularz wpisania kodu (najczęstszy scenariusz: user opuścił
      // żeby się przenieść do innego gospodarstwa).
      goRouter.go('/onboarding/join');
    } on PostgrestException catch (e) {
      // Najczęściej: function nie istnieje (42883) — migracja 0004
      // nieaplikowana. Pokazujemy konkretny error code/message.
      messenger.showSnackBar(
        SnackBar(
          content: Text('Nie udało się opuścić: ${e.code ?? "?"} ${e.message}'),
          duration: const Duration(seconds: 6),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Nie udało się opuścić: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Widget _kvRow(
    BuildContext context, {
    required String label,
    required String value,
    bool copyable = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: copyable ? 'monospace' : null,
            ),
          ),
        ),
        if (copyable)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            padding: EdgeInsets.zero,
            tooltip: 'Kopiuj',
            icon: const AppIcon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
            },
          ),
      ],
    );
  }
}

/// Karta pobierania/statusu modelu głosowego Vosk. Słucha singletona
/// [VoiceInputService] (ChangeNotifier, nie Riverpod) i pokazuje postęp.
class _VoiceModelCard extends StatefulWidget {
  const _VoiceModelCard();

  @override
  State<_VoiceModelCard> createState() => _VoiceModelCardState();
}

class _VoiceModelCardState extends State<_VoiceModelCard> {
  final _service = VoiceInputService.instance;

  @override
  void initState() {
    super.initState();
    // Odśwież status (model mógł zostać pobrany wcześniej).
    _service
      ..addListener(_rebuild)
      ..init();
  }

  @override
  void dispose() {
    _service.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _service.status;

    if (status == VoiceStatus.ready) {
      return ComicCard(
        child: ListTile(
          leading: AppIcon(Icons.check_circle, color: cs.primary),
          title: const Text('Model gotowy'),
          subtitle: const Text(
            'Mikrofon na ekranie nowej transakcji jest aktywny.',
          ),
        ),
      );
    }

    if (_service.isDownloading || status == VoiceStatus.loading) {
      final progress = _service.downloadProgress;
      final isExtracting = status == VoiceStatus.loading || progress == 1;
      final label = isExtracting
          ? 'Rozpakowywanie i ładowanie…'
          : progress == null
              ? 'Pobieranie…'
              : 'Pobieranie… ${(progress * 100).round()}%';
      return ComicCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: isExtracting ? null : progress,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
      );
    }

    // unavailable — przycisk pobierania (+ ewentualny błąd).
    return ComicCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_service.downloadError != null) ...[
              Row(
                children: [
                  AppIcon(Icons.error_outline, color: cs.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _service.downloadError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _service.downloadModel,
              icon: const AppIcon(Icons.download),
              label: Text(
                _service.downloadError != null
                    ? 'Spróbuj ponownie'
                    : 'Pobierz model głosowy (~50 MB)',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pobieranie tylko przez Wi-Fi zalecane. Model zostaje na '
              'telefonie — działa bez internetu.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Przełącznik nowego pulpitu (bento 2026): karta „Zostało do wydania"
/// z podpowiedzią dzienną, budżety z ringiem, trend, top kategorie,
/// nadchodzące płatności i ostatnie transakcje w jednym widoku.
class _DashboardV2Tile extends ConsumerWidget {
  const _DashboardV2Tile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(dashboardV2EnabledProvider);
    return ComicCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: SwitchListTile(
        value: enabled,
        onChanged: (v) => ref
            .read(dashboardV2EnabledProvider.notifier)
            .setEnabled(enabled: v),
        title: const Text('Nowy pulpit (beta)'),
        subtitle: const Text(
          'Świeży układ: ile zostało do wydania (z podpowiedzią „ile '
          'dziennie"), budżety, trend, top kategorie, nadchodzące '
          'płatności i ostatnie transakcje. Włącza też pasujący motyw '
          '„Neo" (poprzedni wróci po wyłączeniu; motyw możesz zmienić '
          'jak zwykle).',
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

/// Włącznik delikatnych wibracji przy akcjach (zapis, usunięcie, zmiana
/// zakładki). Osobno od animacji wizualnych — nie każdy lubi haptykę.
class _HapticsTile extends ConsumerWidget {
  const _HapticsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(hapticsEnabledProvider);
    return ComicCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: SwitchListTile(
        value: enabled,
        onChanged: (v) =>
            ref.read(hapticsEnabledProvider.notifier).setEnabled(enabled: v),
        title: const Text('Wibracje przy akcjach'),
        subtitle: const Text(
          'Delikatne „kliknięcie" przy zapisie, usuwaniu i zmianie zakładki.',
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

class _AnimationTile extends ConsumerWidget {
  const _AnimationTile({required this.animation});
  final AppAnimation animation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(animationSettingsProvider);
    final enabled = settings.isOn(animation);
    return ComicCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: SwitchListTile(
        value: enabled,
        onChanged: (v) => ref
            .read(animationSettingsProvider.notifier)
            .set(animation, enabled: v),
        title: Text(animation.label),
        subtitle: Text(animation.description),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

/// Przełącznik nasłuchu powiadomień bankowych (beta): apka czyta
/// powiadomienia IKO / Moje ING / Revolut i podpowiada wydatki do
/// zatwierdzenia na liście Transakcji. Wymaga systemowego dostępu do
/// powiadomień — Android pokaże osobny ekran zgody.
class _BankListenerCard extends ConsumerWidget {
  const _BankListenerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(bankListenerEnabledProvider);
    final theme = Theme.of(context);
    return ComicCard(
      child: SwitchListTile(
        value: enabled,
        secondary: const AppIcon(Icons.notifications_active_outlined),
        title: const Text('Propozycje z powiadomień banku (beta)'),
        subtitle: Text(
          'Płatność kartą (też przez Portfel Google) albo powiadomienie '
          'z PKO BP / ING / Revolut od razu pojawi się jako propozycja '
          'wydatku do zatwierdzenia (baner na liście Transakcji). '
          'Wszystko zostaje na telefonie.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        onChanged: (value) async {
          final notifier = ref.read(bankListenerEnabledProvider.notifier);
          final controller = ref.read(bankListenerControllerProvider);
          if (!value) {
            await notifier.setEnabled(enabled: false);
            return;
          }
          await notifier.setEnabled(enabled: true);
          if (!await controller.isPermissionGranted()) {
            // Android otwiera systemowy ekran „Dostęp do powiadomień" —
            // trzeba tam zaznaczyć naszą apkę.
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Zaznacz „Nasz budżet domowy" na liście, która się '
                    'otworzy — bez tego Android nie przekaże powiadomień.',
                  ),
                  duration: Duration(seconds: 5),
                ),
              );
            }
            await controller.requestPermission();
            await controller.syncWithSettings();
          }
        },
      ),
    );
  }
}

/// Blokada apki PIN-em + (opcjonalnie) biometrią. PIN ustawia się przy
/// włączaniu; wyłączenie wymaga podania PIN-u.
class _AppLockCard extends ConsumerWidget {
  const _AppLockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appLockSettingsProvider);
    final theme = Theme.of(context);
    return ComicCard(
      child: Column(
        children: [
          SwitchListTile(
            value: settings.enabled,
            secondary: const AppIcon(Icons.lock_outline),
            title: const Text('Blokada apki (PIN)'),
            subtitle: Text(
              'Przy otwarciu apki (i po 2 minutach w tle) trzeba podać '
              'PIN. Chroni Wasze finanse przy pożyczaniu telefonu.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            onChanged: (value) async {
              if (value) {
                await _enableFlow(context, ref);
              } else {
                await _disableFlow(context, ref);
              }
            },
          ),
          if (settings.enabled)
            FutureBuilder<bool>(
              future: biometricsAvailable(),
              builder: (context, snap) {
                if (snap.data != true) return const SizedBox.shrink();
                return SwitchListTile(
                  value: settings.biometricsEnabled,
                  secondary: const AppIcon(Icons.fingerprint),
                  title: const Text('Odblokowanie odciskiem / twarzą'),
                  subtitle: const Text('PIN zostaje jako zapasowy.'),
                  onChanged: (v) => ref
                      .read(appLockSettingsProvider.notifier)
                      .setBiometrics(enabled: v),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _enableFlow(BuildContext context, WidgetRef ref) async {
    final pin = await _askNewPin(context);
    if (pin == null) return;
    await ref.read(appLockSettingsProvider.notifier).enable(pin);
    // Świeżo włączona blokada nie ma zaskakiwać natychmiastowym zamkiem.
    ref.read(appLockedProvider.notifier).unlock();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Blokada włączona. Nie zgub PIN-u! 🙂'),
        ),
      );
    }
  }

  Future<void> _disableFlow(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wyłączyć blokadę?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Obecny PIN',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Wyłącz'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final notifier = ref.read(appLockSettingsProvider.notifier);
    if (!notifier.verifyPin(controller.text.trim())) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zły PIN — blokada zostaje.')),
        );
      }
      return;
    }
    await notifier.disable();
  }

  /// Dialog ustawiania PIN-u: dwa pola (nowy + powtórz), 4–6 cyfr.
  Future<String?> _askNewPin(BuildContext context) async {
    final pin1 = TextEditingController();
    final pin2 = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void submit() {
            final a = pin1.text.trim();
            final b = pin2.text.trim();
            if (a.length < 4 || a.length > 6 || int.tryParse(a) == null) {
              setState(() => error = 'PIN to 4–6 cyfr.');
              return;
            }
            if (a != b) {
              setState(() => error = 'PIN-y się różnią.');
              return;
            }
            Navigator.of(ctx).pop(a);
          }

          return AlertDialog(
            title: const Text('Ustaw PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pin1,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Nowy PIN (4–6 cyfr)',
                    counterText: '',
                  ),
                ),
                TextField(
                  controller: pin2,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Powtórz PIN',
                    counterText: '',
                    errorText: error,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Anuluj'),
              ),
              FilledButton(onPressed: submit, child: const Text('Zapisz')),
            ],
          );
        },
      ),
    );
  }
}

/// Eksport transakcji do pliku CSV (Excel) przez systemowe „Udostępnij".
/// „Zacznij od nowa": kasuje wszystkie transakcje gospodarstwa (chmura +
/// lokalna kolejka offline), nie ruszając inwestycji, kategorii, budżetów,
/// cyklicznych ani reguł importu. Chronione przepisaniem frazy.
class _ResetTransactionsCard extends ConsumerWidget {
  const _ResetTransactionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ComicCard(
      child: ListTile(
        leading: AppIcon(
          Icons.restart_alt,
          color: theme.colorScheme.error,
        ),
        title: Text(
          'Zacznij od nowa (usuń wszystkie wpisy)',
          style: TextStyle(color: theme.colorScheme.error),
        ),
        subtitle: const Text(
          'Kasuje wszystkie transakcje u obojga. Inwestycje, kategorie, '
          'budżety i cykliczne zostają.',
        ),
        trailing: const AppIcon(Icons.chevron_right),
        onTap: () => _confirmAndReset(context, ref),
      ),
    );
  }

  Future<void> _confirmAndReset(BuildContext context, WidgetRef ref) async {
    final householdId = ref.read(currentHouseholdIdProvider).value;
    if (householdId == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final deleted = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ResetTransactionsDialog(
        onConfirm: () async {
          // Najpierw chmura (źródło prawdy), potem lokalna kolejka —
          // żeby niewysłane wpisy offline nie wróciły po resecie.
          final count = await ref
              .read(transactionRepositoryProvider)
              .deleteAllForHousehold(householdId);
          await ref.read(pendingOpsDaoProvider).removeForHousehold(
                householdId,
              );
          return count;
        },
      ),
    );
    if (deleted == null) return;

    ref.invalidate(transactionsProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          deleted == 0
              ? 'Nie było nic do usunięcia — budżet już jest pusty.'
              : 'Usunięto $deleted transakcji. Zaczynacie od nowa 🌱',
        ),
      ),
    );
  }
}

class _ExportCsvCard extends ConsumerWidget {
  const _ExportCsvCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ComicCard(
      child: ListTile(
        leading: const AppIcon(Icons.table_view_outlined),
        title: const Text('Eksport do CSV (Excel)'),
        subtitle: const Text(
          'Zapisz albo wyślij transakcje jako arkusz — np. do rozliczeń.',
        ),
        trailing: const AppIcon(Icons.chevron_right),
        onTap: () => _pickRangeAndExport(context, ref),
      ),
    );
  }

  Future<void> _pickRangeAndExport(BuildContext context, WidgetRef ref) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Co wyeksportować?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('month'),
            child: const Text('Ten miesiąc'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('all'),
            child: const Text('Wszystkie transakcje'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final all = ref.read(transactionsProvider).value;
    if (all == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Lista transakcji jeszcze się ładuje — spróbuj '
              'za chwilę.'),
        ),
      );
      return;
    }
    var txs = all;
    if (choice == 'month') {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month);
      final end = DateTime(now.year, now.month + 1);
      txs = [
        for (final t in all)
          if (!t.occurredAt.isBefore(start) && t.occurredAt.isBefore(end)) t,
      ];
    }
    if (txs.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Brak transakcji do eksportu.')),
      );
      return;
    }

    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    final csv = buildTransactionsCsv(
      txs,
      {for (final c in categories) c.id: c},
    );

    try {
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp = '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/nasz-budzet-$stamp.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Nasz budżet domowy — eksport $stamp',
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Eksport nie wyszedł: ${humanizeError(e)}')),
      );
    }
  }
}
