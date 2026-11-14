import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/compact/compact.dart';
import 'my_voice_service.dart';

/// `/settings/my-voice`: set up "My voice" in a few taps.
/// Intro → consent (read one line) → six practical phrases (about a minute,
/// live level, retake) → build → preview in other languages → done.
class MyVoiceWizardScreen extends StatefulWidget {
  const MyVoiceWizardScreen({super.key});

  @override
  State<MyVoiceWizardScreen> createState() => _MyVoiceWizardScreenState();
}

enum _Stage { loading, home, intro, consent, record, building, preview, error }

const _consentLine = 'I agree that Oneova may use my voice to speak my own translated words.';

const _fallbackPrompts = [
  'Hi, it’s me. I’m on my way, I’ll call you when I get there.',
  'Can you send me the price and the delivery time, please?',
  'Thank you so much for watching, see you in the next video!',
  'That sounds great. Let’s meet tomorrow at ten in the morning.',
  'I’m a bit busy right now, can I call you back in five minutes?',
  'Welcome to my shop. This one is my favourite, let me show you.',
];

/// A short line per preview language (spoken in the person's own voice).
const _previewLines = <String, (String, String)>{
  'sw': ('Swahili', 'Habari! Hii ni sauti yangu, nimetafsiriwa na Oneova.'),
  'fr': ('French', 'Bonjour ! C’est ma voix, traduite par Oneova.'),
  'ar': ('Arabic', 'مرحبا! هذا صوتي، مترجم بواسطة Oneova.'),
  'pt': ('Portuguese', 'Olá! Esta é a minha voz, traduzida pela Oneova.'),
  'es': ('Spanish', '¡Hola! Esta es mi voz, traducida por Oneova.'),
  'en': ('English', 'Hi! This is my voice, translated by Oneova.'),
};

class _MyVoiceWizardScreenState extends State<MyVoiceWizardScreen> {
  final _svc = MyVoiceService.instance;
  final _recorder = AudioRecorder();
  final _player = Player();
  _Stage _stage = _Stage.loading;
  MyVoiceStatus? _status;
  String? _error;
  List<String> _prompts = _fallbackPrompts;
  final Map<int, File> _clips = {};
  final Map<int, double> _clipSeconds = {};
  final Set<int> _retake = {};
  int _index = 0;
  bool _recording = false;
  bool _uploading = false;
  double _level = 0;
  StreamSubscription<Amplitude>? _amp;
  DateTime? _recStart;
  DateTime? _lastLoud;
  File? _consent;
  bool _agree = false;
  String _previewLang = 'sw';
  bool _speaking = false;
  ({String path, String consentPath})? _paths;

  double get _total => _clipSeconds.values.fold(0.0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amp?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _svc.status();
      if (!mounted) return;
      setState(() {
        _status = s;
        if (s.prompts.isNotEmpty) _prompts = s.prompts;
        _stage = s.status == 'none' ? _Stage.intro : _Stage.home;
      });
    } catch (e) {
      if (mounted) setState(() => _fail(e));
    }
  }

  void _fail(Object e) {
    _stage = _Stage.error;
    _error = e is FirebaseFunctionsException ? (e.message ?? 'Something went wrong.') : 'Something went wrong. Try again.';
  }

  // ── Recording ───────────────────────────────────────────────────────────

  Future<File?> _record({required int maxSeconds}) async {
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Allow the microphone to record your voice.');
      return null;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/myvoice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100, numChannels: 1, bitRate: 128000, noiseSuppress: false, autoGain: false),
      path: path,
    );
    HapticFeedback.lightImpact();
    setState(() {
      _recording = true;
      _recStart = DateTime.now();
      _lastLoud = null;
    });
    final done = Completer<void>();
    _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((a) {
      final lvl = ((a.current + 50) / 50).clamp(0.0, 1.0);
      if (mounted) setState(() => _level = lvl);
      final now = DateTime.now();
      if (lvl > 0.25) _lastLoud = now;
      final spoken = now.difference(_recStart!).inMilliseconds;
      // Stop on 1.2 s of quiet after speaking, or at the time limit.
      final quiet = _lastLoud != null && now.difference(_lastLoud!).inMilliseconds > 1200 && spoken > 3000;
      if ((quiet || spoken > maxSeconds * 1000) && !done.isCompleted) done.complete();
    });
    await done.future;
    return _stop(path);
  }

  Future<File?> _stop(String path) async {
    await _amp?.cancel();
    _amp = null;
    final out = await _recorder.stop();
    HapticFeedback.selectionClick();
    final secs = DateTime.now().difference(_recStart ?? DateTime.now()).inMilliseconds / 1000.0;
    if (mounted) {
      setState(() {
        _recording = false;
        _level = 0;
      });
    }
    final f = File(out ?? path);
    return secs >= 2 && f.existsSync() ? f : null;
  }

  Future<void> _recordConsent() async {
    final f = await _record(maxSeconds: 10);
    if (f != null && mounted) setState(() => _consent = f);
  }

  Future<void> _startClips() async {
    if (_consent == null || !_agree) return;
    setState(() => _uploading = true);
    try {
      _paths = await _svc.start();
      await FirebaseStorage.instance.ref(_paths!.consentPath).putFile(_consent!, SettableMetadata(contentType: 'audio/mp4'));
      if (mounted) setState(() => _stage = _Stage.record);
    } catch (e) {
      if (mounted) setState(() => _fail(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _recordClip() async {
    final started = DateTime.now();
    final f = await _record(maxSeconds: 15);
    if (f == null || !mounted) return;
    final secs = DateTime.now().difference(started).inMilliseconds / 1000.0;
    setState(() {
      _clips[_index] = f;
      _clipSeconds[_index] = secs;
      _retake.remove(_index);
      _uploading = true;
    });
    try {
      _paths ??= await _svc.start();
      await FirebaseStorage.instance.ref('${_paths!.path}clip_$_index.m4a').putFile(f, SettableMetadata(contentType: 'audio/mp4'));
      if (!mounted) return;
      // Next phrase that still needs recording (or a retake).
      final next = [for (var i = 0; i < _prompts.length; i++) i].firstWhere(
        (i) => !_clips.containsKey(i) || _retake.contains(i),
        orElse: () => -1,
      );
      setState(() {
        if (next >= 0) _index = next;
      });
    } catch (e) {
      if (mounted) setState(() => _fail(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _play(File f) async {
    await _player.open(Media(f.path));
  }

  bool get _allRecorded => _clips.length >= _prompts.length && _retake.isEmpty;

  // ── Build and preview ─────────────────────────────────────────────────────

  Future<void> _build() async {
    setState(() => _stage = _Stage.building);
    try {
      final s = _status ?? await _svc.status();
      if (!s.available) {
        // Recordings are saved; the voice is built when the server is on.
        if (mounted) setState(() => _stage = _Stage.home);
        await _load();
        return;
      }
      final r = await _svc.finish();
      if (!mounted) return;
      if (r.ready) {
        HapticFeedback.mediumImpact();
        setState(() => _stage = _Stage.preview);
        return;
      }
      setState(() {
        for (final t in r.retake) {
          final i = int.tryParse(RegExp(r'clip_(\d+)').firstMatch(t.clip)?.group(1) ?? '');
          if (i != null) _retake.add(i);
        }
        _index = _retake.isEmpty ? 0 : _retake.first;
        _stage = _Stage.record;
      });
    } catch (e) {
      if (mounted) setState(() => _fail(e));
    }
  }

  Future<void> _preview() async {
    if (_speaking) return;
    setState(() => _speaking = true);
    try {
      final line = _previewLines[_previewLang]!;
      final pcm = await _svc.speakOwn(line.$2, _previewLang);
      await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
      FlutterPcmSound.feed(PcmArrayInt16(bytes: ByteData.sublistView(pcm)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is FirebaseFunctionsException ? (e.message ?? 'Couldn’t play it.') : 'Couldn’t play it.')));
      }
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _turnOff() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Turn off My voice?'),
        content: const Text('Your recordings and your voice are deleted. You can set it up again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (yes != true) return;
    await _svc.disable();
    setState(() {
      _clips.clear();
      _clipSeconds.clear();
      _consent = null;
      _agree = false;
      _paths = null;
    });
    await _load();
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        toolbarHeight: 50,
        title: Text('My voice', style: AppTypography.pageTitle(context.textPrimary)),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          child: KeyedSubtree(key: ValueKey(_stage), child: _body()),
        ),
      ),
    );
  }

  Widget _body() => switch (_stage) {
        _Stage.loading => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        _Stage.error => _page(
            icon: _VoiceOrb(level: 0, tone: AppColors.brandPink),
            title: 'Something went wrong',
            body: _error ?? '',
            primary: ('Try again', () {
              setState(() => _stage = _Stage.loading);
              _load();
            }),
          ),
        _Stage.home => _home(),
        _Stage.intro => _page(
            icon: const _VoiceOrb(level: 0.6, idle: true),
            title: 'Your own voice, in every language',
            body: 'Record about a minute of everyday phrases. Then the people you talk to hear you in their language, '
                'in your own voice, in voice notes and calls.',
            bullets: const [
              (Icons.lock_outline_rounded, 'Only you can use your voice, only for your own words'),
              (Icons.verified_outlined, 'Always marked as AI voice'),
              (Icons.delete_outline_rounded, 'Turn it off any time and it’s deleted'),
            ],
            primary: ('Start', () => setState(() => _stage = _Stage.consent)),
          ),
        _Stage.consent => _consentPage(),
        _Stage.record => _recordPage(),
        _Stage.building => _page(
            icon: const _VoiceOrb(level: 0.8, building: true),
            title: 'Building your voice…',
            body: 'This takes about a minute. You can leave this screen; we’ll keep going.',
          ),
        _Stage.preview => _previewPage(),
      };

  Widget _home() {
    final s = _status!;
    final title = switch (s.status) {
      'ready' => 'Your voice is ready',
      'building' => 'Building your voice…',
      'needs_retake' => 'A few phrases need another take',
      _ => s.available ? 'Recordings saved' : 'Recordings saved for later',
    };
    final body = switch (s.status) {
      'ready' => 'People hear you in their language, in your voice, in voice notes and calls.',
      'needs_retake' => 'Record them again in a quiet place.',
      _ => s.available ? 'Finish to build your voice.' : 'We’re switching on the voice server. Your voice will be built automatically.',
    };
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Center(child: _VoiceOrb(level: s.ready ? 0.7 : 0.3, idle: true)),
      const SizedBox(height: 12),
      Text(title, textAlign: TextAlign.center, style: AppTypography.pageTitle(context.textPrimary)),
      const SizedBox(height: 4),
      Text(body, textAlign: TextAlign.center, style: AppTypography.small(context.textSecondary)),
      const SizedBox(height: 16),
      CompactGroup(children: [
        if (s.ready) CompactRow(icon: Icons.play_circle_outline_rounded, title: 'Hear yourself in another language', onTap: () => setState(() => _stage = _Stage.preview)),
        if (s.status == 'needs_retake' || (s.status == 'recording' && s.available))
          CompactRow(icon: Icons.mic_rounded, title: 'Continue', onTap: () => setState(() => _stage = _Stage.record)),
        CompactRow(icon: Icons.refresh_rounded, title: 'Record again', subtitle: 'Sounds more like you with a quiet room', onTap: () => setState(() => _stage = _Stage.consent)),
        CompactRow(icon: Icons.delete_outline_rounded, title: 'Turn off and delete', destructive: true, onTap: _turnOff),
      ]),
    ]);
  }

  Widget _consentPage() => _page(
        icon: _VoiceOrb(level: _level, recording: _recording),
        title: 'First, your OK in your own voice',
        body: 'Tap the mic and read this line:',
        quote: _consentLine,
        extra: Column(children: [
          if (_consent != null)
            TextButton.icon(onPressed: () => _play(_consent!), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play it back')),
          CheckboxListTile(
            value: _agree,
            onChanged: (v) => setState(() => _agree = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text('I agree. My voice is used only for my own translated words, marked as AI, and deleted when I turn it off.',
                style: AppTypography.small(context.textSecondary)),
          ),
        ]),
        primary: _consent == null || _recording
            ? (_recording ? 'Listening…' : 'Record', _recording ? null : _recordConsent)
            : ('Continue', _agree && !_uploading ? _startClips : null),
      );

  Widget _recordPage() {
    final prompt = _prompts[_index];
    final has = _clips[_index];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(children: [
          for (var i = 0; i < _prompts.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: _recording ? null : () => setState(() => _index = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _retake.contains(i)
                        ? AppColors.brandPink
                        : _clips.containsKey(i)
                            ? AppColors.brandBlue
                            : (i == _index ? AppColors.brandBlue.withValues(alpha: 0.35) : context.border),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: _page(
          icon: _VoiceOrb(level: _level, recording: _recording),
          title: 'Phrase ${_index + 1} of ${_prompts.length}',
          body: _retake.contains(_index) ? 'Once more, a little clearer.' : 'Tap the mic and read it naturally.',
          quote: prompt,
          extra: Column(children: [
            _MinuteRing(seconds: _total),
            if (has != null)
              TextButton.icon(onPressed: () => _play(has), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play it back')),
          ]),
          primary: _allRecorded && !_recording
              ? ('Build my voice', _uploading ? null : _build)
              : (_recording ? 'Listening…' : (has != null ? 'Record again' : 'Record'), _recording || _uploading ? null : _recordClip),
        ),
      ),
    ]);
  }

  Widget _previewPage() => _page(
        icon: _VoiceOrb(level: _speaking ? 0.9 : 0.4, idle: !_speaking, recording: _speaking),
        title: 'Hear yourself',
        body: 'Pick a language. This is how others will hear you.',
        extra: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final e in _previewLines.entries)
            CompactChip(label: e.value.$1, selected: _previewLang == e.key, onTap: () => setState(() => _previewLang = e.key)),
        ]),
        primary: (_speaking ? 'Speaking…' : 'Play', _speaking ? null : _preview),
        secondary: ('Done', () {
          setState(() => _stage = _Stage.loading);
          _load();
        }),
      );

  Widget _page({
    required Widget icon,
    required String title,
    required String body,
    String? quote,
    List<(IconData, String)> bullets = const [],
    Widget? extra,
    (String, VoidCallback?)? primary,
    (String, VoidCallback?)? secondary,
  }) {
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
      Center(child: icon),
      const SizedBox(height: 14),
      Text(title, textAlign: TextAlign.center, style: AppTypography.pageTitle(context.textPrimary)),
      const SizedBox(height: 6),
      Text(body, textAlign: TextAlign.center, style: AppTypography.small(context.textSecondary)),
      if (quote != null) ...[
        const SizedBox(height: 14),
        CompactCard(highlight: true, child: Text('“$quote”', textAlign: TextAlign.center, style: AppTypography.sectionTitle(context.textPrimary))),
      ],
      for (final b in bullets)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Icon(b.$1, size: 18, color: AppColors.brandBlue),
            const SizedBox(width: 10),
            Expanded(child: Text(b.$2, style: AppTypography.small(context.textPrimary))),
          ]),
        ),
      if (extra != null) ...[const SizedBox(height: 12), extra],
      if (primary != null) ...[
        const SizedBox(height: 18),
        SizedBox(
          height: 42,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm))),
            onPressed: primary.$2,
            child: Text(primary.$1),
          ),
        ),
      ],
      if (secondary != null) TextButton(onPressed: secondary.$2, child: Text(secondary.$1)),
    ]);
  }
}

/// Animated voice icon: breathing when idle, live bars while recording or
/// speaking, a rotating ring while building.
class _VoiceOrb extends StatefulWidget {
  final double level;
  final bool recording;
  final bool idle;
  final bool building;
  final Color tone;
  const _VoiceOrb({required this.level, this.recording = false, this.idle = false, this.building = false, this.tone = AppColors.brandBlue});

  @override
  State<_VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<_VoiceOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return SizedBox(
      width: 132,
      height: 132,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _OrbPainter(
            t: reduce ? 0.25 : _c.value,
            level: widget.level,
            recording: widget.recording,
            building: widget.building,
            tone: widget.tone,
          ),
          child: Center(
            child: Icon(widget.building ? Icons.graphic_eq_rounded : Icons.mic_rounded, size: 34, color: AppColors.brandWhite),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t, level;
  final bool recording, building;
  final Color tone;
  _OrbPainter({required this.t, required this.level, required this.recording, required this.building, required this.tone});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.28;
    final breathe = math.sin(t * math.pi * 2) * 0.5 + 0.5;
    canvas.drawCircle(c, r * (1.35 + 0.25 * (recording ? level : breathe * 0.4)), Paint()..color = tone.withValues(alpha: 0.12));
    canvas.drawCircle(c, r * (1.15 + 0.15 * (recording ? level : breathe * 0.3)), Paint()..color = tone.withValues(alpha: 0.22));
    canvas.drawCircle(c, r, Paint()..color = tone);
    if (recording) {
      final bar = Paint()
        ..color = tone
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 24; i++) {
        final a = i / 24 * math.pi * 2;
        final len = 6 + 18 * level * (0.5 + 0.5 * math.sin(a * 3 + t * math.pi * 4));
        final p1 = c + Offset(math.cos(a), math.sin(a)) * (r * 1.6);
        canvas.drawLine(p1, p1 + Offset(math.cos(a), math.sin(a)) * len, bar);
      }
    }
    if (building) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = AppColors.brandPink;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * 1.55), t * math.pi * 2, math.pi * 0.7, false, arc);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}

/// Progress toward about a minute of clean speech.
class _MinuteRing extends StatelessWidget {
  final double seconds;
  const _MinuteRing({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final p = (seconds / 60).clamp(0.0, 1.0);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(value: p, strokeWidth: 3, color: AppColors.brandBlue, backgroundColor: context.border),
      ),
      const SizedBox(width: 8),
      Text(seconds >= 60 ? 'About a minute recorded ✓' : '${seconds.round()} of 60 seconds',
          style: AppTypography.caption(context.textSecondary)),
    ]);
  }
}
