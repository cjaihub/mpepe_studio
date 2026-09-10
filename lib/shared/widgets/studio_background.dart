import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_animate/flutter_animate.dart';

class StudioBackground extends StatelessWidget {
  final Widget child;
  final List<IconData> backgroundIcons;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  const StudioBackground({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
    this.backgroundIcons = const [
      Icons.hub_outlined,
      Icons.play_circle_outline,
      Icons.mic_none
    ],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: child,
    );
  }
}
