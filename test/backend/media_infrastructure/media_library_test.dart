import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:oneova/backend/media_infrastructure/models/media_processing_models.dart';
import 'package:oneova/backend/media_infrastructure/services/media_library_service.dart';

// Fakes
class FakeUser implements User {
  @override
  final String uid;
  FakeUser(this.uid);
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirebaseAuth implements FirebaseAuth {
  User? _currentUser;
  @override
  User? get currentUser => _currentUser;
  set currentUser(User? user) => _currentUser = user;
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReference implements Reference {
  final String path;
  bool shouldThrowExpired = false;
  FakeReference(this.path);
  
  @override
  Future<String> getDownloadURL() async {
    if (shouldThrowExpired) {
      throw Exception('Token expired');
    }
    return 'https://signed.url/video.mp4?token=secure';
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirebaseStorage implements FirebaseStorage {
  bool shouldThrowExpired = false;
  
  @override
  Reference ref([String? path]) {
    final reference = FakeReference(path ?? '');
    reference.shouldThrowExpired = shouldThrowExpired;
    return reference;
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeFirebaseAuth fakeAuth;
  late FakeFirebaseStorage fakeStorage;
  late MediaLibraryService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    fakeAuth = FakeFirebaseAuth();
    fakeAuth.currentUser = FakeUser('user123');
    fakeStorage = FakeFirebaseStorage();

    service = MediaLibraryService(
      firestore: firestore,
      auth: fakeAuth,
      storage: fakeStorage,
    );
  });

  MediaAsset createTestAsset({
    required String id,
    required String ownerId,
    MediaVisibility visibility = MediaVisibility.public,
    MediaProcessingStatus status = MediaProcessingStatus.ready,
  }) {
    return MediaAsset(
      id: id,
      ownerId: ownerId,
      type: MediaType.video,
      originalFilename: 'test.mp4',
      mimeType: 'video/mp4',
      sizeBytes: 1024 * 1024 * 10,
      storageLocation: 'content_media/$ownerId/$id.mp4',
      processingState: status,
      visibility: visibility,
      createdAt: DateTime.now(),
    );
  }

  test('Test unauthorized download (not logged in)', () async {
    fakeAuth.currentUser = null;

    expect(
      () => service.getSecureSignedUrl('asset1'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Unauthorized'))),
    );
  });

  test('Test unauthorized download (private media owned by someone else)', () async {
    final asset = createTestAsset(id: 'asset1', ownerId: 'otherUser', visibility: MediaVisibility.private);
    await service.registerAsset(asset);

    expect(
      () => service.getSecureSignedUrl('asset1'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Forbidden'))),
    );
  });
  
  test('Test authorized download (private media owned by current user)', () async {
    final asset = createTestAsset(id: 'asset1', ownerId: 'user123', visibility: MediaVisibility.private);
    await service.registerAsset(asset);

    final url = await service.getSecureSignedUrl('asset1');
    expect(url, 'https://signed.url/video.mp4?token=secure');
  });

  test('Test deleted media access', () async {
    final asset = createTestAsset(id: 'asset1', ownerId: 'user123', status: MediaProcessingStatus.deleted);
    await service.registerAsset(asset);

    expect(
      () => service.getSecureSignedUrl('asset1'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Gone'))),
    );
  });

  test('Test ownership when deleting', () async {
    final asset = createTestAsset(id: 'asset1', ownerId: 'otherUser');
    await service.registerAsset(asset);

    expect(
      () => service.deleteAsset('asset1'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Forbidden'))),
    );
  });

  test('Test expired signed URLs', () async {
    final asset = createTestAsset(id: 'asset1', ownerId: 'user123');
    await service.registerAsset(asset);

    fakeStorage.shouldThrowExpired = true;

    expect(
      () => service.getSecureSignedUrl('asset1'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to generate secure access token'))),
    );
  });
}
