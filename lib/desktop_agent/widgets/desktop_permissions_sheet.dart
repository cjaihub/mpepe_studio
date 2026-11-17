import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../desktop_window_bridge.dart';

/// Compact dual-mode modal sheet for viewing and granting Desktop Agent
/// permissions across Mouse/Keyboard, Multiple Screens, Device Storage, App
/// Automation, and Microphone on both macOS and Windows.
class DesktopPermissionsSheet extends StatefulWidget {
  const DesktopPermissionsSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DesktopPermissionsSheet(),
    );
  }

  @override
  State<DesktopPermissionsSheet> createState() =>
      _DesktopPermissionsSheetState();
}

class _DesktopPermissionsSheetState extends State<DesktopPermissionsSheet> {
  final DesktopWindowBridge _bridge = DesktopWindowBridge.instance;
  Timer? _pollTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bridge.refreshPermissions());
    // Live poll while user toggles checkboxes in System Settings.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_bridge.refreshPermissions()),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _grantAll() async {
    setState(() => _busy = true);
    await _bridge.requestPermission('all');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmResetTcc() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text(
          'Reset macOS Permission Cache?',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: ctx.textPrimary,
          ),
        ),
        content: Text(
          'This clears stale macOS Privacy entries for Oneova after app updates so you can re-enable Accessibility, Screen Recording, and Storage toggles cleanly.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: ctx.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    await _bridge.resetStalePermissions();
    await _bridge.requestPermission('all');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 40, 16, 16),
      constraints: const BoxConstraints(maxWidth: 660, maxHeight: 700),
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: context.border, width: 1.0),
        boxShadow: AppShadows.lg,
      ),
      child: ValueListenableBuilder<DesktopPermissionsSnapshot>(
        valueListenable: _bridge.permissions,
        builder: (context, p, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.brandBlue, AppColors.brandPink],
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Desktop Access & Permissions',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            p.missingCriticalCount == 0
                                ? 'All core storage, screens, mouse & keyboard controls are ready.'
                                : '${p.missingCriticalCount} system access toggle(s) still need permission.',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _grantAll,
                      icon: _busy
                          ? const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt_rounded, size: 16),
                      label: const Text('Grant All'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brandBlue,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: context.textSecondary,
                        size: 19,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.border),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PermRow(
                        icon: Icons.mouse_rounded,
                        title: 'Mouse & Keyboard Across All Apps',
                        subtitle: isMac
                            ? 'Accessibility (${p.accessibility ? "On" : "Off"}) • Input Monitoring (${p.inputMonitoring ? "On" : "Off"})'
                            : 'Win32 Input & Global Hotkeys${p.isElevated ? " • Elevated Admin Active" : " • Standard User (grant Admin to control UAC/Admin windows)"}',
                        granted: p.mouseKeyboardReady && (isMac || p.isElevated),
                        actionLabel: isMac
                            ? (p.accessibility ? 'Input Monitoring' : 'Allow Control')
                            : (p.isElevated ? 'Elevated' : 'Run Elevated'),
                        onAction: () => _bridge.requestPermission(
                          isMac
                              ? (p.accessibility
                                    ? 'inputMonitoring'
                                    : 'accessibility')
                              : 'elevation',
                        ),
                        onSettings: () => _bridge.openPermissionSettings(
                          isMac ? 'accessibility' : 'privacy',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PermRow(
                        icon: Icons.monitor_rounded,
                        title: 'Screen & Other Displays (${p.displays.length} connected)',
                        subtitle: p.screenRecording
                            ? 'Screen capture & multi-display mouse navigation ready.'
                            : 'Needed to view and click across primary & external displays.',
                        granted: p.screenRecording,
                        actionLabel: p.screenRecording ? 'Settings' : 'Allow Screens',
                        onAction: () => _bridge.requestPermission('screenRecording'),
                        onSettings: () =>
                            _bridge.openPermissionSettings('screenRecording'),
                      ),
                      if (p.displays.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _DisplaySelectorStrip(
                          displays: p.displays,
                          bridge: _bridge,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _PermRow(
                        icon: Icons.folder_open_rounded,
                        title: 'Device Storage, User Folders & Drives',
                        subtitle:
                            'Desktop (${p.desktopFolder ? "✓" : "✕"}) • Documents (${p.documentsFolder ? "✓" : "✕"}) • Downloads (${p.downloadsFolder ? "✓" : "✕"}) • ${p.mountedVolumes.isEmpty ? "Drives" : p.mountedVolumes.join(", ")}',
                        granted: p.storageFoldersReady,
                        actionLabel:
                            p.storageFoldersReady ? 'Full Disk' : 'Grant Folders',
                        onAction: () => _bridge.requestPermission(
                          p.storageFoldersReady ? 'fullDiskAccess' : 'storage',
                        ),
                        onSettings: () =>
                            _bridge.openPermissionSettings('fullDiskAccess'),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'External Drives & Custom Project Folders',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    p.authorizedFolders.isEmpty
                                        ? 'No custom drives/folders pinned yet. Grant any SSD or project folder.'
                                        : p.authorizedFolders.join(' • '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: context.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  unawaited(_bridge.authorizeStorageFolder()),
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Add Folder'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                side: const BorderSide(
                                  color: AppColors.brandPink,
                                  width: 1.0,
                                ),
                                foregroundColor: AppColors.brandPink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isMac) ...[
                        const SizedBox(height: 8),
                        _PermRow(
                          icon: Icons.auto_awesome_rounded,
                          title: 'Studio App Automation (Apple Events)',
                          subtitle:
                              'Required for DaVinci Resolve, Logic Pro, Finder, Final Cut Pro & Adobe suites.',
                          granted: p.automation,
                          actionLabel: p.automation ? 'Settings' : 'Authorize Apps',
                          onAction: () => _bridge.requestPermission('automation'),
                          onSettings: () =>
                              _bridge.openPermissionSettings('automation'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _PermRow(
                        icon: Icons.mic_rounded,
                        title: 'Microphone & Vertex Live Voice',
                        subtitle:
                            'Used for hands-free Wispr typing and live voice sessions.',
                        granted: p.microphone,
                        actionLabel: p.microphone ? 'Settings' : 'Allow Mic',
                        onAction: () => _bridge.requestPermission('microphone'),
                        onSettings: () =>
                            _bridge.openPermissionSettings('microphone'),
                      ),
                      if (isMac) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _busy ? null : _confirmResetTcc,
                            icon: const Icon(Icons.refresh_rounded, size: 15),
                            label: Text(
                              'If macOS toggles look stuck after update, Reset Permission Cache',
                              style: GoogleFonts.inter(fontSize: 11),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: context.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DisplaySelectorStrip extends StatelessWidget {
  const _DisplaySelectorStrip({
    required this.displays,
    required this.bridge,
  });

  final List<DesktopDisplayInfo> displays;
  final DesktopWindowBridge bridge;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: bridge.selectedDisplayIndex,
      builder: (context, selectedIdx, _) {
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final d in displays)
              ChoiceChip(
                label: Text(
                  '${d.name} (${d.width}x${d.height})',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selectedIdx == d.index
                        ? Colors.white
                        : context.textPrimary,
                  ),
                ),
                selected: selectedIdx == d.index,
                selectedColor: AppColors.brandBlue,
                backgroundColor: context.surface,
                side: BorderSide(color: context.border, width: 1.0),
                onSelected: (_) => bridge.selectDisplay(d.index),
              ),
            if (displays.length > 1)
              ChoiceChip(
                label: Text(
                  'All Screens',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selectedIdx == -1
                        ? Colors.white
                        : context.textPrimary,
                  ),
                ),
                selected: selectedIdx == -1,
                selectedColor: AppColors.brandPink,
                backgroundColor: context.surface,
                side: BorderSide(color: context.border, width: 1.0),
                onSelected: (_) => bridge.selectDisplay(-1),
              ),
          ],
        );
      },
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.actionLabel,
    required this.onAction,
    required this.onSettings,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final statusColor = granted ? const Color(0xFF10B981) : AppColors.brandPink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: granted
              ? context.border
              : AppColors.brandPink.withValues(alpha: 0.45),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 17, color: statusColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        granted ? 'Granted' : 'Required',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: context.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Open System Privacy Settings',
            icon: Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: context.textSecondary,
            ),
            onPressed: onSettings,
          ),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  granted ? context.surfaceMid : AppColors.brandBlue,
              foregroundColor: granted ? context.textPrimary : Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: Text(
              actionLabel,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
