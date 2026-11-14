import 'package:flutter/material.dart';

import '../shared/language/world_languages.dart';
import '../shared/theme/app_theme.dart';

/// Searchable list of world and local languages; returns a language code.
Future<String?> pickLanguage(BuildContext context, {String title = 'Send it in…'}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => _LanguageSheet(title: title),
  );
}

class _LanguageSheet extends StatefulWidget {
  final String title;
  const _LanguageSheet({required this.title});

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = [
      for (final l in WorldLanguages.all)
        if (q.isEmpty || l.name.toLowerCase().contains(q) || l.native.toLowerCase().contains(q) || l.code.toLowerCase() == q) l,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(widget.title, style: AppTypography.sectionTitle(context.textPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search languages',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: context.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.full), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                title: Text(list[i].native, style: AppTypography.bodyMedium(context.textPrimary)),
                subtitle: Text(list[i].name, style: AppTypography.caption(context.textMuted)),
                onTap: () => Navigator.pop(context, list[i].code),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
