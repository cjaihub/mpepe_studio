import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/backend/social/models/content.dart';
import 'package:oneova/backend/social/models/story.dart';
import 'package:oneova/settings/widgets/oneova_ai_bio_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Oneova AI Bio Generator & Constraints', () {
    test('All generated suggestions strictly obey <= 150 characters constraint', () {
      final tones = [AiBioTone.viral, AiBioTone.executive, AiBioTone.creative, AiBioTone.minimal];
      for (final tone in tones) {
        final suggestions = OneovaAiBioSheet.buildLocalSuggestions(
          name: 'Elena Vance',
          category: 'Film, Cinema & Video',
          location: 'Nairobi, Kenya',
          pronouns: 'she/her',
          tone: tone,
          keywords: 'cinematic, 4k visuals, visual storyteller',
        );

        expect(suggestions.isNotEmpty, isTrue);
        for (final bio in suggestions) {
          expect(
            bio.length,
            lessThanOrEqualTo(150),
            reason: 'Generated bio exceeded 150 characters: "$bio" (${bio.length} chars)',
          );
          expect(bio.trim().isNotEmpty, isTrue);
        }
      }
    });

    test('AI suggestions personalize content based on creator category and location', () {
      final suggestions = OneovaAiBioSheet.buildLocalSuggestions(
        name: 'Kofi Mensah',
        category: 'Afrobeats & Dance',
        location: 'Accra, Ghana',
        pronouns: 'he/him',
        tone: AiBioTone.viral,
        keywords: '',
      );

      final combined = suggestions.join(' ');
      // Should reflect category or location in suggestions
      expect(
        combined.contains('Afrobeats & Dance') ||
            combined.contains('Accra, Ghana') ||
            combined.contains('Kofi Mensah'),
        isTrue,
      );
    });

    test('Clean bio helper strips surrounding quotes and enforces max 150 chars', () {
      const overlyLong = '"This is a test bio that is purposefully made extremely long to verify that the string truncation logic truncates cleanly without cutting words abruptly or exceeding the one hundred and fifty character limit."';
      final clean = OneovaAiBioSheet.sanitizeBio(overlyLong);
      expect(clean.startsWith('"'), isFalse);
      expect(clean.endsWith('"'), isFalse);
      expect(clean.length, lessThanOrEqualTo(150));
    });
  });

  group('Category & Niche Search Filter Logic', () {
    const categories = [
      'Afrobeats & Dance',
      'Music & Audio Production',
      'Film, Cinema & Video',
      'Fashion, Style & Beauty',
      'Comedy, Standup & Skits',
      'Tech, AI & Gaming',
      'Business, Startups & Biz Pro',
      'Fitness, Wellness & Health',
      'Visual Arts & Illustration',
      'Education, Science & Learning',
      'Food, Cooking & Culinary',
      'Travel, Nature & Exploration',
    ];

    test('Search filter matches case-insensitively and finds exact/partial hits', () {
      final query = 'tech';
      final matches = categories.where((c) => c.toLowerCase().contains(query)).toList();
      expect(matches, contains('Tech, AI & Gaming'));
    });

    test('Search filter detects when a custom niche is needed', () {
      final query = 'Quantum Robotics';
      final matches = categories.where((c) => c.toLowerCase().contains(query.toLowerCase())).toList();
      expect(matches.isEmpty, isTrue);
      // Custom niche created
      final customNiche = query.trim();
      expect(customNiche, 'Quantum Robotics');
    });
  });

  group('Story Status Content Sharing Model', () {
    test('Story model constructs valid shared post element with 24-hour expiration', () {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24));

      final story = Story(
        id: 'story_test_123',
        authorId: 'user_456',
        authorName: 'Alex Rivera',
        authorAvatarUrl: 'https://cdn.oneova.app/avatar.jpg',
        mediaType: StoryMediaType.video,
        mediaUrl: 'https://cdn.oneova.app/video.mp4',
        createdAt: now,
        expiresAt: expiresAt,
        privacy: StoryPrivacy.public,
        lifecycle: StoryLifecycle.published,
        interactiveElements: [
          InteractiveElement(
            type: 'shared_post',
            x: 0.5,
            y: 0.5,
            data: {
              'postId': 'post_789',
              'authorId': 'creator_001',
              'thumbnailUrl': 'https://cdn.oneova.app/thumb.jpg',
              'caption': 'Check out this awesome video!',
            },
          ),
        ],
      );

      expect(story.id, 'story_test_123');
      expect(story.authorId, 'user_456');
      expect(story.isExpired, isFalse);
      expect(story.expiresAt.difference(now).inHours, 24);
      expect(story.interactiveElements.length, 1);
      expect(story.interactiveElements.first.type, 'shared_post');
      expect(story.interactiveElements.first.data['postId'], 'post_789');

      final map = story.toMap();
      expect(map['authorId'], 'user_456');
      expect(map['privacy'], 'public');
      expect(map['lifecycle'], 'published');
    });
  });
}
