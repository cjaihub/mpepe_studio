class TelemetryData {
  final double cpuUsagePercent;
  final double ramTotalGb;
  final double ramUsedGb;
  final double storageTotalGb;
  final double storageUsedGb;
  final double networkUploadMbps;
  final double networkDownloadMbps;
  final DateTime timestamp;

  TelemetryData({
    required this.cpuUsagePercent,
    required this.ramTotalGb,
    required this.ramUsedGb,
    required this.storageTotalGb,
    required this.storageUsedGb,
    required this.networkUploadMbps,
    required this.networkDownloadMbps,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'cpu': cpuUsagePercent,
      'ram_total': ramTotalGb,
      'ram_used': ramUsedGb,
      'storage_total': storageTotalGb,
      'storage_used': storageUsedGb,
      'net_up': networkUploadMbps,
      'net_down': networkDownloadMbps,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory TelemetryData.fromJson(Map<String, dynamic> json) {
    return TelemetryData(
      cpuUsagePercent: (json['cpu'] as num?)?.toDouble() ?? 0.0,
      ramTotalGb: (json['ram_total'] as num?)?.toDouble() ?? 0.0,
      ramUsedGb: (json['ram_used'] as num?)?.toDouble() ?? 0.0,
      storageTotalGb: (json['storage_total'] as num?)?.toDouble() ?? 0.0,
      storageUsedGb: (json['storage_used'] as num?)?.toDouble() ?? 0.0,
      networkUploadMbps: (json['net_up'] as num?)?.toDouble() ?? 0.0,
      networkDownloadMbps: (json['net_down'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']) 
          : DateTime.now(),
    );
  }
}
