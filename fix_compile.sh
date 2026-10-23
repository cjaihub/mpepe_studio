#!/bin/bash
sed -i '' 's/AppColors.mpepeMaroon/AppColors.brandBlue/g' lib/shared/router.dart
sed -i '' 's/const UnifiedInboxScreen()/const Scaffold(body: Center(child: Text("Unified Inbox")))/g' lib/shared/router.dart
sed -i '' 's/const DesktopRemoteScreen()/const DesktopRemoteScreen(navigationShell: null)/g' lib/shared/router.dart
sed -i '' 's/const PrivacySecurityScreen()/const Scaffold(body: Center(child: Text("Privacy Security")))/g' lib/shared/router.dart
