import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AnimatedStreamingMarkdown extends StatefulWidget {
  final String text;
  final Duration typingSpeed;
  final MarkdownStyleSheet? styleSheet;

  const AnimatedStreamingMarkdown({
    super.key,
    required this.text,
    this.typingSpeed = const Duration(milliseconds: 10),
    this.styleSheet,
  });

  @override
  State<AnimatedStreamingMarkdown> createState() => _AnimatedStreamingMarkdownState();
}

class _AnimatedStreamingMarkdownState extends State<AnimatedStreamingMarkdown> {
  String _displayedText = "";
  int _currentIndex = 0;
  bool _isTyping = true;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(AnimatedStreamingMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (_displayedText == oldWidget.text && widget.text.startsWith(oldWidget.text)) {
        // Appended text (streaming chunk)
        _startTyping();
      } else if (!widget.text.startsWith(_displayedText)) {
        // Completely new text
        _displayedText = "";
        _currentIndex = 0;
        _startTyping();
      } else {
        // Text updated but still typing, just continue
        _isTyping = true;
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
    return MarkdownBody(
      data: _displayedText,
      styleSheet: widget.styleSheet ?? MarkdownStyleSheet(
        p: GoogleFonts.inter(color: context.textPrimary, fontSize: 14),
        code: GoogleFonts.firaCode(
          color: context.brandPink, 
          fontSize: 12, 
          backgroundColor: Colors.transparent,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.border, width: 1.0),
        ),
      ),
    );
  }
}
