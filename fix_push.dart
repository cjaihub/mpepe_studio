import 'dart:io';

void main() {
  final filesToFix = {
    'lib/auth/signup_wizard_screen.dart': ['/auth/main_login'],
    'lib/auth/main_login_screen.dart': ['/auth/locked', '/auth/signup_wizard', '/auth/pending'],
    'lib/auth/services/app_lifecycle_observer.dart': ['/auth/locked'],
    'lib/shared/widgets/creation_type_modal.dart': ['/upload/global', '/video/dashboard', '/create/picker', 'item.route'],
    'lib/shared/widgets/all_tools_modal.dart': ['item.route', '/video/dashboard'],
    'lib/social_hub/creation/camera_screen.dart': ['/upload/global'],
    'lib/social_hub/creation/editor_screen.dart': ['/social_hub/feed'],
    'lib/social_hub/feed/sound_page_screen.dart': ['/upload/global'],
    'lib/social_hub/feed/social_feed_screen.dart': ['/upload/global'],
    'lib/social_hub/feed/widgets/story_tray.dart': ['/upload/global'],
    'lib/upload/screens/studio_hub_screen.dart': ['/video/dashboard', '/audio/dashboard'],
  };

  for (final entry in filesToFix.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) continue;
    
    var content = file.readAsStringSync();
    for (final route in entry.value) {
      if (route == 'item.route') {
        content = content.replaceAll("context.go(item.route)", "context.push(item.route)");
      } else {
        content = content.replaceAll("context.go('$route')", "context.push('$route')");
        content = content.replaceAll('context.go("$route")', 'context.push("$route")');
      }
    }
    file.writeAsStringSync(content);
  }
}
