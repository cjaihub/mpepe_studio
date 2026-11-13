import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'telemetry_models.dart';
import '../secure_pairing/secure_pairing_service.dart';
import '../secure_pairing/crypto_utils.dart';
import '../../desktop_agent/desktop_firebase_rest_client.dart';

class DesktopTelemetryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Ref _ref;
  
  Timer? _timer;
  bool _isRunning = false;
  String? _deviceId;
  
  // Network speed calculation
  int _lastNetworkInBytes = 0;
  int _lastNetworkOutBytes = 0;
  DateTime? _lastNetworkTime;

  DesktopTelemetryService(this._ref);

  void start(String deviceId) {
    if (_isRunning) return;
    _deviceId = deviceId;
    _isRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _collectAndPublish();
    });
  }

  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _collectAndPublish() async {
    if (!kIsWeb && Platform.isMacOS) {
      try {
        final cpu = await _getCpuUsage();
        final ram = await _getRamUsage();
        final storage = await _getStorageUsage();
        final network = await _getNetworkSpeed();

        final data = TelemetryData(
          cpuUsagePercent: cpu,
          ramTotalGb: ram['total'] ?? 0.0,
          ramUsedGb: ram['used'] ?? 0.0,
          storageTotalGb: storage['total'] ?? 0.0,
          storageUsedGb: storage['used'] ?? 0.0,
          networkUploadMbps: network['up'] ?? 0.0,
          networkDownloadMbps: network['down'] ?? 0.0,
          timestamp: DateTime.now(),
        );

        await _publishToCloud(data);
      } catch (e) {
        debugPrint("Telemetry collection error: \$e");
      }
    }
  }

  Future<void> _publishToCloud(TelemetryData data) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    final activeKey = _ref.read(securePairingProvider).activeKey;
    final payloadMap = <String, dynamic>{
      'timestamp': DateTime.now().toUtc(),
    };
    if (activeKey != null) {
      final jsonString = jsonEncode(data.toJson());
      payloadMap['payload_encrypted'] =
          CryptoUtils.encryptPayload(jsonString, activeKey);
    } else {
      payloadMap['payload'] = data.toJson();
    }

    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      await DesktopFirebaseRestClient.instance.setDocument(
        'registered_computers/$deviceId/telemetry/latest',
        payloadMap,
      );
      return;
    }

    await _firestore
        .collection('registered_computers')
        .doc(deviceId)
        .collection('telemetry')
        .doc('latest')
        .set({
      ...payloadMap,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<double> _getCpuUsage() async {
    final result = await Process.run('top', ['-l', '1', '-n', '0']);
    final output = result.stdout as String;
    
    // CPU usage: 5.88% user, 2.94% sys, 91.17% idle
    final RegExp regExp = RegExp(r"CPU usage: ([\d.]+)% user, ([\d.]+)% sys");
    final match = regExp.firstMatch(output);
    if (match != null) {
      final user = double.tryParse(match.group(1)!) ?? 0.0;
      final sys = double.tryParse(match.group(2)!) ?? 0.0;
      return user + sys;
    }
    return 0.0;
  }

  Future<Map<String, double>> _getRamUsage() async {
    // Total RAM
    final memsizeResult = await Process.run('sysctl', ['-n', 'hw.memsize']);
    final totalBytes = int.tryParse((memsizeResult.stdout as String).trim()) ?? 0;
    final totalGb = totalBytes / (1024 * 1024 * 1024);

    // Used RAM (approximate using top)
    final topResult = await Process.run('top', ['-l', '1', '-n', '0']);
    final output = topResult.stdout as String;
    // PhysMem: 18G used (3394M wired), 14G unused.
    final RegExp regExp = RegExp(r"PhysMem: (\d+)([MG]) used");
    final match = regExp.firstMatch(output);
    
    double usedGb = 0.0;
    if (match != null) {
      final val = double.tryParse(match.group(1)!) ?? 0.0;
      final unit = match.group(2);
      if (unit == 'M') {
        usedGb = val / 1024;
      } else {
        usedGb = val;
      }
    }

    return {'total': totalGb, 'used': usedGb};
  }

  Future<Map<String, double>> _getStorageUsage() async {
    final result = await Process.run('df', ['-k', '/']);
    final output = result.stdout as String;
    final lines = output.split('\n');
    if (lines.length > 1) {
      final parts = lines[1].trim().split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        final totalKb = double.tryParse(parts[1]) ?? 0.0;
        final usedKb = double.tryParse(parts[2]) ?? 0.0;
        return {
          'total': totalKb / (1024 * 1024),
          'used': usedKb / (1024 * 1024)
        };
      }
    }
    return {'total': 0.0, 'used': 0.0};
  }

  Future<Map<String, double>> _getNetworkSpeed() async {
    final result = await Process.run('netstat', ['-ib']);
    final output = result.stdout as String;
    
    int totalIn = 0;
    int totalOut = 0;
    
    final lines = output.split('\n');
    // Header typically: Name  Mtu   Network       Address            Ipkts Ierrs    Ibytes    Opkts Oerrs    Obytes  Coll
    // We look for interfaces like en0, en1 (exclude lo0)
    for (var line in lines) {
      if (line.startsWith('en') && !line.contains('lo0')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        // Find indices for Ibytes and Obytes based on heuristics (often columns 6 and 9)
        // A safer way is to count from right because IP addresses can have variable parts
        if (parts.length >= 10) {
          final ibytes = int.tryParse(parts[6]) ?? 0;
          final obytes = int.tryParse(parts[9]) ?? 0;
          totalIn += ibytes;
          totalOut += obytes;
        }
      }
    }

    final now = DateTime.now();
    double mbpsDown = 0.0;
    double mbpsUp = 0.0;

    if (_lastNetworkTime != null) {
      final seconds = now.difference(_lastNetworkTime!).inMilliseconds / 1000.0;
      if (seconds > 0) {
        final inDelta = totalIn - _lastNetworkInBytes;
        final outDelta = totalOut - _lastNetworkOutBytes;
        
        // Convert Bytes/sec to Mbps (Megabits per second)
        mbpsDown = (inDelta * 8) / (1000000 * seconds);
        mbpsUp = (outDelta * 8) / (1000000 * seconds);
      }
    }

    _lastNetworkInBytes = totalIn;
    _lastNetworkOutBytes = totalOut;
    _lastNetworkTime = now;

    return {
      'down': mbpsDown > 0 ? mbpsDown : 0.0,
      'up': mbpsUp > 0 ? mbpsUp : 0.0
    };
  }
}

final desktopTelemetryProvider = Provider<DesktopTelemetryService>((ref) {
  return DesktopTelemetryService(ref);
});
