import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attachment_model.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../security/e2e_encryption_service.dart';

final attachmentServiceProvider = Provider((ref) => AttachmentService(
  ref.read(e2eEncryptionServiceProvider),
));

class AttachmentService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final E2EEncryptionService _e2eService;

  AttachmentService(this._e2eService);

  /// Uploads a file to the Staging bucket for server-side validation.
  /// Returns the UploadTask so the UI can listen to progress, pause, and resume.
  UploadTask uploadAttachment({
    required File file,
    required String conversationId,
    required String userId,
    required AttachmentType expectedType,
    String? encryptionKey,
  }) {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}';
    
    // Upload strictly to the staging directory per architecture rules.
    final storageRef = _storage.ref().child('staging/$conversationId/$userId/$fileName');
    
    // Even if client sets content-type here, we don't trust it. Cloud Function will verify.
    final metadata = SettableMetadata(
      customMetadata: {
        'conversationId': conversationId,
        'userId': userId,
        'expectedType': expectedType.name,
      }
    );

    return storageRef.putFile(file, metadata);
  }

  /// Saves the initial Attachment metadata to Firestore with 'uploading' status
  Future<Attachment> createAttachmentRecord({
    required String conversationId,
    required String fileName,
    required int fileSize,
    required AttachmentType type,
    String? encryptionKey,
  }) async {
    final docRef = _firestore.collection('conversations').doc(conversationId).collection('attachments').doc();
    
    final attachment = Attachment(
      id: docRef.id,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: 'pending/validation', // Unknown until server validates
      type: type,
      storagePath: '', // Unknown until server validates and moves
      status: AttachmentStatus.uploading,
      encryptionKey: encryptionKey,
    );

    await docRef.set(attachment.toJson());
    return attachment;
  }

  /// Retrieves the secure download URL for a validated attachment.
  /// This relies on Firebase SDK auth tokens, maintaining strict access control
  /// without exposing static public URLs.
  Future<String> getSecureDownloadUrl(String storagePath) async {
    final ref = _storage.ref().child(storagePath);
    return await ref.getDownloadURL();
  }

  /// Uploads a file with E2E encryption. 
  /// Generates a symmetric key, encrypts the file, uploads the ciphertext, and returns the symmetric key base64.
  Future<(UploadTask, String)> uploadEncryptedAttachment({
    required File file,
    required String conversationId,
    required String userId,
    required AttachmentType expectedType,
  }) async {
    final symKey = await _e2eService.generateSymmetricKey();
    final symKeyBase64 = await _e2eService.exportSymmetricKey(symKey);
    
    final fileBytes = await file.readAsBytes();
    final encryptedBytes = await _e2eService.encryptBytes(fileBytes, symKey);
    
    // Write encrypted bytes to temp file
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, 'enc_${p.basename(file.path)}'));
    await tempFile.writeAsBytes(encryptedBytes);

    final uploadTask = uploadAttachment(
      file: tempFile,
      conversationId: conversationId,
      userId: userId,
      expectedType: expectedType,
      encryptionKey: symKeyBase64,
    );

    return (uploadTask, symKeyBase64);
  }

  /// Downloads and decrypts an encrypted attachment.
  Future<List<int>> getSecureDecryptedBytes(String storagePath, String symmetricKeyBase64) async {
    final ref = _storage.ref().child(storagePath);
    final data = await ref.getData();
    if (data == null) throw Exception('No data retrieved from storage');

    final symKey = await _e2eService.importSymmetricKey(symmetricKeyBase64);
    final decryptedBytes = await _e2eService.decryptBytes(data.toList(), symKey);
    
    return decryptedBytes;
  }

  /// Deletes an attachment from secure storage and Firestore.
  Future<void> deleteAttachment(String conversationId, Attachment attachment) async {
    if (attachment.storagePath.isNotEmpty) {
      final ref = _storage.ref().child(attachment.storagePath);
      await ref.delete();
    }
    
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('attachments')
        .doc(attachment.id)
        .delete();
  }
}
