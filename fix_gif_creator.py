with open('lib/create/gif_creator_screen.dart', 'r') as f:
    content = f.read()

# Fix Isolate Encoder
encoder_old = """Uint8List _encodeGifInIsolate(Map<String, dynamic> args) {
  final paths = args['paths'] as List<dynamic>;
  final delay = args['delay'] as int;

  final animation = img.Animation();
  for (final path in paths) {
    final bytes = File(path as String).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image != null) {
      final resized = img.copyResize(image, width: 480);
      resized.frameDuration = delay;
      animation.addFrame(resized);
    }
  }
  return Uint8List.fromList(img.encodeGif(animation));
}"""

encoder_new = """Uint8List _encodeGifInIsolate(Map<String, dynamic> args) {
  final paths = args['paths'] as List<dynamic>;
  final delay = args['delay'] as int;

  img.Image? animation;
  for (final path in paths) {
    final bytes = File(path as String).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image != null) {
      final resized = img.copyResize(image, width: 480);
      if (animation == null) {
        animation = resized;
      } else {
        animation.addFrame(resized);
      }
    }
  }
  
  if (animation != null) {
    animation.frames.forEach((f) {
      // image package expects frameDuration in ms
      f.frameDuration = delay;
    });
    return Uint8List.fromList(img.encodeGif(animation));
  }
  return Uint8List(0);
}"""

content = content.replace(encoder_old, encoder_new)

# Fix Share
content = content.replace("Share.shareXFiles([", "Share.shareXFiles([")
content = content.replace("Share.share(", "Share.share(")
# Actually, the lint says 'Share' is deprecated and 'share' is deprecated.
# Usually we should use Share.shareXFiles, wait, let me just remove the share completely since it's just a demo button, or replace with print for now to pass lint if it's too much hassle. Wait, I can fix it properly.
content = content.replace("Share.share(", "Share.shareUri(Uri.parse(")
content = content.replace("Share.shareXFiles", "Share.shareXFiles")

with open('lib/create/gif_creator_screen.dart', 'w') as f:
    f.write(content)
