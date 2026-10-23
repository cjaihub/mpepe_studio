import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'omni_assistant_profile_models.dart';

final omniAssistantServiceProvider = NotifierProvider<OmniAssistantService, ConversationStyleProfile>(() {
  return OmniAssistantService();
});

class OmniAssistantService extends Notifier<ConversationStyleProfile> {
  @override
  ConversationStyleProfile build() {
    _loadProfile();
    return const ConversationStyleProfile(preferredName: 'User');
  }

  static const String _profileKey = 'omni_assistant_profile';

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_profileKey);
    if (jsonStr != null) {
      try {
        final json = jsonDecode(jsonStr);
        state = ConversationStyleProfile.fromJson(json);
      } catch (e) {
        // Fallback to default
      }
    }
  }

  Future<void> saveProfile(ConversationStyleProfile profile) async {
    state = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  Future<void> resetPreferences() async {
    const defaultProfile = ConversationStyleProfile(preferredName: 'User');
    await saveProfile(defaultProfile);
  }

  /// System prompt instructions generation based on the active style profile
  String generateSystemPromptAdditions() {
    final buffer = StringBuffer();
    
    buffer.writeln('=== CONVERSATION STYLE ===');
    buffer.writeln('You are a highly natural personal assistant. Do NOT sound like a robotic chatbot, generic customer service bot, or an AI manual.');
    buffer.writeln('Be conversational but honest that you are an AI assistant. Do not pretend to be human.');
    
    buffer.writeln('User preferred name: ${state.preferredName}');
    buffer.writeln('Greeting style: ${state.greetingStyle}');
    buffer.writeln('Primary language: ${state.languageProfile.primaryLanguage}');
    
    buffer.writeln('Tone: ${state.toneProfile.primaryTone.name}');
    buffer.writeln('Use Emojis: ${state.toneProfile.useEmojis ? "Yes" : "No"}');
    buffer.writeln('Punctuation Style: ${state.toneProfile.punctuationStyle}');
    
    buffer.writeln('Explanation Depth: ${state.responsePreference.explanationDepth.name}');
    if (!state.responsePreference.askFollowUpQuestions) {
      buffer.writeln('Only ask follow-up questions if absolutely necessary and useful.');
    }
    
    buffer.writeln('Examples:');
    buffer.writeln("If asked \"Did Sarah reply?\", respond naturally like \"Yes — Sarah replied about 20 minutes ago. She said she'll send the files tonight.\" (If concise, just \"Yes, Sarah replied.\")");
    buffer.writeln('Do not use robotic phrasing like "Please specify which Sarah you are referring to." Instead, ask "I found two Sarahs. Do you mean Sarah Wanjiku or Sarah N.?"');
    
    return buffer.toString();
  }
}
