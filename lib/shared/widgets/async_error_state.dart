import 'package:flutter/material.dart';
import 'package:nasz_budzet_domowy/core/error_messages.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Jednolity stan błędu dla zakładek: ludzki komunikat (humanizeError),
/// przycisk „Spróbuj ponownie" i drobny techniczny jednolinijkowiec (do
/// przekazania osobie, która ogarnia serwer). Zastępuje trzy różne
/// stylistyki błędów, które rozjechały się po ekranach.
class AsyncErrorState extends StatelessWidget {
  const AsyncErrorState({required this.error, this.onRetry, super.key});

  final Object error;

  /// Zwykle `() => ref.invalidate(...)` na providery ekranu.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              humanizeError(error),
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const AppIcon(Icons.refresh),
                label: const Text('Spróbuj ponownie'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '$error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
