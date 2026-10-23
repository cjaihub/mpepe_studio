enum PrivacyVisibility {
  everyone,
  followers,
  mutuals, // Friends
  none,    // Only me
}

class ProfilePrivacy {
  PrivacyVisibility whoCanSee;
  PrivacyVisibility whoCanFollow;

  ProfilePrivacy({
    this.whoCanSee = PrivacyVisibility.everyone,
    this.whoCanFollow = PrivacyVisibility.everyone,
  });
}

class ContentPrivacy {
  PrivacyVisibility whoCanComment;
  PrivacyVisibility whoCanRemix;
  PrivacyVisibility whoCanDownload;

  ContentPrivacy({
    this.whoCanComment = PrivacyVisibility.everyone,
    this.whoCanRemix = PrivacyVisibility.followers,
    this.whoCanDownload = PrivacyVisibility.none,
  });
}

class MessagesPrivacy {
  PrivacyVisibility whoCanMessage;

  MessagesPrivacy({
    this.whoCanMessage = PrivacyVisibility.followers,
  });
}

class LocationPrivacy {
  PrivacyVisibility whoCanSeeLocation;

  LocationPrivacy({
    this.whoCanSeeLocation = PrivacyVisibility.none,
  });
}

class AiPrivacy {
  PrivacyVisibility whoCanUseAiContext; 

  AiPrivacy({
    this.whoCanUseAiContext = PrivacyVisibility.none,
  });
}

class PrivacyCenterSettings {
  final String userId;
  final ProfilePrivacy profile;
  final ContentPrivacy content;
  final MessagesPrivacy messages;
  final LocationPrivacy location;
  final AiPrivacy ai;

  PrivacyCenterSettings({
    required this.userId,
    ProfilePrivacy? profile,
    ContentPrivacy? content,
    MessagesPrivacy? messages,
    LocationPrivacy? location,
    AiPrivacy? ai,
  })  : profile = profile ?? ProfilePrivacy(),
        content = content ?? ContentPrivacy(),
        messages = messages ?? MessagesPrivacy(),
        location = location ?? LocationPrivacy(),
        ai = ai ?? AiPrivacy();
}
