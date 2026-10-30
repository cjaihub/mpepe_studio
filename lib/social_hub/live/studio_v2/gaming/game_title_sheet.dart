// LIVE STUDIO v2 — Game Live: "What are you playing?" sheet.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../theme/live_studio_tokens.dart';

/// Quick picks. "Other" clears the field and focuses it.
const List<String> kGameQuickPicks = ['Ludo', 'Free Fire', 'PUBG Mobile', 'eFootball', 'Call of Duty Mobile'];
const String kGameOtherChip = 'Other';

/// Asks for the game title. Returns the trimmed title (1–60 chars), or null
/// when the sheet is dismissed.
Future<String?> showGameTitleSheet(BuildContext context, {String initial = ''}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LiveStudioAccent.clear,
      builder: (_) => GameTitleSheet(initial: initial),
    );

class GameTitleSheet extends StatefulWidget {
  const GameTitleSheet({super.key, this.initial = ''});
  final String initial;

  static const Key fieldKey = ValueKey('game-title-field');
  static const Key startKey = ValueKey('game-title-start');

  @override
  State<GameTitleSheet> createState() => _GameTitleSheetState();
}

class _GameTitleSheetState extends State<GameTitleSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _value => _text.text.trim();

  void _pick(String chip) {
    if (chip == kGameOtherChip) {
      _text.clear();
      _focus.requestFocus();
      return;
    }
    _text.text = chip;
    _text.selection = TextSelection.collapsed(offset: chip.length);
  }

  void _submit() {
    if (_value.isEmpty) return;
    Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    const t = LiveStudioTokens.dark;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [t.drawerTop, t.drawerBottom],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: t.drawerBorder),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: t.ghostBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.sports_esports, color: LiveStudioAccent.pink, size: 22),
              const SizedBox(width: 8),
              Text('What are you playing?', style: LiveStudioType.s(17, FontWeight.w700, t.textHigh, height: 22)),
            ]),
            const SizedBox(height: 14),
            TextField(
              key: GameTitleSheet.fieldKey,
              controller: _text,
              focusNode: _focus,
              maxLength: kGameTitleMaxLength,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u001F\u007F-\u009F]'))],
              onSubmitted: (_) => _submit(),
              style: LiveStudioType.s(15, FontWeight.w500, t.textHigh, height: 20),
              cursorColor: LiveStudioAccent.pink,
              decoration: InputDecoration(
                hintText: 'Game title',
                hintStyle: LiveStudioType.s(15, FontWeight.w400, t.placeholder, height: 20),
                counterStyle: LiveStudioType.s(11, FontWeight.w400, t.textDim, height: 14),
                filled: true,
                fillColor: t.ghostFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: t.ghostBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: t.ghostBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: LiveStudioAccent.pink),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in [...kGameQuickPicks, kGameOtherChip])
                _Chip(label: g, selected: g != kGameOtherChip && _value == g, tokens: t, onTap: () => _pick(g)),
            ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: GameTitleSheet.startKey,
                  borderRadius: BorderRadius.circular(9999),
                  onTap: _value.isEmpty ? null : _submit,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: _value.isEmpty
                          ? null
                          : const LinearGradient(colors: [LiveStudioAccent.pink, LiveStudioAccent.pinkLight]),
                      color: _value.isEmpty ? t.ghostFill : null,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Center(
                      child: Text('Go live with this game',
                          style: LiveStudioType.s(15, FontWeight.w700,
                              _value.isEmpty ? t.textDim : LiveStudioAccent.white, height: 20)),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.tokens, required this.onTap});
  final String label;
  final bool selected;
  final LiveStudioTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(9999),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? LiveStudioAccent.pinkA(0.18) : t.modeIdleFill,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: selected ? LiveStudioAccent.pink : t.modeIdleBorder),
            ),
            child: Text(label,
                style: LiveStudioType.s(13, FontWeight.w600, selected ? t.textHigh : t.modeIdleText, height: 18)),
          ),
        ),
      ),
    );
  }
}
