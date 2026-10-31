import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_theme.dart';

/// Which idea list to show.
enum ProfileIdeaKind { bios, usernames, interests }

/// Ideas from Ova for a profile field the person has not filled in yet
/// (callable `suggestProfileDetails`, Gemini on the server). Nothing is
/// saved here: tapping an idea hands it to [onPick] to fill the field.
class ProfileAiSuggestions extends StatefulWidget {
  const ProfileAiSuggestions({super.key, required this.kind, required this.onPick});

  final ProfileIdeaKind kind;
  final ValueChanged<String> onPick;

  @override
  State<ProfileAiSuggestions> createState() => _ProfileAiSuggestionsState();
}

class _ProfileAiSuggestionsState extends State<ProfileAiSuggestions> {
  bool _loading = false;
  String? _error;
  List<String> _ideas = const [];

  Future<void> _load() async {
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
      final res = await FirebaseFunctions.instance
          .httpsCallable('suggestProfileDetails')
          .call<Map<String, dynamic>>({'lang': lang});
      final key = widget.kind.name;
      final list = (res.data[key] as List? ?? const []).whereType<String>().toList();
      if (!mounted) return;
      setState(() {
        _ideas = list;
        if (list.isEmpty) _error = 'No ideas yet. Post something first, then try again.';
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.code) {
            'resource-exhausted' => e.message ?? 'You have used today’s ideas. Try again tomorrow.',
            'not-found' || 'unimplemented' => 'Profile ideas are coming soon.',
            _ => 'Ova could not come up with ideas right now.',
          });
    } catch (_) {
      if (mounted) setState(() => _error = 'Ova could not come up with ideas right now.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ideas.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: _loading ? null : _load,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandBlue,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.full),
                side: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.35)),
              ),
            ),
            icon: _loading
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))
                : const Icon(Icons.auto_awesome_rounded, size: 15),
            label: Text(
              _loading ? 'Thinking…' : 'Suggest ideas with Ova',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(_error!, style: TextStyle(fontSize: 11, color: context.textMuted)),
            ),
        ],
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final idea in _ideas)
          ActionChip(
            avatar: const Icon(Icons.auto_awesome_rounded, size: 13, color: AppColors.brandPink),
            label: Text(idea, style: TextStyle(fontSize: 11.5, color: context.textPrimary)),
            backgroundColor: context.surfaceMid,
            side: BorderSide(color: context.border),
            onPressed: () {
              HapticFeedback.selectionClick();
              widget.onPick(idea);
            },
          ),
      ],
    );
  }
}
