import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/oneova_language_service.dart';
import '../theme/app_theme.dart';
import 'oneova_language_action_sheet.dart';

/// Oneova Voice Typing Button
///
/// A premium, compact microphone button that integrates live speech-to-text
/// directly into any [TextEditingController].
///
/// Features:
/// - Tap to toggle voice dictation with haptic feedback
/// - Long-press to open Language Auto-Detection & Translation Actions
/// - Real-time word-by-word transcription into the target [controller]
/// - Intelligent appending (preserves existing text with proper spacing) or replace mode
/// - Pulsing luminous glow in [AppColors.brandPink] while active
/// - Auto-stops on silence/timeout or manual tap
/// - Handles microphone permissions gracefully with in-app settings redirect
/// - Auto-detects spoken language upon dictation completion with 1-tap translate prompt
class OneovaVoiceTypingButton extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<bool>? onListeningChanged;
  final FocusNode? focusNode;
  final bool append;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final Color? idleColor;
  final Color? activeColor;
  final String tooltip;
  final bool showTranslateAction;
  final bool enableLanguageDetectionToast;

  const OneovaVoiceTypingButton({
    super.key,
    required this.controller,
    this.onChanged,
    this.onListeningChanged,
    this.focusNode,
    this.append = true,
    this.iconSize = 18.0,
    this.padding = const EdgeInsets.all(6.0),
    this.idleColor,
    this.activeColor,
    this.tooltip = 'Voice typing (Dictate)',
    this.showTranslateAction = false,
    this.enableLanguageDetectionToast = true,
  });

  @override
  State<OneovaVoiceTypingButton> createState() => OneovaVoiceTypingButtonState();
}

class OneovaVoiceTypingButtonState extends State<OneovaVoiceTypingButton>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isSpeechReady = false;
  String _initialPrefix = '';

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get isListening => _isListening;

  @override
  void initState() {
    super.initState();
    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulseController.reverse();
      } else if (status == AnimationStatus.dismissed && _isListening) {
        _pulseController.forward();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speech.cancel();
    super.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;

    if (!mounted) return false;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          status.isPermanentlyDenied
              ? 'Microphone access is disabled for Oneova. Enable it in Settings to use voice typing.'
              : 'Microphone permission is required for voice typing.',
          style: GoogleFonts.inter(fontSize: 12.5),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
        action: status.isPermanentlyDenied
            ? SnackBarAction(
                label: 'Settings',
                textColor: AppColors.brandPink,
                onPressed: openAppSettings,
              )
            : null,
      ),
    );
    return false;
  }

  Future<void> toggleListening() async {
    if (_isListening) {
      await stopListening();
      return;
    }

    HapticFeedback.lightImpact();
    if (!await _ensureMicPermission()) return;

    if (!_isSpeechReady) {
      try {
        _isSpeechReady = await _speech.initialize(
          onStatus: (status) {
            if ((status == 'done' || status == 'notListening') && mounted && _isListening) {
              _handleListeningStopped();
            }
          },
          onError: (_) {
            if (mounted && _isListening) {
              _handleListeningStopped();
            }
          },
        );
      } catch (_) {
        _isSpeechReady = false;
      }
    }

    if (!_isSpeechReady) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Voice typing is unavailable on this device.',
            style: GoogleFonts.inter(fontSize: 12.5),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.brandPink,
        ),
      );
      return;
    }

    if (widget.focusNode != null && !widget.focusNode!.hasFocus) {
      widget.focusNode!.requestFocus();
    }

    final currentText = widget.controller.text;
    _initialPrefix = widget.append && currentText.trim().isNotEmpty
        ? '${currentText.trim()} '
        : '';

    setState(() {
      _isListening = true;
    });
    widget.onListeningChanged?.call(true);
    _pulseController.forward();

    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (result) {
          if (!mounted || !_isListening) return;

          final words = result.recognizedWords;
          final updatedText = '$_initialPrefix$words';

          widget.controller.text = updatedText;
          widget.controller.selection = TextSelection.collapsed(
            offset: widget.controller.text.length,
          );

          widget.onChanged?.call(updatedText);

          if (result.finalResult) {
            // Completed recognition sentence
            HapticFeedback.selectionClick();
          }
        },
      );
    } catch (_) {
      _handleListeningStopped();
    }
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _handleListeningStopped();
  }

  void _handleListeningStopped() {
    if (!_isListening) return;
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
      _pulseController.stop();
      _pulseController.reset();
      widget.onListeningChanged?.call(false);

      // Auto-detect language on finished dictated text and offer quick actions
      if (widget.enableLanguageDetectionToast && widget.controller.text.trim().isNotEmpty) {
        final detected = OneovaLanguageService.instance.detectLanguage(widget.controller.text);
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Text(detected.flag, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Detected: ${detected.name} · Tap to translate or polish',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'Actions',
                textColor: AppColors.brandPink,
                onPressed: () {
                  OneovaLanguageActionSheet.show(
                    context,
                    controller: widget.controller,
                    onTextChanged: widget.onChanged,
                  );
                },
              ),
              backgroundColor: AppColors.darkSurface,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  void _openLanguageActionSheet() {
    HapticFeedback.mediumImpact();
    OneovaLanguageActionSheet.show(
      context,
      controller: widget.controller,
      onTextChanged: widget.onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor = widget.activeColor ?? AppColors.brandPink;
    final effectiveIdleColor = widget.idleColor ?? context.textMuted;
    final hasText = widget.controller.text.trim().isNotEmpty;

    final micWidget = Tooltip(
      message: _isListening ? 'Listening… Tap to stop' : widget.tooltip,
      child: InkWell(
        onTap: toggleListening,
        onLongPress: _openLanguageActionSheet,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Padding(
          padding: widget.padding,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = _isListening ? 1.0 + (_pulseController.value * 0.22) : 1.0;
              final glowAlpha = _isListening ? 0.35 + (_pulseController.value * 0.45) : 0.0;

              return Transform.scale(
                scale: scale,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _isListening
                        ? effectiveActiveColor.withValues(alpha: 0.18)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    boxShadow: _isListening
                        ? [
                            BoxShadow(
                              color: effectiveActiveColor.withValues(alpha: glowAlpha),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    size: widget.iconSize,
                    color: _isListening ? effectiveActiveColor : effectiveIdleColor,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    if (widget.showTranslateAction && hasText) {
      final detected = OneovaLanguageService.instance.detectLanguage(widget.controller.text);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OneovaTranslateButton(
            controller: widget.controller,
            onChanged: widget.onChanged,
            iconSize: widget.iconSize,
            detectedLanguage: detected,
          ),
          micWidget,
        ],
      );
    }

    return micWidget;
  }
}

/// Standalone or companion button that opens Language Auto-Detection & Translation Actions
class OneovaTranslateButton extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final DetectedLanguage? detectedLanguage;

  const OneovaTranslateButton({
    super.key,
    required this.controller,
    this.onChanged,
    this.iconSize = 18.0,
    this.padding = const EdgeInsets.all(6.0),
    this.color,
    this.detectedLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.brandBlue;
    final detected = detectedLanguage ?? OneovaLanguageService.instance.detectLanguage(controller.text);

    return Tooltip(
      message: 'Translate & Actions (${detected.name} ${detected.flag})',
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          OneovaLanguageActionSheet.show(
            context,
            controller: controller,
            onTextChanged: onChanged,
          );
        },
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.translate_rounded, size: iconSize, color: effectiveColor),
              if (controller.text.trim().isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(detected.flag, style: const TextStyle(fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


