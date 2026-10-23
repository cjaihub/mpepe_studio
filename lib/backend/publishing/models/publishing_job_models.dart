enum OrchestrationStatus {
  draft,
  queued,
  processing,
  publishing,
  published, // Only if ALL destinations succeed
  partial,   // If SOME destinations failed
  failed,    // If ALL destinations failed
  cancelled,
}

enum DestinationStatus {
  queued,
  validating,
  uploading,
  publishing,
  verifying,
  published,
  failed,
  cancelled,
}

class DestinationJob {
  final String id;
  final String platform;
  final String accountId;
  DestinationStatus status;
  String? externalId;
  String? errorMessage;

  DestinationJob({
    required this.id,
    required this.platform,
    required this.accountId,
    this.status = DestinationStatus.queued,
    this.externalId,
    this.errorMessage,
  });
}

class OrchestrationJob {
  final String id;
  final String contentId;
  final DateTime createdAt;
  OrchestrationStatus masterStatus;
  final List<DestinationJob> destinations;

  OrchestrationJob({
    required this.id,
    required this.contentId,
    required this.createdAt,
    this.masterStatus = OrchestrationStatus.draft,
    required this.destinations,
  });

  /// Evaluates the master status based on all child destination jobs.
  void evaluateMasterStatus() {
    if (masterStatus == OrchestrationStatus.cancelled) return;
    
    bool allPublished = true;
    bool allFailed = true;
    bool anyProcessing = false;

    for (var dest in destinations) {
      if (dest.status == DestinationStatus.published) {
        allFailed = false;
      } else if (dest.status == DestinationStatus.failed) {
        allPublished = false;
      } else if (dest.status == DestinationStatus.cancelled) {
        allPublished = false;
        allFailed = false;
      } else {
        allPublished = false;
        allFailed = false;
        anyProcessing = true;
      }
    }

    if (anyProcessing) {
      masterStatus = OrchestrationStatus.processing; // or publishing depending on specific states
    } else if (allPublished && destinations.isNotEmpty) {
      masterStatus = OrchestrationStatus.published;
    } else if (allFailed && destinations.isNotEmpty) {
      masterStatus = OrchestrationStatus.failed;
    } else {
      masterStatus = OrchestrationStatus.partial;
    }
  }
}
