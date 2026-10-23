import '../models/connector_models.dart';

class UnsupportedCapabilityException implements Exception {
  final String capability;
  final String platform;
  UnsupportedCapabilityException(this.platform, this.capability);

  @override
  String toString() => 'UnsupportedCapabilityException: Platform $platform does not support $capability';
}

/// The universal canonical contract for ALL external platform connectors.
/// Each implementation (e.g. YouTubeConnector, InstagramConnector) MUST implement this contract,
/// but must actively throw `UnsupportedCapabilityException` for capabilities it lacks.
abstract class PlatformConnector {
  final String platformName;

  PlatformConnector(this.platformName);

  /// Establish initial connection setup or OAuth intent.
  Future<void> connect();

  /// Complete authorization and yield a connected account.
  Future<ConnectedAccount> authorize(Map<String, dynamic> authPayload);

  /// Refresh the authentication credentials.
  Future<Credential> refreshCredentials(Credential current);

  /// Returns the actual capabilities technically supported by this platform.
  /// Never assume every platform supports every capability.
  List<PlatformCapability> getCapabilities();

  /// Checks if the requested capability is supported, throwing if not.
  void requireCapability(PlatformCapability capability) {
    if (!getCapabilities().contains(capability)) {
      throw UnsupportedCapabilityException(platformName, capability.toString());
    }
  }

  /// Syncs data (messages, comments, analytics) from the platform.
  Future<SyncJob> sync(ConnectedAccount account) async {
    // Implementations will override this and selectively sync what they can.
    // E.g., if they support commentsRead, they sync comments.
    throw UnimplementedError();
  }

  /// Publishes an external object to the platform.
  Future<PublishJob> publish(ConnectedAccount account, ExternalObject object) async {
    requireCapability(PlatformCapability.contentPublish);
    throw UnimplementedError();
  }

  /// Sends a message via the platform's messaging API.
  Future<ExternalMessage> sendMessage(ConnectedAccount account, String recipientId, String text) async {
    requireCapability(PlatformCapability.messagesSend);
    throw UnimplementedError();
  }

  /// Retrieves the current operational status or health of the connector.
  Future<String> getStatus(ConnectedAccount account);

  /// Ingests and processes incoming webhooks securely.
  Future<void> handleWebhook(Webhook webhook) async {
    requireCapability(PlatformCapability.webhooks);
    throw UnimplementedError();
  }

  /// Revokes access and destroys the connection.
  Future<void> disconnect(ConnectedAccount account);
}
