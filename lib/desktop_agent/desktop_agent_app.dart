import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/theme/app_theme.dart';
import 'desktop_agent_screen.dart';

class DesktopAgentApp extends ConsumerWidget {
  const DesktopAgentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'OneOva Connect',
      theme: AppTheme.darkTheme,
      // No auth gate — DesktopAgentScreen handles its own pairing/bypass flow.
      home: const DesktopAgentScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

