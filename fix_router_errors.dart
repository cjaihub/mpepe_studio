import 'dart:io';

void main() {
  final file = File('lib/shared/router.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('const PrivacySecurityScreen()', 'const Scaffold()');
  content = content.replaceAll('const UnifiedInboxScreen()', 'const Scaffold()');
  content = content.replaceAll('AppTheme.h1Style', 'const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)');
  content = content.replaceAll('const DesktopRemoteScreen()', 'const Scaffold() /* DesktopRemoteScreen disabled */');
  file.writeAsStringSync(content);
}
