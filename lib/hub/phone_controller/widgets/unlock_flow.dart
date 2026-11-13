import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';

import '../../../shared/theme/app_theme.dart';

/// Gets the computer's login password for a remote unlock.
///
/// The password is stored only on this phone (secure storage / Keystore),
/// is released only after a fingerprint / device-credential check, and is
/// never written to logs or the cloud.
class UnlockFlow {
  UnlockFlow._();

  static const _storage = FlutterSecureStorage();
  static String _key(String deviceId) => 'oneova_unlock_secret_$deviceId';

  static Future<bool> _verifyOwner() async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return true; // no lock on device
      return await auth.authenticate(
        localizedReason: 'Confirm it\'s you to unlock your computer',
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasSaved(String deviceId) async {
    try {
      return (await _storage.read(key: _key(deviceId)))?.isNotEmpty == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> forget(String deviceId) async {
    try {
      await _storage.delete(key: _key(deviceId));
    } catch (_) {}
  }

  /// Returns the password to send, or null if the user cancelled.
  static Future<String?> obtain(BuildContext context, String deviceId, String computerName) async {
    String? saved;
    try {
      saved = await _storage.read(key: _key(deviceId));
    } catch (_) {}
    if (saved != null && saved.isNotEmpty) {
      return await _verifyOwner() ? saved : null;
    }
    if (!context.mounted) return null;
    final result = await showDialog<({String password, bool remember})>(
      context: context,
      builder: (ctx) => _PasswordDialog(computerName: computerName),
    );
    if (result == null || result.password.isEmpty) return null;
    if (result.remember && await _verifyOwner()) {
      try {
        await _storage.write(key: _key(deviceId), value: result.password);
      } catch (_) {}
    }
    return result.password;
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.computerName});
  final String computerName;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctrl = TextEditingController();
  bool _remember = true;
  bool _show = false;

  @override
  void dispose() {
    _ctrl.clear();
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    HapticFeedback.selectionClick();
    Navigator.pop(context, (password: _ctrl.text, remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: context.border, width: 1.0),
      ),
      title: Text(
        'Unlock ${widget.computerName}',
        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: context.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your computer login password is typed on its lock screen over the encrypted link. '
            'It is never logged or uploaded.',
            style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: !_show,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.visiblePassword,
            onSubmitted: (_) => _submit(),
            style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Computer password',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Switch(
                value: _remember,
                activeTrackColor: AppColors.brandBlue,
                onChanged: (v) => setState(() => _remember = v),
              ),
              Expanded(
                child: Text(
                  'Remember on this phone (fingerprint)',
                  style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.inter(color: context.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandBlue,
            foregroundColor: AppColors.brandWhite,
            elevation: 0,
          ),
          onPressed: _submit,
          child: Text('Unlock', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
