import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../audio/cloud_dictation.dart';
import '../audio/mic_coordinator.dart';
import '../audio/speech_hub.dart';

import '../services/oneova_language_service.dart';
import '../theme/app_theme.dart';
import 'oneova_language_action_sheet.dart';
import 'oneova_smart_status_banner.dart';

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
  final SpeechHub _speech = SpeechHub.instance;
  CloudDictation? _cloud;
  MicLease? _lease;
  bool _isListening = false;
  bool _usingCloud = false;
  bool _transcribing = false;
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
    unawaited(_speech.cancel(this));
    unawaited(_cloud?.dispose());
    unawaited(_lease?.release());
    super.dispose();
  }

  void _toast(String text, {Color? color, SnackBarAction? action}) {
    if (!mounted) return;
    final isAlert = color == AppColors.brandPink;
    OneovaSmartStatus.show(
      context,
      title: text,
      source: 'Voice Dictation',
      kind: isAlert ? OneovaStatusKind.warning : OneovaStatusKind.info,
      actionLabel: action?.label,
      onAction: action?.onPressed,
    );
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    _toast(
      status.isPermanentlyDenied
          ? 'Microphone access is disabled for Oneova. Enable it in Settings to use voice typing.'
          : 'Microphone permission is required for voice typing.',
      action: status.isPermanentlyDenied
          ? SnackBarAction(label: 'Settings', textColor: AppColors.brandPink, onPressed: openAppSettings)
          : null,
    );
    return false;
  }

  Future<void> toggleListening() async {
    if (_transcribing) return;
    if (_isListening) {
      await stopListening();
      return;
    }

    HapticFeedback.lightImpact();
    if (!await _ensureMicPermission()) return;

    // Take the mic: stops Ova / AI voice / a voice note if one is running and
    // pauses other apps' audio. A call keeps the mic.
    final got = await MicCoordinator.instance.acquire(
      MicUser.voiceTyping,
      onPreempted: _onPreempted,
      onInterruption: (i) {
        if (i == MicInterruption.heldByOtherApp && _isListening) {
          _toast('Another app is using the microphone. Voice typing paused.', color: AppColors.brandPink);
          unawaited(stopListening());
        }
      },
    );
    if (got is MicBusy) {
      _toast(got.message, color: AppColors.brandPink);
      return;
    }
    _lease = got as MicLease;
    if (!mounted) {
      await _lease?.release();
      return;
    }

    if (widget.focusNode != null && !widget.focusNode!.hasFocus) {
      widget.focusNode!.requestFocus();
    }
    final currentText = widget.controller.text;
    _initialPrefix = widget.append && currentText.trim().isNotEmpty ? '${currentText.trim()} ' : '';

    setState(() => _isListening = true);
    widget.onListeningChanged?.call(true);
    _pulseController.forward();

    final started = await _speech.listen(
      owner: this,
      options: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      onStatus: (status) {
        if (!mounted || !_isListening || _usingCloud) return;
        if (status == 'done' || status == 'notListening' || status == 'preempted') {
          _handleListeningStopped();
        }
      },
      onError: (error) {
        if (!mounted || !_isListening || _usingCloud) return;
        // No speech heard is a normal end; anything else means the phone's
        // recognizer failed, so carry on with Oneova's own dictation.
        if (error.errorMsg == 'error_no_match' || error.errorMsg == 'error_speech_timeout') {
          _handleListeningStopped();
        } else {
          unawaited(_startCloud());
        }
      },
      onResult: (result) {
        if (!mounted || !_isListening || _usingCloud) return;
        _write(result.recognizedWords);
        if (result.finalResult) HapticFeedback.selectionClick();
      },
    );
    if (!started) await _startCloud();
  }

  void _write(String words) {
    final updatedText = '$_initialPrefix$words';
    widget.controller.text = updatedText;
    widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    widget.onChanged?.call(updatedText);
  }

  /// The phone's speech service is missing or busy: record and transcribe here.
  Future<void> _startCloud() async {
    if (_usingCloud || !mounted || !_isListening) return;
    await _speech.cancel(this);
    _usingCloud = true;
    _cloud ??= CloudDictation();
    final ok = await _cloud!.start();
    if (!ok) {
      _usingCloud = false;
      _toast('Voice typing is unavailable right now.', color: AppColors.brandPink);
      _handleListeningStopped();
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _onPreempted() async {
    await _speech.cancel(this);
    if (_usingCloud) {
      _usingCloud = false;
      await _cloud?.cancel();
    }
    _lease = null;
    if (mounted && _isListening) _handleListeningStopped();
  }

  Future<void> stopListening() async {
    if (_usingCloud) {
      _usingCloud = false;
      setState(() => _transcribing = true);
      try {
        final text = await _cloud!.stopAndTranscribe();
        if (mounted && text.isNotEmpty) _write(text);
      } catch (_) {
        _toast('Could not transcribe. Check your connection and try again.', color: AppColors.brandPink);
      }
      if (mounted) setState(() => _transcribing = false);
    } else {
      await _speech.stop(this);
    }
    _handleListeningStopped();
  }

  void _handleListeningStopped() {
    if (!_isListening) return;
    HapticFeedback.lightImpact();
    _isListening = false;
    if (_usingCloud) {
      _usingCloud = false;
      unawaited(_cloud?.cancel());
    }
    final lease = _lease;
    _lease = null;
    unawaited(lease?.release());
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
          OneovaSmartStatus.show(
            context,
            title: '${detected.flag} Detected ${detected.name}',
            subtitle: 'Tap Actions to translate or polish your voice draft',
            source: 'Voice Dictation',
            kind: OneovaStatusKind.live,
            actionLabel: 'Actions',
            onAction: () {
              OneovaLanguageActionSheet.show(
                context,
                controller: widget.controller,
                onTextChanged: widget.onChanged,
              );
            },
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
      message: _transcribing
          ? 'Transcribing…'
          : _isListening
              ? 'Listening… Tap to stop'
              : widget.tooltip,
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


