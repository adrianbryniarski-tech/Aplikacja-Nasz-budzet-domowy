import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nasz_budzet_domowy/shared/widgets/manga_icons.dart';
import 'package:nasz_budzet_domowy/shared/widgets/material_symbol_icon.dart';

/// Grid pickera ikon Material Symbols. Lista wczytana z
/// `assets/icons/category_icons.json` — każda pozycja ma `name` (klucz do
/// [MaterialSymbolIcon.map]) i `tags` (po polsku, do search).
class IconPicker extends StatefulWidget {
  const IconPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<IconPicker> {
  List<_IconEntry> _all = const [];
  String _query = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await rootBundle.loadString('assets/icons/category_icons.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (json['icons'] as List)
        .cast<Map<String, dynamic>>()
        .map(_IconEntry.fromJson)
        .where((e) => MaterialSymbolIcon.map.containsKey(e.name))
        .toList();
    // Dedup by name (JSON ma duplikaty np. "park" 3 razy).
    final seen = <String>{};
    final deduped = <_IconEntry>[];
    for (final e in entries) {
      if (seen.add(e.name)) deduped.add(e);
    }
    if (mounted) {
      setState(() {
        _all = deduped;
        _loaded = true;
      });
    }
  }

  List<_IconEntry> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all
        .where(
          (e) => e.name.contains(q) || e.tags.any((t) => t.contains(q)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final theme = Theme.of(context);
    final filtered = _filtered;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Szukaj ikony (np. „paliwo", „kawa")',
            prefixIcon: AppIcon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'Brak wyników',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : GridView.builder(
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final e = filtered[index];
                    final isSelected = e.name == widget.selected;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => widget.onSelected(e.name),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(
                                  color: theme.colorScheme.primary,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: MaterialSymbolIcon(
                          name: e.name,
                          size: 24,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _IconEntry {
  const _IconEntry({required this.name, required this.tags});

  factory _IconEntry.fromJson(Map<String, dynamic> json) {
    return _IconEntry(
      name: json['name'] as String,
      tags: ((json['tags'] as List?) ?? const [])
          .cast<String>()
          .map((t) => t.toLowerCase())
          .toList(growable: false),
    );
  }

  final String name;
  final List<String> tags;
}
