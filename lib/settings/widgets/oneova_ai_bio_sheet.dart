import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/oneova_voice_typing_button.dart';

enum AiBioTone {
  viral('⚡ Viral & Punchy', 'High-energy, emojis, catchy hook, and high distribution'),
  executive('💼 Executive & Pro', 'Authoritative, clear value proposition, and achievements'),
  creative('🎨 Creative & Aesthetic', 'Expressive, artistic style, vision, and atmospheric'),
  minimal('✨ Minimal & Clean', 'Sleek, short 1-line statement with impactful simplicity');

  final String label;
  final String description;
  const AiBioTone(this.label, this.description);
}

class OneovaAiBioSheet extends StatefulWidget {
  final String currentDisplayName;
  final String currentUsername;
  final String currentCategory;
  final String accountType;
  final String location;
  final String pronouns;
  final String currentBio;
  final ValueChanged<String> onBioSelected;

  const OneovaAiBioSheet({
    super.key,
    required this.currentDisplayName,
    required this.currentUsername,
    required this.currentCategory,
    required this.accountType,
    required this.location,
    required this.pronouns,
    required this.currentBio,
    required this.onBioSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required String currentDisplayName,
    required String currentUsername,
    required String currentCategory,
    required String accountType,
    required String location,
    required String pronouns,
    required String currentBio,
    required ValueChanged<String> onBioSelected,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => OneovaAiBioSheet(
        currentDisplayName: currentDisplayName,
        currentUsername: currentUsername,
        currentCategory: currentCategory,
        accountType: accountType,
        location: location,
        pronouns: pronouns,
        currentBio: currentBio,
        onBioSelected: onBioSelected,
      ),
    );
  }

  static String sanitizeBio(String raw) {
    var clean = raw.trim().replaceAll(RegExp(r'^"+|"+$'), '').replaceAll('\n\n\n', '\n');
    if (clean.length > 150) {
      clean = '${clean.substring(0, 147).trimRight()}…';
    }
    return clean;
  }

  static List<String> buildLocalSuggestions({
    required String name,
    required String category,
    required String location,
    required AiBioTone tone,
    required String keywords,
    required String pronouns,
  }) {
    final locTag = location.isNotEmpty ? ' 📍 $location' : '';
    final proTag = pronouns.isNotEmpty ? ' ($pronouns)' : '';
    final kwTag = keywords.isNotEmpty ? ' • $keywords' : '';

    switch (tone) {
      case AiBioTone.viral:
        return [
          sanitizeBio('Creating the future of $category 🔥$proTag\nJoin the wave$locTag\nDrop a follow for daily drops 🚀$kwTag'),
          sanitizeBio('⚡ $name | $category$proTag\nOriginal sounds, unfiltered cuts$kwTag\nTap in & stay inspired$locTag'),
          sanitizeBio('Redefining $category on Oneova 🌟\nWatch till the end$kwTag$locTag\nDM for collabs 📩'),
          sanitizeBio('Welcome to my studio ✨ $category creator$proTag\nDaily vibes$locTag$kwTag\nHit follow & grow with us!'),
        ];
      case AiBioTone.executive:
        return [
          sanitizeBio('$name | $category Specialist$proTag\nBuilding media, distribution & value$locTag$kwTag\nInquiries & partnerships below 🌐'),
          sanitizeBio('Official $name$proTag$locTag\n$category • Content Strategy$kwTag\nTransforming creative work into scalable impact.'),
          sanitizeBio('$category Professional$locTag\nCurating high-grade visuals & audio$kwTag\nVerified Oneova Creator 💼'),
          sanitizeBio('Executive $category Creator$proTag\nInnovating modern production$locTag$kwTag\nCollaborate: links below 🔗'),
        ];
      case AiBioTone.creative:
        return [
          sanitizeBio('✨ $name$proTag • Exploring light, sound & $category\nCrafting cinematic moments$locTag$kwTag\nVisual diary on Oneova 🎞️'),
          sanitizeBio('Where $category meets soul 🎨$locTag\nRaw takes, deliberate aesthetics$kwTag\nCreating without permission ✨'),
          sanitizeBio('Sound & visual artisan$proTag\nDeep in $category$kwTag$locTag\nTurn sound on & immerse 🎧'),
          sanitizeBio('Aesthetic archives of $name 💫\n$category narrative$locTag$kwTag\nWelcome to my digital gallery.'),
        ];
      case AiBioTone.minimal:
        return [
          sanitizeBio('$name • $category$locTag$proTag\n$keywords'.trim()),
          sanitizeBio('$category in motion.$locTag$kwTag'),
          sanitizeBio('Creating what’s next in $category.$locTag'),
          sanitizeBio('$name$proTag | $category$locTag'),
        ];
    }
  }

  @override
  State<OneovaAiBioSheet> createState() => _OneovaAiBioSheetState();
}

class _OneovaAiBioSheetState extends State<OneovaAiBioSheet> {
  final _keywordsController = TextEditingController();
  AiBioTone _selectedTone = AiBioTone.viral;
  bool _isLoading = false;
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _generateBios();
  }

  @override
  void dispose() {
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _generateBios() async {
    setState(() {
      _isLoading = true;
    });

    final name = widget.currentDisplayName.trim().isNotEmpty
        ? widget.currentDisplayName.trim()
        : 'Creator';
    final category = widget.currentCategory.trim().isNotEmpty
        ? widget.currentCategory.trim()
        : 'Digital Creator';
    final location = widget.location.trim();
    final customKeywords = _keywordsController.text.trim();

    // 1. Attempt online generation via Cloud Function (Ova Gemini)
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('suggestProfileDetails')
          .call<Map<String, dynamic>>({
        'lang': 'en',
        'displayName': name,
        'category': category,
        'tone': _selectedTone.name,
        'location': location,
        'keywords': customKeywords,
      }).timeout(const Duration(seconds: 4));

      final remoteList = (res.data['bios'] as List? ?? const [])
          .whereType<String>()
          .where((b) => b.trim().isNotEmpty)
          .toList();

      if (remoteList.isNotEmpty && mounted) {
        setState(() {
          _suggestions = remoteList.take(4).map(OneovaAiBioSheet.sanitizeBio).toList();
          _isLoading = false;
        });
        return;
      }
    } catch (_) {
      // Fallback gracefully to smart local contextual generation
    }

    // 2. Local AI Contextual Generator (instant, works offline or on rate-limits)
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    final generated = OneovaAiBioSheet.buildLocalSuggestions(
      name: name,
      category: category,
      location: location,
      tone: _selectedTone,
      keywords: customKeywords,
      pronouns: widget.pronouns.trim(),
    );

    setState(() {
      _suggestions = generated;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 16,
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.brandBlue, AppColors.brandPink],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Bio Assistant',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Generate tailored bios based on your category & style',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 20, color: context.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Tone Selector
          Text(
            'SELECT TONE',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AiBioTone.values.map((tone) {
                final isSelected = _selectedTone == tone;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected && _selectedTone != tone) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedTone = tone);
                        _generateBios();
                      }
                    },
                    label: Text(tone.label),
                    selectedColor: AppColors.brandBlue,
                    backgroundColor: context.surfaceMid,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : context.textPrimary,
                    ),
                    side: BorderSide(
                      color: isSelected ? AppColors.brandBlue : context.border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Custom Guidance / Keywords field
          TextField(
            controller: _keywordsController,
            style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add custom keywords (e.g. guitarist, producer, Lagos)',
              hintStyle: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
              prefixIcon: const Icon(Icons.tune_rounded, size: 16, color: AppColors.brandPink),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OneovaVoiceTypingButton(
                    controller: _keywordsController,
                    tooltip: 'Dictate guidance / keywords',
                    showTranslateAction: true,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.brandBlue),
                    tooltip: 'Regenerate',
                    onPressed: _isLoading ? null : _generateBios,
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: context.surfaceMid,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: context.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: context.border),
              ),
            ),
            onSubmitted: (_) => _generateBios(),
          ),
          const SizedBox(height: 14),

          // Suggestions List
          Text(
            'SUGGESTIONS (TAP TO APPLY)',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 8),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2.5),
                    SizedBox(height: 10),
                    Text('Ova AI is composing your creator bio…', style: TextStyle(fontSize: 12, color: AppColors.brandBlue)),
                  ],
                ),
              ),
            )
          else
            ..._suggestions.map((bio) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bio,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: context.textPrimary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${bio.length}/150 chars',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: bio.length > 150 ? AppColors.brandPink : context.textMuted,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              tooltip: 'Copy',
                              color: context.textSecondary,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: bio));
                                HapticFeedback.lightImpact();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Bio copied to clipboard!'),
                                    duration: Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton.icon(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                widget.onBioSelected(bio);
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandBlue,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: const Size(0, 28),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                ),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                              label: Text(
                                'Apply',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
