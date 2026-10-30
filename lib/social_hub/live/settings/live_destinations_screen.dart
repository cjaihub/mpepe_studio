// LIVE DESTINATIONS — /settings/live_destinations
//
// Where the Live Studio restreams in real time: Facebook, YouTube, TikTok,
// Twitch, Instagram, Kick or any RTMP server. The host pastes the server URL
// and stream key from the platform's live dashboard; keys are stored
// server-side only (lsDestinations) and shown back masked.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/live_studio/fun/studio_fun.dart';
import '../../../shared/theme/app_theme.dart';

class _Platform {
  const _Platform(this.id, this.label, this.icon, this.defaultUrl, this.help);
  final String id;
  final String label;
  final IconData icon;
  final String defaultUrl;
  final String help;
}

const _platforms = [
  _Platform('facebook', 'Facebook Live', Icons.facebook_rounded, 'rtmps://live-api-s.facebook.com:443/rtmp/',
      'Facebook → Live Producer → Streaming software → copy the stream key.'),
  _Platform('youtube', 'YouTube Live', Icons.smart_display_rounded, 'rtmp://a.rtmp.youtube.com/live2',
      'YouTube Studio → Go live → Stream → copy the stream key.'),
  _Platform('tiktok', 'TikTok LIVE', Icons.music_note_rounded, '',
      'TikTok LIVE Center → stream key (eligible accounts). Paste both the server URL and the key.'),
  _Platform('twitch', 'Twitch', Icons.videogame_asset_rounded, 'rtmp://live.twitch.tv/app',
      'Twitch dashboard → Settings → Stream → primary stream key.'),
  _Platform('instagram', 'Instagram Live', Icons.camera_alt_rounded, '',
      'Instagram (professional accounts) → Live → Streaming software → copy URL and key.'),
  _Platform('kick', 'Kick', Icons.sports_mma_rounded, '', 'Kick dashboard → Settings → Stream URL & key.'),
  _Platform('custom', 'Other (RTMP)', Icons.settings_input_antenna_rounded, '', 'Any service that accepts RTMP/RTMPS.'),
];

_Platform _platformOf(String id) => _platforms.firstWhere((p) => p.id == id, orElse: () => _platforms.last);

class LiveDestinationsScreen extends ConsumerStatefulWidget {
  const LiveDestinationsScreen({super.key});

  @override
  ConsumerState<LiveDestinationsScreen> createState() => _LiveDestinationsScreenState();
}

class _LiveDestinationsScreenState extends ConsumerState<LiveDestinationsScreen> {
  List<LiveDestination>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(studioBroadcastApiProvider).destinations();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load your destinations.');
    }
  }

  Future<void> _edit({LiveDestination? existing, _Platform? platform}) async {
    final saved = await showModalBottomSheet<List<LiveDestination>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => _EditSheet(existing: existing, platform: platform ?? _platformOf(existing?.platform ?? 'custom')),
    );
    if (saved != null && mounted) setState(() => _items = saved);
  }

  Future<void> _toggle(LiveDestination d, bool on) async {
    try {
      final items = await ref.read(studioBroadcastApiProvider).saveDestination(
            id: d.id,
            platform: d.platform,
            label: d.label,
            url: d.url,
            key: '',
            enabled: on,
          );
      if (mounted) setState(() => _items = items);
    } catch (_) {}
  }

  Future<void> _delete(LiveDestination d) async {
    final items = await ref.read(studioBroadcastApiProvider).deleteDestination(d.id);
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.topBarBg,
        foregroundColor: context.topBarFg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/hub/home'),
        ),
        title: Text('Live destinations', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.brandBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(children: [
            const Icon(Icons.cell_tower_rounded, color: AppColors.brandBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your Oneova live is restreamed in real time to every destination that is on. '
                'Comments and likes stay on Oneova; the video is the 1080p stage.',
                style: GoogleFonts.inter(fontSize: 13, height: 1.35, color: context.textPrimary),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        if (_error != null) Text(_error!, style: GoogleFonts.inter(color: AppColors.brandPink)),
        if (items == null && _error == null) const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
        if (items != null) ...[
          for (final d in items)
            Card(
              color: context.surface,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: context.border),
              ),
              child: ListTile(
                leading: Icon(_platformOf(d.platform).icon, color: d.enabled ? AppColors.brandBlue : context.textMuted),
                title: Text(d.label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary)),
                subtitle: Text('${d.url}  ${d.keyHint}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
                onTap: () => _edit(existing: d),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch.adaptive(value: d.enabled, onChanged: (v) => _toggle(d, v), activeTrackColor: AppColors.brandPink),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: context.textMuted),
                    tooltip: 'Remove',
                    onPressed: () => _delete(d),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          Text('ADD A PLATFORM',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: context.textMuted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _platforms)
              ActionChip(
                avatar: Icon(p.icon, size: 18, color: AppColors.brandBlue),
                label: Text(p.label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary)),
                backgroundColor: context.surface,
                side: BorderSide(color: context.border),
                onPressed: () => _edit(platform: p),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.existing, required this.platform});
  final LiveDestination? existing;
  final _Platform platform;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  late final _label = TextEditingController(text: widget.existing?.label ?? widget.platform.label);
  late final _url = TextEditingController(text: widget.existing?.url ?? widget.platform.defaultUrl);
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await ref.read(studioBroadcastApiProvider).saveDestination(
            id: widget.existing?.id,
            platform: widget.platform.id,
            label: _label.text.trim(),
            url: _url.text.trim(),
            key: _key.text.trim(),
            enabled: widget.existing?.enabled ?? true,
          );
      if (mounted) Navigator.of(context).pop(items);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is FirebaseFunctionsException ? e.message : 'Could not save. Try again.';
        });
      }
    }
  }

  InputDecoration _dec(String label, IconData icon, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.brandBlue),
        filled: true,
        fillColor: context.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(widget.platform.icon, color: AppColors.brandBlue),
          const SizedBox(width: 10),
          Text(editing ? 'Edit ${widget.platform.label}' : widget.platform.label,
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: context.textPrimary)),
        ]),
        const SizedBox(height: 6),
        Text(widget.platform.help, style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary)),
        const SizedBox(height: 16),
        TextField(controller: _label, decoration: _dec('Name', Icons.label_outline_rounded)),
        const SizedBox(height: 10),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: _dec('Server URL', Icons.dns_outlined, hint: 'rtmp://…'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _key,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: _dec('Stream key', Icons.key_rounded,
              hint: editing ? 'Leave empty to keep ${widget.existing!.keyHint}' : 'Paste from the platform'),
        ),
        TextButton.icon(
          onPressed: () async {
            final d = await Clipboard.getData(Clipboard.kTextPlain);
            if (d?.text != null) _key.text = d!.text!.trim();
          },
          icon: const Icon(Icons.content_paste_rounded, color: AppColors.brandBlue),
          label: Text('Paste key', style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w700)),
        ),
        if (_error != null) Text(_error!, style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 13)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
            child: Text(_busy ? 'Saving…' : 'Save', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.brandWhite)),
          ),
        ),
      ]),
    );
  }
}
