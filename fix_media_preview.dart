import 'dart:io';

void main() {
  final file = File('lib/create/media_preview_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst(
    "appBar: AppBar(",
    "appBar: AppBar(\n        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),"
  );
  file.writeAsStringSync(content);
}
