import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AnimatedTypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration typingSpeed;

  const AnimatedTypewriterText({
    super.key,
    required this.text,
    this.style,
    this.typingSpeed = const Duration(milliseconds: 15),
  });

  @override
  State<AnimatedTypewriterText> createState() => _AnimatedTypewriterTextState();
}

class _AnimatedTypewriterTextState extends State<AnimatedTypewriterText> {
  String _displayedText = "";
  int _currentIndex = 0;
  bool _isTyping = true;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(AnimatedTypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (_displayedText == oldWidget.text && widget.text.startsWith(oldWidget.text)) {
        // Appended text
        _startTyping();
      } else {
        // Completely new text
        _displayedText = "";
        _currentIndex = 0;
        _startTyping();
      }
    }
  }

  void _startTyping() {
    _isTyping = true;
    _typeNextCharacter();
  }

  void _typeNextCharacter() {
    if (!mounted || !_isTyping) return;
    
    if (_currentIndex < widget.text.length) {
      setState(() {
        _currentIndex++;
        _displayedText = widget.text.substring(0, _currentIndex);
      });
      Future.delayed(widget.typingSpeed, _typeNextCharacter);
    } else {
      _isTyping = false;
    }
  }

  @override
  void dispose() {
    _isTyping = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: widget.style ?? GoogleFonts.inter(color: context.textPrimary, fontSize: 14),
    );
  }
}
