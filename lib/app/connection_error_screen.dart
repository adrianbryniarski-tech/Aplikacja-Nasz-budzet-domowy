import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nasz_budzet_domowy/features/household/application/household_providers.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Pełnoekranowy komunikat gdy przy starcie nie ma kontaktu z serwerem
/// (brak internetu, Supabase w pauzie, awaria).
///
/// Bez tego ekranu błąd sieci przy starcie wyglądał jak „brak
/// gospodarstwa" — router wypychał zalogowanego usera na onboarding
/// zakładania gospodarstwa, co myliło i kusiło do założenia duplikatu.
class ConnectionErrorScreen extends ConsumerWidget {
  const ConnectionErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final householdAsync = ref.watch(currentHouseholdIdProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  Icons.cloud_off_outlined,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 24),
                Text(
                  'Brak połączenia z serwerem',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Nie udało się pobrać danych budżetu. Sprawdź, czy masz '
                  'internet, i spróbuj ponownie. Jeśli internet działa, '
                  'serwer może mieć chwilową przerwę — wróć za parę minut.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(currentHouseholdIdProvider),
                  icon: const AppIcon(Icons.refresh),
                  label: const Text('Spróbuj ponownie'),
                ),
                if (householdAsync.hasError) ...[
                  const SizedBox(height: 24),
                  // Techniczny jednolinijkowiec — do przekazania osobie,
                  // która ogarnia serwer, gdy problem nie mija.
                  Text(
                    'Szczegóły: ${householdAsync.error}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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
