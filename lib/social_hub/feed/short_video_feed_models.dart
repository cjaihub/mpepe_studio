
enum FeedMode {
  forYou,
  following,
  friends,
  trending,
  latest,
  live,
  nearby
}

enum ShortVideoAction {
  like,
  reaction,
  comment,
  share,
  save,
  repost,
  follow,
  notInterested,
  report,
  viewSound,
  viewCreator,
  viewPlace,
}

enum VideoMetricEvent {
  impression,
  start,
  completion,
  rewatch,
  skip,
  like,
  comment,
  share,
  save,
  follow
}

class ShortVideo {
  final String id;
  final String url;
  final String creatorId;
  final String creatorName;
  final String description;
  final String soundName;
  final String? placeName;
  final Duration duration;

  ShortVideo({
    required this.id,
    required this.url,
    required this.creatorId,
    required this.creatorName,
    required this.description,
    required this.soundName,
    this.placeName,
    required this.duration,
  });
}
