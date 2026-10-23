#!/bin/bash
sed -i '' 's/import '\''\.\.\/settings\/screens\/privacy_security_screen\.dart'\'';/\/\/ import '\''\.\.\/settings\/screens\/privacy_security_screen\.dart'\'';/g' lib/shared/router.dart
sed -i '' 's/import '\''\.\.\/social_hub\/unified_inbox_screen\.dart'\'';/\/\/ import '\''\.\.\/social_hub\/unified_inbox_screen\.dart'\'';/g' lib/shared/router.dart
sed -i '' 's/AppTheme\.h1Style/const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)/g' lib/shared/router.dart
