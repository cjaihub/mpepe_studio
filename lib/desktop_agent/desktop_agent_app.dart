import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/theme/app_theme.dart';
import '../shared/theme/theme_provider.dart';
import 'desktop_agent_screen.dart';

class DesktopAgentApp extends ConsumerWidget {
  const DesktopAgentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    return MaterialApp(
      title: 'Oneova Computer Agent',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const DesktopAgentScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
