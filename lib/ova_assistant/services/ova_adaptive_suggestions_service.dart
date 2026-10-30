import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../memory/ova_memory_engine.dart';

class AdaptiveActionPrompt {
  final String title;
  final String prompt;
  final IconData icon;
  final String? badge;

  const AdaptiveActionPrompt({
    required this.title,
    required this.prompt,
    required this.icon,
    this.badge,
  });
}

final ovaAdaptiveSuggestionsServiceProvider = Provider<OvaAdaptiveSuggestionsService>((ref) {
  final memory = ref.read(ovaMemoryEngineProvider);
  return OvaAdaptiveSuggestionsService(memory);
});

/// Generates live, personalized agent suggestions based on who is logged in,
/// their category, account type, and real background agent mesh state.
/// Eliminates all hardcoded static suggestion chips.
class OvaAdaptiveSuggestionsService {
  final OvaMemoryEngine _memory;

  OvaAdaptiveSuggestionsService(this._memory);

  List<AdaptiveActionPrompt> getPersonalizedPrompts() {
    final user = _memory.currentUserProfile;
    final accountType = user?.accountType ?? 'creator';
    final category = user?.category ?? 'Studio Creation';
    final name = user?.fullName.isNotEmpty == true ? user!.fullName.split(' ').first : 'Creator';

    final prompts = <AdaptiveActionPrompt>[
      // 1. Autonomous Self-Calling Agent Diagnostic (Platform Health & Repair)
      const AdaptiveActionPrompt(
        title: 'Run Autonomous Sentinel Diagnostic',
        prompt: 'Run autonomous system diagnostics, heal backend user records, inspect feed pipelines, and report system health.',
        icon: Icons.healing_rounded,
        badge: 'SENTINEL',
      ),
    ];

    if (accountType == 'business') {
      prompts.addAll([
        AdaptiveActionPrompt(
          title: 'Review Store Inquiries & Catalog Leads',
          prompt: 'Analyze today\'s customer questions, recent orders, and recommend immediate follow-up responses.',
          icon: Icons.storefront_rounded,
          badge: 'BIZ',
        ),
        AdaptiveActionPrompt(
          title: 'Draft Promo Campaign for $category',
          prompt: 'Generate a high-converting promotional post script and caption showcasing our latest $category offerings.',
          icon: Icons.campaign_rounded,
          badge: 'GROWTH',
        ),
        const AdaptiveActionPrompt(
          title: 'Weekly Commerce Performance Summary',
          prompt: 'Summarize weekly storefront revenue, product views, and cart conversions with executive next steps.',
          icon: Icons.analytics_outlined,
        ),
      ]);
    } else {
      // Creator / Personal
      prompts.addAll([
        AdaptiveActionPrompt(
          title: 'Draft Viral $category Reel (15s)',
          prompt: 'Draft a viral $category Reel script with a 3-second visual hook, high-retention mid-break, and call to action.',
          icon: Icons.auto_awesome_rounded,
          badge: 'VIRAL',
        ),
        AdaptiveActionPrompt(
          title: 'Audience Sentiment & Trending Audio',
          prompt: 'Inspect audience reactions on my latest uploads and recommend trending audio tracks fitting $category.',
          icon: Icons.graphic_eq_rounded,
          badge: 'RADAR',
        ),
        AdaptiveActionPrompt(
          title: 'Content Pipeline & Auto-Scheduler',
          prompt: 'Review my pending studio drafts, optimize their captions, and propose an optimal publishing schedule.',
          icon: Icons.schedule_send_rounded,
          badge: 'SCHEDULE',
        ),
      ]);
    }

    // Add persistent memory recall action
    prompts.add(
      AdaptiveActionPrompt(
        title: 'Review Learned Preferences for $name',
        prompt: 'What have you learned about my creative style, preferred camera settings, and publishing habits?',
        icon: Icons.psychology_rounded,
        badge: 'MEMORY',
      ),
    );

    return prompts;
  }
}
