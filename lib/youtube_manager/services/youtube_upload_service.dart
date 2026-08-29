import 'dart:io';
import 'package:googleapis/youtube/v3.dart' as youtube;
import 'package:http/http.dart' as http;

class YouTubeUploadService {
  final http.Client authenticatedClient;

  YouTubeUploadService(this.authenticatedClient);

  Future<youtube.Video> uploadVideo({
    required File videoFile,
    required String title,
    required String description,
    required List<String> tags,
    String privacyStatus = 'private',
  }) async {
    var ytApi = youtube.YouTubeApi(authenticatedClient);

    var video = youtube.Video();
    video.snippet = youtube.VideoSnippet()
      ..title = title
      ..description = description
      ..tags = tags;
    video.status = youtube.VideoStatus()..privacyStatus = privacyStatus;

    var fileStream = videoFile.openRead();
    var media = youtube.Media(fileStream, videoFile.lengthSync());

    try {
      var response = await ytApi.videos.insert(
        video,
        ['snippet', 'status'],
        uploadMedia: media,
      );
      return response;
    } catch (e) {
      print('Error uploading video: $e');
      rethrow;
    }
  }
}
