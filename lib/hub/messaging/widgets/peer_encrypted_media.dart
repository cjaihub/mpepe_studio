import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../backend/security/e2e_encryption_service.dart';
import '../../../shared/theme/app_theme.dart';

/// Encrypts and decrypts 1:1 chat attachments with the per-chat key
/// (X25519 shared secret -> HKDF "chat-media" -> AES-256-GCM). Storage only
/// ever holds ciphertext; plaintext lives in the app's temp directory.
class PeerMediaCrypto {
  PeerMediaCrypto._();

  static final Map<String, Future<File>> _decrypted = {};

  /// Writes an encrypted copy of [file] for upload and returns it.
  static Future<File> encryptForUpload(
    E2EEncryptionService e2ee,
    File file,
    String peerPublicKey,
  ) async {
    final cipher = await e2ee.encryptBytesForPeer(await file.readAsBytes(), peerPublicKey);
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/oneova_enc_${DateTime.now().microsecondsSinceEpoch}.bin');
    await out.writeAsBytes(cipher, flush: true);
    return out;
  }

  /// Downloads and decrypts [url] once per app run; later calls share the file.
  static Future<File> decryptToCache(
    E2EEncryptionService e2ee,
    String url,
    String peerPublicKey, {
    String? fileName,
  }) {
    return _decrypted.putIfAbsent(url, () async {
      final dir = await getTemporaryDirectory();
      final ext = _extension(fileName, url);
      final out = File('${dir.path}/oneova_dec_${url.hashCode.toUnsigned(32)}$ext');
      if (await out.exists() && await out.length() > 0) return out;
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final plain = await e2ee.decryptBytesFromPeer(res.bodyBytes, peerPublicKey);
      await out.writeAsBytes(plain, flush: true);
      return out;
    }).catchError((Object e) {
      _decrypted.remove(url);
      throw e;
    });
  }

  static String _extension(String? fileName, String url) {
    final name = (fileName ?? '').isNotEmpty ? fileName! : Uri.parse(url).pathSegments.last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || name.length - dot > 6) return '';
    return name.substring(dot);
  }
}

/// Shows an encrypted attachment: downloads, decrypts, then calls [builder]
/// with the local plaintext file path.
class PeerEncryptedMedia extends ConsumerStatefulWidget {
  final String url;
  final String? peerPublicKey;
  final String? fileName;
  final Widget Function(BuildContext context, String localPath) builder;

  const PeerEncryptedMedia({
    super.key,
    required this.url,
    required this.peerPublicKey,
    required this.builder,
    this.fileName,
  });

  @override
  ConsumerState<PeerEncryptedMedia> createState() => _PeerEncryptedMediaState();
}

class _PeerEncryptedMediaState extends ConsumerState<PeerEncryptedMedia> {
  Future<File>? _file;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant PeerEncryptedMedia old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.peerPublicKey != widget.peerPublicKey) _start();
  }

  void _start() {
    final key = widget.peerPublicKey;
    _file = (key == null || key.isEmpty)
        ? null
        : PeerMediaCrypto.decryptToCache(
            ref.read(e2eEncryptionServiceProvider),
            widget.url,
            key,
            fileName: widget.fileName,
          );
  }

  @override
  Widget build(BuildContext context) {
    final future = _file;
    if (future == null) return _placeholder(context, loading: true);
    return FutureBuilder<File>(
      future: future,
      builder: (context, snap) {
        if (snap.hasData) return widget.builder(context, snap.data!.path);
        if (snap.hasError) return _placeholder(context, loading: false);
        return _placeholder(context, loading: true);
      },
    );
  }

  Widget _placeholder(BuildContext context, {required bool loading}) {
    return Container(
      width: 200,
      height: 120,
      margin: const EdgeInsets.only(bottom: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1),
      ),
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: context.textMuted),
                const SizedBox(width: 6),
                Text(
                  "Can't decrypt on this device",
                  style: TextStyle(fontSize: 11, color: context.textMuted),
                ),
              ],
            ),
    );
  }
}

/// Network URL or local file path -> image provider.
ImageProvider chatMediaImage(String urlOrPath) =>
    urlOrPath.startsWith('/') ? FileImage(File(urlOrPath)) : NetworkImage(urlOrPath) as ImageProvider;
