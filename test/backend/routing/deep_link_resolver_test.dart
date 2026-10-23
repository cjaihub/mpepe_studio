import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/routing/deep_link_resolver.dart';
import 'package:oneova/backend/observability/telemetry_service.dart';
import 'package:mockito/annotations.dart';

// Generates a mock telemetry service
@GenerateMocks([TelemetryService])
import 'deep_link_resolver_test.mocks.dart';

void main() {
  late DeepLinkResolver resolver;
  late MockTelemetryService mockTelemetry;

  setUp(() {
    mockTelemetry = MockTelemetryService();
    resolver = DeepLinkResolver(mockTelemetry);
  });

  group('Security & Routing: DeepLinkResolver', () {
    test('Should return /404 when unauthorized to prevent resource leakage', () async {
      // Act: 'secret-resource' is explicitly hardcoded to return false in _checkResourceAuthorization
      final path = await resolver.resolveAndAuthorize('video', 'secret-resource', mockUid: 'test-user-id');
      
      // Assert: Must never expose 'Access Denied', strictly '404'
      expect(path, equals('/404'));
    });

    test('Should route to correct destination when authorized', () async {
      // Act
      final path = await resolver.resolveAndAuthorize('video', 'public-video-123', mockUid: 'test-user-id');
      
      // Assert
      expect(path, equals('/creator_studio/video/public-video-123'));
    });
    
    test('Should route live streams to viewer', () async {
      final path = await resolver.resolveAndAuthorize('live', 'stream-456', mockUid: 'test-user-id');
      expect(path, equals('/live/view/stream-456'));
    });
  });
}
