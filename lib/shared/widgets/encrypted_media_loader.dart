import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../backend/security/e2e_encryption_service.dart';
import '../../backend/inbox/models/attachment_model.dart';
import '../theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class EncryptedMediaLoader extends ConsumerStatefulWidget {
  final Attachment attachment;
  final Widget Function(BuildContext context, File file) builder;
  final Widget fallback;

  const EncryptedMediaLoader({
    super.key,
    required this.attachment,
    required this.builder,
    required this.fallback,
  });

  @override
  ConsumerState<EncryptedMediaLoader> createState() => _EncryptedMediaLoaderState();
}

class _EncryptedMediaLoaderState extends ConsumerState<EncryptedMediaLoader> {
  File? _decryptedFile;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadAndDecrypt();
  }

  Future<void> _loadAndDecrypt() async {
    if (widget.attachment.downloadUrl == null) {
      setState(() => _hasError = true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final File localFile = File('${tempDir.path}/decrypted_${widget.attachment.id}_${widget.attachment.fileName}');

      if (await localFile.exists()) {
        setState(() {
          _decryptedFile = localFile;
          _isLoading = false;
        });
        return;
      }

      final response = await http.get(Uri.parse(widget.attachment.downloadUrl!));
      if (response.statusCode != 200) throw Exception('Failed to download');

      if (widget.attachment.encryptionKey != null) {
        final e2e = ref.read(e2eEncryptionServiceProvider);
        final key = await e2e.importSymmetricKey(widget.attachment.encryptionKey!);
        final decryptedBytes = await e2e.decryptBytes(response.bodyBytes, key);
        await localFile.writeAsBytes(decryptedBytes);
      } else {
        await localFile.writeAsBytes(response.bodyBytes);
      }

      if (mounted) {
        setState(() {
          _decryptedFile = localFile;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading/decrypting media: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return widget.fallback;
    
    if (_isLoading || _decryptedFile == null) {
      return Container(
        constraints: const BoxConstraints(maxHeight: 250, maxWidth: 250),
        color: AppColors.surfaceMid(context),
        alignment: Alignment.center,
        child: const AnimatedLoadingIndicator(color: AppColors.brandBlue),
      );
    }

    return widget.builder(context, _decryptedFile!);
  }
}
