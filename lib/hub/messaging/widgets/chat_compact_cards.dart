import 'package:any_link_preview/any_link_preview.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_theme.dart';

/// Small, theme-aware building blocks for chat bubbles: link cards, file
/// cards, date separators, the encryption banner and the jump-to-latest
/// button. [onBlue] means the card sits inside your own (brand blue) bubble.

Color _fg(BuildContext c, bool onBlue) => onBlue ? AppColors.brandWhite : c.textPrimary;
Color _fgMuted(BuildContext c, bool onBlue) => onBlue ? AppColors.brandWhite.withValues(alpha: 0.72) : c.textMuted;
Color _cardBg(BuildContext c, bool onBlue) =>
    onBlue ? AppColors.brandBlack.withValues(alpha: 0.18) : c.surfaceMid;

final _urlPattern = RegExp(r'(?:https?:\/\/|www\.)[^\s<>"]+', caseSensitive: false);

/// First web link in [text], with a scheme, or null.
String? firstLinkIn(String text) {
  final m = _urlPattern.firstMatch(text);
  if (m == null) return null;
  var url = m.group(0)!.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
  if (!url.toLowerCase().startsWith('http')) url = 'https://$url';
  return Uri.tryParse(url)?.hasAuthority == true ? url : null;
}

String _domainOf(String url) {
  final host = Uri.tryParse(url)?.host ?? url;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Compact link preview: thumbnail, title and domain in one row.
class ChatLinkCard extends StatefulWidget {
  final String url;
  final bool onBlue;
  const ChatLinkCard({super.key, required this.url, this.onBlue = false});

  static final Map<String, Future<Metadata?>> _cache = {};

  @override
  State<ChatLinkCard> createState() => _ChatLinkCardState();
}

class _ChatLinkCardState extends State<ChatLinkCard> {
  late Future<Metadata?> _meta;

  @override
  void initState() {
    super.initState();
    _meta = ChatLinkCard._cache.putIfAbsent(
      widget.url,
      () => AnyLinkPreview.getMetadata(link: widget.url).catchError((_) => null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onBlue = widget.onBlue;
    return FutureBuilder<Metadata?>(
      future: _meta,
      builder: (context, snap) {
        final m = snap.data;
        final title = (m?.title?.trim().isNotEmpty ?? false) ? m!.title!.trim() : _domainOf(widget.url);
        final image = m?.image;
        return Material(
          color: _cardBg(context, onBlue),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border(
                  left: BorderSide(color: onBlue ? AppColors.brandWhite : AppColors.brandBlue, width: 2.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: image != null && image.startsWith('http')
                          ? Image.network(image, fit: BoxFit.cover, errorBuilder: (_, _, _) => _linkIcon(context))
                          : _linkIcon(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: _fg(context, onBlue),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.link_rounded, size: 11, color: _fgMuted(context, onBlue)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              _domainOf(widget.url),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(color: _fgMuted(context, onBlue), fontSize: 10.5),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _linkIcon(BuildContext context) => Container(
        color: widget.onBlue ? AppColors.brandWhite.withValues(alpha: 0.14) : AppColors.brandBlue.withValues(alpha: 0.12),
        child: Icon(Icons.public_rounded, size: 20, color: widget.onBlue ? AppColors.brandWhite : AppColors.brandBlue),
      );
}

/// What kind of file a name looks like, for the icon and label.
({IconData icon, String label, bool accent}) chatFileKind(String fileName, String? mediaType) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  if (ext == 'pdf') return (icon: Icons.picture_as_pdf_rounded, label: 'PDF', accent: true);
  if (['xls', 'xlsx', 'csv', 'numbers', 'tsv'].contains(ext)) {
    return (icon: Icons.table_chart_rounded, label: 'Spreadsheet', accent: false);
  }
  if (['ppt', 'pptx', 'key'].contains(ext)) return (icon: Icons.slideshow_rounded, label: 'Slides', accent: true);
  if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2'].contains(ext) || mediaType == 'archive') {
    return (icon: Icons.folder_zip_rounded, label: 'Archive', accent: false);
  }
  if (['dart', 'js', 'ts', 'py', 'json', 'html', 'css', 'swift', 'kt', 'cpp', 'c', 'sql', 'sh', 'yaml', 'yml']
          .contains(ext) ||
      mediaType == 'code') {
    return (icon: Icons.code_rounded, label: 'Code', accent: false);
  }
  if (['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'].contains(ext)) {
    return (icon: Icons.audio_file_rounded, label: 'Audio', accent: true);
  }
  if (['doc', 'docx', 'txt', 'rtf', 'pages', 'md'].contains(ext)) {
    return (icon: Icons.description_rounded, label: 'Document', accent: false);
  }
  return (icon: Icons.insert_drive_file_rounded, label: 'File', accent: false);
}

String chatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Compact file row: type icon, name, size · type, and a save/open button.
class ChatFileCard extends StatelessWidget {
  final String fileName;
  final int? fileSize;
  final String? mediaType;
  final bool onBlue;
  final bool encrypted;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;

  const ChatFileCard({
    super.key,
    required this.fileName,
    this.fileSize,
    this.mediaType,
    this.onBlue = false,
    this.encrypted = false,
    this.onOpen,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final kind = chatFileKind(fileName, mediaType);
    final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : '';
    final tint = onBlue ? AppColors.brandWhite : (kind.accent ? AppColors.brandPink : AppColors.brandBlue);
    final size = chatFileSize(fileSize);
    return Material(
      color: _cardBg(context, onBlue),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(kind.icon, size: 17, color: tint),
                    if (ext.isNotEmpty && ext.length <= 4)
                      Text(ext,
                          style: GoogleFonts.inter(color: tint, fontSize: 7.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: _fg(context, onBlue), fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 1),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (encrypted) ...[
                        Icon(Icons.lock_rounded, size: 9.5, color: _fgMuted(context, onBlue)),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          size.isEmpty ? kind.label : '$size · ${kind.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(color: _fgMuted(context, onBlue), fontSize: 10.5),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              if (onSave != null)
                IconButton(
                  onPressed: onSave,
                  tooltip: 'Save or open with…',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.download_rounded, size: 18, color: _fg(context, onBlue)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", weekday, or a date, centred between messages.
class ChatDateSeparator extends StatelessWidget {
  final DateTime day;
  const ChatDateSeparator({super.key, required this.day});

  static String label(DateTime d, [DateTime? now]) {
    now ??= DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff < 7) return days[d.weekday - 1];
    final base = '${d.day} ${months[d.month - 1]}';
    return d.year == now.year ? base : '$base ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: context.border, width: 1),
          ),
          child: Text(
            label(day),
            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Sticky banner at the top of a chat that shrinks into a lock chip once you
/// scroll. [text] must describe the chat's real protection.
class ChatEncryptionBanner extends StatelessWidget {
  final bool collapsed;
  final bool endToEnd;
  final String text;
  final String chipText;
  final VoidCallback onTap;

  const ChatEncryptionBanner({
    super.key,
    required this.collapsed,
    required this.endToEnd,
    required this.text,
    required this.chipText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = endToEnd ? AppColors.brandBlue : context.textSecondary;
    return Semantics(
      button: true,
      label: '$text. Tap for details.',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 16, vertical: 6),
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 9 : 12, vertical: collapsed ? 4 : 8),
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(collapsed ? AppRadius.full : AppRadius.md),
            border: Border.all(color: tint.withValues(alpha: 0.35), width: 1),
            boxShadow: [
              BoxShadow(color: AppColors.brandBlack.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(endToEnd ? Icons.lock_rounded : Icons.lock_outline_rounded, size: collapsed ? 12 : 15, color: tint),
                SizedBox(width: collapsed ? 4 : 8),
                Flexible(
                  child: Text(
                    collapsed ? chipText : text,
                    maxLines: collapsed ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: collapsed ? tint : context.textSecondary,
                      fontSize: collapsed ? 10.5 : 11.5,
                      fontWeight: collapsed ? FontWeight.w700 : FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.info_outline_rounded, size: 14, color: context.textMuted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round "jump to latest" button with a count of new messages.
class ChatJumpToLatest extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;
  const ChatJumpToLatest({super.key, required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: context.surface,
          shape: CircleBorder(side: BorderSide(color: context.border)),
          elevation: 3,
          shadowColor: AppColors.brandBlack.withValues(alpha: 0.3),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 38,
              height: 38,
              child: Icon(Icons.keyboard_double_arrow_down_rounded, size: 20, color: AppColors.brandBlue),
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            top: -6,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: AppColors.brandPink,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 9.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    );
  }
}
