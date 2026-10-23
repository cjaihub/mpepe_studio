#!/bin/bash
# Remove redirect: _requireAuth from /hub/home to test the inbox UI directly
sed -i '' 's/redirect: _requireAuth,//g' lib/shared/router.dart
# Set initialLocation directly to /hub/home if it was /splash
sed -i '' "s/initialLocation: isDesktopDebug ? '\/desktop_agent' : '\/splash'/initialLocation: '\/hub\/home'/g" lib/shared/router.dart
