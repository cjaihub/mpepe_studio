import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/oneova_language_service.dart';
import '../theme/app_theme.dart';

/// Modal bottom sheet that provides auto language detection, 1-tap translation,
/// AI text polish, speech playback (TTS), and text actions for any [TextEditingController].
class OneovaLanguageActionSheet extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onTextChanged;
  final VoidCallback? onCleared;

  const OneovaLanguageActionSheet({
    super.key,
    required this.controller,
    this.onTextChanged,
    this.onCleared,
  });

  static Future<void> show(
    BuildContext context, {
    required TextEditingController controller,
    ValueChanged<String>? onTextChanged,
    VoidCallback? onCleared,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => OneovaLanguageActionSheet(
        controller: controller,
        onTextChanged: onTextChanged,
        onCleared: onCleared,
      ),
    );
  }

  @override
  State<OneovaLanguageActionSheet> createState() => _OneovaLanguageActionSheetState();
}

class _OneovaLanguageActionSheetState extends State<OneovaLanguageActionSheet> {
  late DetectedLanguage _detected;
  late String _targetLanguageCode;
  String _translatedText = '';
  bool _isTranslating = false;
  bool _isPolishing = false;
  bool _isPlayingTts = false;

  @override
  void initState() {
    super.initState();
    _detected = OneovaLanguageService.instance.detectLanguage(widget.controller.text);
    // If detected is English, default target is Swahili (or French); otherwise English.
    _targetLanguageCode = _detected.code == 'en' ? 'sw' : 'en';
    _performTranslate();
  }

  @override
  void dispose() {
    OneovaLanguageService.instance.stopSpeaking();
    super.dispose();
  }

  Future<void> _performTranslate() async {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isTranslating = true);
    try {
      final res = await OneovaLanguageService.instance.translateText(
        text,
        targetLanguageCode: _targetLanguageCode,
        sourceLanguageCode: _detected.code,
      );
      if (mounted) {
        setState(() {
          _translatedText = res;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _translatedText = text);
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  Future<void> _performPolish(String tone) async {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPolishing = true);
    HapticFeedback.selectionClick();
    try {
      final polished = await OneovaLanguageService.instance.polishText(text, tone: tone);
      if (mounted) {
        widget.controller.text = polished;
        widget.controller.selection = TextSelection.collapsed(offset: polished.length);
        widget.onTextChanged?.call(polished);
        setState(() {
          _detected = OneovaLanguageService.instance.detectLanguage(polished);
        });
        _performTranslate();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Applied $tone polish to text!', style: GoogleFonts.inter(fontSize: 12)),
            backgroundColor: AppColors.brandBlue,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPolishing = false);
    }
  }

  void _applyTranslation() {
    if (_translatedText.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    widget.controller.text = _translatedText;
    widget.controller.selection = TextSelection.collapsed(offset: _translatedText.length);
    widget.onTextChanged?.call(_translatedText);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Translation applied to field!', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: AppColors.brandBlue,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleTts(String textToSpeak, String langCode) async {
    HapticFeedback.lightImpact();
    if (_isPlayingTts) {
      await OneovaLanguageService.instance.stopSpeaking();
      setState(() => _isPlayingTts = false);
    } else {
      setState(() => _isPlayingTts = true);
      await OneovaLanguageService.instance.speak(textToSpeak, languageCode: langCode);
      if (mounted) setState(() => _isPlayingTts = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard!', style: GoogleFonts.inter(fontSize: 12)),
        backgroundColor: AppColors.brandBlue,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearField() {
    HapticFeedback.mediumImpact();
    final prev = widget.controller.text;
    widget.controller.clear();
    widget.onTextChanged?.call('');
    widget.onCleared?.call();
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Field cleared', style: GoogleFonts.inter(fontSize: 12)),
        backgroundColor: AppColors.darkSurface,
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppColors.brandPink,
          onPressed: () {
            widget.controller.text = prev;
            widget.controller.selection = TextSelection.collapsed(offset: prev.length);
            widget.onTextChanged?.call(prev);
          },
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final originalText = widget.controller.text.trim();
    final targetLang = OneovaLanguageService.findLanguage(_targetLanguageCode);

    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      padding: EdgeInsets.only(
        top: 14,
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Top Header: Detected Language & Top Actions
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_detected.flag, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        'Detected: ${_detected.name}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandBlue,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${(_detected.confidence * 100).toInt()}%)',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Speak Button
                IconButton(
                  tooltip: _isPlayingTts ? 'Stop audio' : 'Listen with Speech',
                  icon: Icon(
                    _isPlayingTts ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                    size: 20,
                    color: _isPlayingTts ? AppColors.brandPink : AppColors.brandBlue,
                  ),
                  onPressed: originalText.isEmpty
                      ? null
                      : () => _toggleTts(originalText, _detected.code),
                ),
                // Copy Button
                IconButton(
                  tooltip: 'Copy text',
                  icon: Icon(Icons.copy_rounded, size: 18, color: context.textSecondary),
                  onPressed: originalText.isEmpty
                      ? null
                      : () => _copyToClipboard(originalText, 'Original text'),
                ),
                // Clear Button
                IconButton(
                  tooltip: 'Clear field',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.brandPink),
                  onPressed: originalText.isEmpty ? null : _clearField,
                ),
                // Close Sheet
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 20, color: context.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Original Text Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'CURRENT INPUT',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: context.textMuted, letterSpacing: 0.6),
                      ),
                      const Spacer(),
                      Text(
                        '${originalText.length} chars',
                        style: GoogleFonts.inter(fontSize: 10, color: context.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    originalText.isEmpty ? '(No text entered yet)' : originalText,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: originalText.isEmpty ? context.textMuted : context.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Translation Section
            Row(
              children: [
                const Icon(Icons.translate_rounded, size: 16, color: AppColors.brandBlue),
                const SizedBox(width: 6),
                Text(
                  'TRANSLATE TO',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.brandBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Target Language Picker Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: OneovaLanguageService.supportedLanguages.map((lang) {
                  final isSelected = lang.code == _targetLanguageCode;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${lang.flag} ${lang.name}'),
                      selected: isSelected,
                      selectedColor: AppColors.brandBlue,
                      backgroundColor: context.surfaceMid,
                      labelStyle: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : context.textPrimary,
                      ),
                      side: BorderSide(color: isSelected ? AppColors.brandBlue : context.border, width: 1.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
                      onSelected: (selected) {
                        if (selected && _targetLanguageCode != lang.code) {
                          HapticFeedback.selectionClick();
                          setState(() => _targetLanguageCode = lang.code);
                          _performTranslate();
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),

            // Translated Result Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.25), width: 1.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${targetLang.flag} ${targetLang.name.toUpperCase()} TRANSLATION',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.brandBlue, letterSpacing: 0.6),
                      ),
                      const Spacer(),
                      if (_isTranslating)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                        )
                      else ...[
                        InkWell(
                          onTap: () => _toggleTts(_translatedText, targetLang.code),
                          child: const Icon(Icons.volume_up_rounded, size: 16, color: AppColors.brandBlue),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _copyToClipboard(_translatedText, 'Translation'),
                          child: Icon(Icons.copy_rounded, size: 15, color: context.textSecondary),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isTranslating ? 'Translating via Oneova AI…' : (_translatedText.isEmpty ? '(Translating…)' : _translatedText),
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_isTranslating || _translatedText.trim().isEmpty) ? null : _applyTranslation,
                      icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                      label: Text(
                        'Replace Field with ${targetLang.name} Translation',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // AI Text Polish & Tone Section
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.brandPink),
                const SizedBox(width: 6),
                Text(
                  'AI POLISH & TONE TIDY',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.brandPink,
                  ),
                ),
                if (_isPolishing) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPink),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildToneChip(title: 'Studio Polish ✨', tone: 'studio'),
                _buildToneChip(title: 'Friendly 😊', tone: 'friendly'),
                _buildToneChip(title: 'Concise ✂️', tone: 'concise'),
                _buildToneChip(title: 'Professional 💼', tone: 'professional'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToneChip({required String title, required String tone}) {
    return ActionChip(
      label: Text(title),
      backgroundColor: context.surfaceMid,
      labelStyle: GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: context.textPrimary,
      ),
      side: BorderSide(color: context.border, width: 1.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
      onPressed: _isPolishing ? null : () => _performPolish(tone),
    );
  }
}

