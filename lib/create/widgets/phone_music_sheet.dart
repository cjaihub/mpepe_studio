import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart' show Media, Player;
import 'package:photo_manager/photo_manager.dart';

import '../../shared/theme/app_theme.dart';

/// A song picked from the phone's own music library.
class PhoneSong {
  final String path;
  final String title;
  final int durationMs;
  const PhoneSong(this.path, this.title, this.durationMs);
}

/// The phone's music (MediaStore audio): search, tap to listen, Use to pick.
Future<PhoneSong?> showPhoneMusicSheet(BuildContext context) => showModalBottomSheet<PhoneSong>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _PhoneMusicSheet(),
    );

class _PhoneMusicSheet extends StatefulWidget {
  const _PhoneMusicSheet();

  @override
  State<_PhoneMusicSheet> createState() => _PhoneMusicSheetState();
}

class _PhoneMusicSheetState extends State<_PhoneMusicSheet> {
  List<AssetEntity>? _songs;
  String? _error;
  String _query = '';
  String? _playingId;
  Player? _player;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final perm = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(androidPermission: AndroidPermission(type: RequestType.audio, mediaLocation: false)),
      );
      if (!perm.hasAccess) {
        setState(() => _error = 'Allow access to music to use songs from this phone.');
        return;
      }
      final paths = await PhotoManager.getAssetPathList(type: RequestType.audio, onlyAll: true);
      final all = paths.isEmpty ? <AssetEntity>[] : await paths.first.getAssetListRange(start: 0, end: 2000);
      all.sort((a, b) => (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase()));
      if (mounted) setState(() => _songs = all.where((a) => a.duration >= 3).toList());
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read music on this phone: $e');
    }
  }

  String _title(AssetEntity a) => (a.title ?? 'Song').replaceAll(RegExp(r'\.[^.]+$'), '');

  Future<void> _toggle(AssetEntity a) async {
    HapticFeedback.selectionClick();
    final p = _player ??= Player();
    if (_playingId == a.id) {
      await p.pause();
      setState(() => _playingId = null);
      return;
    }
    final f = await a.file;
    if (f == null) return;
    await p.open(Media(f.path));
    setState(() => _playingId = a.id);
  }

  Future<void> _use(AssetEntity a) async {
    if (_picking) return;
    setState(() => _picking = true);
    final f = await a.originFile ?? await a.file;
    if (!mounted) return;
    if (f == null) {
      setState(() => _picking = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That song is not available on this phone.')));
      return;
    }
    Navigator.pop(context, PhoneSong(f.path, _title(a), a.duration * 1000));
  }

  @override
  Widget build(BuildContext context) {
    final songs = (_songs ?? const <AssetEntity>[])
        .where((s) => _query.isEmpty || _title(s).toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Text('My music', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  if (_songs != null)
                    Text('${_songs!.length} songs', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      final f = await FilePicker.pickFile(type: FileType.audio);
                      if (f?.path == null || !context.mounted) return;
                      Navigator.pop(context, PhoneSong(f!.path!, f.name.replaceAll(RegExp(r'\.[^.]+$'), ''), 0));
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 16, color: AppColors.brandBlue),
                    label: Text('Files', style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(icon: Icon(Icons.close, color: context.textSecondary), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: context.surfaceMid,
                  hintText: 'Search songs',
                  prefixIcon: Icon(Icons.search_rounded, color: context.textMuted, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.full), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.inter(color: context.textSecondary)),
                      ),
                    )
                  : _songs == null
                      ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2))
                      : songs.isEmpty
                          ? Center(child: Text('No music found on this phone', style: GoogleFonts.inter(color: context.textMuted)))
                          : ListView.builder(
                              itemCount: songs.length,
                              itemBuilder: (_, i) {
                                final a = songs[i];
                                final playing = _playingId == a.id;
                                return ListTile(
                                  leading: GestureDetector(
                                    onTap: () => _toggle(a),
                                    child: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.brandPink.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppColors.brandPink),
                                    ),
                                  ),
                                  title: Text(_title(a),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5)),
                                  subtitle: Text('${a.duration ~/ 60}:${(a.duration % 60).toString().padLeft(2, '0')}',
                                      style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
                                  trailing: TextButton(
                                    onPressed: () => _use(a),
                                    child: Text('Use', style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w800)),
                                  ),
                                  onTap: () => _toggle(a),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
