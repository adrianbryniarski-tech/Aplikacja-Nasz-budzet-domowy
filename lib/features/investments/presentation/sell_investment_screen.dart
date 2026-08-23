import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';
import 'package:nasz_budzet_domowy/features/investments/application/investment_providers.dart';
import 'package:nasz_budzet_domowy/features/investments/data/investment.dart';
import 'package:nasz_budzet_domowy/features/investments/data/investment_repository.dart';
import 'package:nasz_budzet_domowy/shared/widgets/comic_shadow.dart';
import 'package:nasz_budzet_domowy/shared/widgets/inline_error.dart';
import 'package:nasz_budzet_domowy/shared/widgets/loading_filled_button.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';

/// Jak użytkownik chce wpisać wynik sprzedaży.
enum _ResultMode {
  /// Podaje kwotę, którą odzyskał (apka liczy zysk/stratę).
  proceeds,

  /// Podaje wprost samą stratę w złotówkach.
  loss,
}

/// Sprzedaż / realizacja pozycji inwestycyjnej (całości lub części).
///
/// Pozycja w portfelu zostaje — odejmujemy tylko sprzedaną ilość. Wynik
/// (zysk lub strata) trafia do historii realizacji. Można wpisać kwotę
/// odzyskaną (apka policzy wynik) albo samą stratę wprost.
class SellInvestmentScreen extends ConsumerStatefulWidget {
  const SellInvestmentScreen({required this.valuation, super.key});

  final InvestmentValuation valuation;

  @override
  ConsumerState<SellInvestmentScreen> createState() =>
      _SellInvestmentScreenState();
}

class _SellInvestmentScreenState extends ConsumerState<SellInvestmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _valueController = TextEditingController();

  DateTime _soldAt = DateTime.now();
  _ResultMode _mode = _ResultMode.proceeds;
  bool _saving = false;
  String? _error;

  Investment get _inv => widget.valuation.investment;
  double get _remaining => widget.valuation.remainingQuantity;

  @override
  void initState() {
    super.initState();
    // Domyślnie sprzedaż całości tego co zostało.
    _qtyController.text = _fmtQty(_remaining);
    // Jeśli znamy aktualny kurs — podpowiedz kwotę odzyskaną.
    final price = widget.valuation.pricePln;
    if (price != null) {
      _valueController.text = (_remaining * price).toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();

  /// Parsuje liczbę dodatnią (ilość). null = nieprawidłowa.
  double? _parsePositive(String raw) {
    final v = double.tryParse(raw.replaceAll(' ', '').replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return v;
  }

  /// Parsuje liczbę nieujemną (kwota — 0 = całkowita strata). null = błąd.
  double? _parseNonNegative(String raw) {
    final v = double.tryParse(raw.replaceAll(' ', '').replaceAll(',', '.'));
    if (v == null || v < 0) return null;
    return v;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _soldAt,
      firstDate: DateTime(2009),
      lastDate: now,
      helpText: 'Data sprzedaży',
    );
    if (picked == null || !mounted) return;
    setState(() => _soldAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final qty = _parsePositive(_qtyController.text);
    if (qty == null) {
      setState(() => _error = 'Wpisz prawidłową ilość.');
      return;
    }
    // Tolerancja na zaokrąglenia (np. 0.1+0.2 w double).
    if (qty > _remaining + 1e-9) {
      setState(
        () => _error = 'Masz tylko ${_fmtQty(_remaining)} ${_inv.unitLabel} — '
            'nie możesz sprzedać więcej.',
      );
      return;
    }

    final costBasisCents = (qty * _inv.buyPriceCents).round();
    final int proceedsCents;
    if (_mode == _ResultMode.proceeds) {
      final proceeds = _parseNonNegative(_valueController.text);
      if (proceeds == null) {
        setState(() => _error = 'Wpisz kwotę, którą odzyskałeś (może być 0).');
        return;
      }
      proceedsCents = (proceeds * 100).round();
    } else {
      final loss = _parseNonNegative(_valueController.text);
      if (loss == null) {
        setState(() => _error = 'Wpisz stratę w złotówkach.');
        return;
      }
      final lossCents = (loss * 100).round();
      if (lossCents > costBasisCents) {
        setState(
          () => _error = 'Strata nie może przekroczyć kosztu zakupu tej części '
              '(${_fmtPln(costBasisCents / 100)}).',
        );
        return;
      }
      proceedsCents = costBasisCents - lossCents;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await ref.read(investmentRepositoryProvider).recordSale(
          investment: _inv,
          quantity: qty,
          proceedsCents: proceedsCents,
          soldAt: _soldAt,
        );
    if (!mounted) return;
    switch (result) {
      case InvestmentWriteSuccess():
        ref.invalidate(pricesProvider);
        context.pop();
      case InvestmentWriteFailure(:final message):
        setState(() {
          _saving = false;
          _error = 'Nie udało się zapisać: $message';
        });
    }
  }

  String _fmtPln(double v) => NumberFormat.currency(
        locale: 'pl_PL',
        symbol: 'zł',
        decimalDigits: 2,
      ).format(v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = _inv.unitLabel;

    return Scaffold(
      appBar: AppBar(title: const Text('Sprzedaż / realizacja')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              ComicCard(
                child: ListTile(
                  title: Text(_inv.displayName),
                  subtitle: Text(
                    'Masz: ${_fmtQty(_remaining)} $unit • '
                    'kupione po ${_fmtPln(_inv.buyPricePerUnitPln)}',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Ile sprzedajesz', style: theme.textTheme.labelLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(
                      () => _qtyController.text = _fmtQty(_remaining),
                    ),
                    child: const Text('Sprzedaj wszystko'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _qtyController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _fmtQty(_remaining),
                  suffixText: unit,
                ),
                validator: (v) =>
                    _parsePositive(v ?? '') == null ? 'Wpisz ilość' : null,
              ),
              const SizedBox(height: 20),
              Text('Data sprzedaży', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const AppIcon(Icons.calendar_today_outlined, size: 18),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    DateFormat('d MMMM yyyy', 'pl_PL').format(_soldAt),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  alignment: Alignment.centerLeft,
                ),
              ),
              const SizedBox(height: 20),
              Text('Jak wpisać wynik', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<_ResultMode>(
                segments: const [
                  ButtonSegment(
                    value: _ResultMode.proceeds,
                    label: Text('Kwota odzyskana'),
                  ),
                  ButtonSegment(
                    value: _ResultMode.loss,
                    label: Text('Sama strata'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() {
                  _mode = s.first;
                  _valueController.clear();
                  // W trybie "kwota" podpowiedz wartość rynkową.
                  final price = widget.valuation.pricePln;
                  final qty = _parsePositive(_qtyController.text);
                  if (_mode == _ResultMode.proceeds &&
                      price != null &&
                      qty != null) {
                    _valueController.text = (qty * price).toStringAsFixed(2);
                  }
                }),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _valueController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _mode == _ResultMode.proceeds
                      ? 'Za ile łącznie odzyskałeś'
                      : 'Ile straciłeś',
                  hintText:
                      _mode == _ResultMode.proceeds ? 'np. 9500' : 'np. 500',
                  suffixText: 'zł',
                  helperText: _mode == _ResultMode.proceeds
                      ? 'Łączna kwota ze sprzedaży. '
                          'Wpisz 0 przy całkowitej stracie.'
                      : 'Kwota, którą straciłeś na tej części.',
                ),
                validator: (v) =>
                    _parseNonNegative(v ?? '') == null ? 'Wpisz kwotę' : null,
              ),
              const SizedBox(height: 16),
              _ResultPreview(
                mode: _mode,
                quantity: _parsePositive(_qtyController.text),
                buyPricePerUnitPln: _inv.buyPricePerUnitPln,
                value: _parseNonNegative(_valueController.text),
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                InlineError(message: _error!),
                const SizedBox(height: 16),
              ],
              LoadingFilledButton(
                label: 'Zapisz sprzedaż',
                isLoading: _saving,
                icon: Icons.check,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Podgląd wyniku sprzedaży: koszt zakupu, kwota odzyskana, wynik.
class _ResultPreview extends StatelessWidget {
  const _ResultPreview({
    required this.mode,
    required this.quantity,
    required this.buyPricePerUnitPln,
    required this.value,
  });

  final _ResultMode mode;
  final double? quantity;
  final double buyPricePerUnitPln;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 2,
    );
    if (quantity == null || value == null) {
      return const SizedBox.shrink();
    }
    final costBasis = quantity! * buyPricePerUnitPln;
    final double proceeds;
    final double result;
    if (mode == _ResultMode.proceeds) {
      proceeds = value!;
      result = proceeds - costBasis;
    } else {
      result = -value!;
      proceeds = costBasis - value!;
    }
    final positive = result >= 0;
    final color = positive ? AppTheme.incomeAccent : AppTheme.expenseAccent;

    return ComicCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PreviewRow(
              label: 'Koszt zakupu tej części',
              value: fmt.format(costBasis),
            ),
            const SizedBox(height: 4),
            _PreviewRow(
              label: 'Odzyskujesz',
              value: fmt.format(proceeds < 0 ? 0 : proceeds),
            ),
            const Divider(height: 16),
            Row(
              children: [
                Text(
                  positive ? 'Zysk' : 'Strata',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${positive ? '+' : ''}${fmt.format(result)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
