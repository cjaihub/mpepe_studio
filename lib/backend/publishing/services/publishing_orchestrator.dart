import 'package:oneova/backend/publishing/models/publishing_job_models.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';
import 'package:oneova/backend/connectors/core/platform_connector.dart';

class PublishingOrchestrator {
  final Map<String, PlatformConnector> connectors;

  PublishingOrchestrator({required this.connectors});

  /// Orchestrates the publish flow for master content across multiple destinations.
  Future<OrchestrationJob> orchestratePublish(
    String contentId,
    List<ConnectedAccount> targetDestinations,
    Map<String, dynamic> masterData,
  ) async {
    final List<DestinationJob> destJobs = targetDestinations.map((account) {
      return DestinationJob(
        id: 'job_${account.externalAccountId}_${DateTime.now().millisecondsSinceEpoch}',
        platform: account.platformId,
        accountId: account.externalAccountId,
        status: DestinationStatus.queued,
      );
    }).toList();

    final orchestrationJob = OrchestrationJob(
      id: 'orch_${DateTime.now().millisecondsSinceEpoch}',
      contentId: contentId,
      createdAt: DateTime.now(),
      masterStatus: OrchestrationStatus.processing,
      destinations: destJobs,
    );

    // Concurrently process all destinations
    await Future.wait(targetDestinations.map((account) async {
      final destJob = destJobs.firstWhere((j) => j.accountId == account.externalAccountId);
      await _processDestination(destJob, account, masterData);
    }));

    // Crucial: The system must NEVER report PUBLISHED when only some channels succeeded.
    orchestrationJob.evaluateMasterStatus();
    
    // Final record save here (to DB)
    return orchestrationJob;
  }

  /// Retries a single failed destination inside an existing OrchestrationJob
  Future<void> retryDestination(OrchestrationJob masterJob, String destJobId, ConnectedAccount account, Map<String, dynamic> masterData) async {
    final destJob = masterJob.destinations.firstWhere((j) => j.id == destJobId);
    
    if (destJob.status == DestinationStatus.published) return; // Already done

    destJob.status = DestinationStatus.queued;
    destJob.errorMessage = null;
    masterJob.masterStatus = OrchestrationStatus.processing;
    
    await _processDestination(destJob, account, masterData);
    masterJob.evaluateMasterStatus();
  }

  Future<void> _processDestination(DestinationJob job, ConnectedAccount account, Map<String, dynamic> masterData) async {
    try {
      final connector = connectors[account.platformId];
      if (connector == null) throw Exception('No connector found for ${account.platformId}');

      // 1. Validate
      job.status = DestinationStatus.validating;
      connector.requireCapability(PlatformCapability.contentPublish);
      // specific payload validation logic
      
      // 2. Transform (Adapting master payload to platform specific requirements)
      final transformedData = _transformPayload(account.platformId, masterData);
      final externalObject = ExternalObject(
        externalId: '', 
        platform: account.platformId, 
        type: masterData['type'] ?? 'video', 
        data: transformedData,
      );

      // 3. Upload & Publish (Delegated to the connector which usually chunks/uploads then posts)
      job.status = DestinationStatus.publishing;
      final publishResult = await connector.publish(account, externalObject);
      
      // 4. Verify & Record
      job.status = DestinationStatus.verifying;
      if (publishResult.status == 'published' || publishResult.status == 'PENDING_AUDIT') {
        job.externalId = publishResult.jobId; // E.g., YT Video ID
        job.status = DestinationStatus.published;
      } else {
        throw Exception('Provider failed with status: ${publishResult.status}');
      }

    } catch (e) {
      job.status = DestinationStatus.failed;
      job.errorMessage = e.toString();
    }
  }

  Map<String, dynamic> _transformPayload(String platform, Map<String, dynamic> masterData) {
    // Platform-specific transformation rules applied here.
    return Map<String, dynamic>.from(masterData);
  }
}
