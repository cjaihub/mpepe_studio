enum CopilotCapability {
  contentIdeas,
  hooks,
  scripts,
  captions,
  hashtags,
  thumbnailIdeas,
  titles,
  storyboards,
  editingSuggestions,
  bestPostingWindows,
  commentSummaries,
  fanQuestions,
  communitySummaries,
  contentRepurposing,
  longVideoConversion,
  shortExtraction,
  translation,
  dubbing,
  analyticsExplanation,
}

class CopilotSuggestion {
  final String id;
  final CopilotCapability capability;
  final String title;
  final String content;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const CopilotSuggestion({
    required this.id,
    required this.capability,
    required this.title,
    required this.content,
    this.metadata,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'capability': capability.name,
      'title': title,
      'content': content,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
