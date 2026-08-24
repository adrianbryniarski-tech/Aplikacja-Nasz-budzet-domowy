import 'package:flutter/material.dart';

/// Fraza, którą trzeba przepisać, żeby odblokować kasowanie.
const kResetPhrase = 'KASUJĘ';

/// Czy wpisana fraza odblokowuje reset (bez rozróżniania wielkości liter
/// i z tolerancją spacji — ale trzeba napisać dokładnie to słowo).
bool isResetPhraseValid(String input) =>
    input.trim().toUpperCase() == kResetPhrase;

/// Dialog „Zacznij od nowa": tłumaczy, co zniknie (wszystkie transakcje
/// obojga), co ZOSTAJE (inwestycje, kategorie, budżety, cykliczne,
/// nauczone reguły importu) i wymaga przepisania frazy [kResetPhrase],
/// zanim przycisk kasowania się odblokuje.
///
/// Samo kasowanie robi [onConfirm] (wstrzykiwane — dialog jest przez to
/// testowalny bez sieci). Dialog pokazuje kręciołek na czas operacji
/// i zamyka się z wynikiem: liczbą usuniętych wpisów albo `null` przy
/// anulowaniu/błędzie (błąd pokazuje w sobie).
class ResetTransactionsDialog extends StatefulWidget {
  const ResetTransactionsDialog({required this.onConfirm, super.key});

  /// Wykonuje reset i zwraca liczbę usuniętych transakcji.
  final Future<int> Function() onConfirm;

  @override
  State<ResetTransactionsDialog> createState() =>
      _ResetTransactionsDialogState();
}

class _ResetTransactionsDialogState extends State<ResetTransactionsDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final deleted = await widget.onConfirm();
      if (!mounted) return;
      Navigator.of(context).pop(deleted);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Nie udało się usunąć wpisów: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phraseOk = isResetPhraseValid(_controller.text);
    return AlertDialog(
      title: const Text('Zacząć budżet od nowa?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Usunie to WSZYSTKIE transakcje — u Ciebie i u drugiej osoby, '
            'z chmury i z telefonów. Tego nie da się cofnąć.\n\n'
            'Zostają nietknięte: inwestycje, kategorie, budżety (limity), '
            'płatności cykliczne i nauczone kategorie importu.\n\n'
            'Rada: najpierw zrób „Eksport do CSV" — będziesz mieć kopię.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_busy,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Przepisz: $kResetPhrase',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: phraseOk && !_busy ? _confirm : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Usuń wszystko'),
        ),
      ],
    );
  }
}
