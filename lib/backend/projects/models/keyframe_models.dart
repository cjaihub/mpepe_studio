import 'package:uuid/uuid.dart';

enum KeyframeEasing {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  bezier,
  custom,
}

class Keyframe {
  final String id;
  final String property; // e.g. 'transform.positionX'
  final double time;
  final dynamic value;
  final KeyframeEasing easing;
  
  // For bezier / custom curves
  final List<double>? curveParameters;

  Keyframe({
    String? id,
    required this.property,
    required this.time,
    required this.value,
    this.easing = KeyframeEasing.linear,
    this.curveParameters,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'property': property,
    'time': time,
    'value': value,
    'easing': easing.index,
    'curveParameters': curveParameters,
  };

  factory Keyframe.fromJson(Map<String, dynamic> json) {
    KeyframeEasing parsedEasing = KeyframeEasing.linear;
    if (json['easing'] != null) {
      if (json['easing'] is int) {
        parsedEasing = KeyframeEasing.values[json['easing']];
      } else if (json['easing'] is String) {
        // Fallback for old data
        final str = json['easing'] as String;
        if (str == 'easeIn') {
          parsedEasing = KeyframeEasing.easeIn;
        } else if (str == 'easeOut') parsedEasing = KeyframeEasing.easeOut;
        else if (str == 'easeInOut') parsedEasing = KeyframeEasing.easeInOut;
      }
    }
    
    return Keyframe(
      id: json['id'],
      property: json['property'] ?? '',
      time: (json['time'] ?? 0.0).toDouble(),
      value: json['value'],
      easing: parsedEasing,
      curveParameters: (json['curveParameters'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
    );
  }
}

class TrackingData {
  final String id;
  final String targetType; // 'subject', 'face', 'object'
  final Map<double, Map<String, double>> points; // time -> {x, y, scale}
  final double confidence;

  TrackingData({
    String? id, 
    required this.targetType, 
    required this.points,
    this.confidence = 1.0,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'targetType': targetType,
    'confidence': confidence,
    // Note: points need complex serialization, simplified here
    'points': points.map((k, v) => MapEntry(k.toString(), v)),
  };

  factory TrackingData.fromJson(Map<String, dynamic> json) {
    var rawPoints = json['points'] as Map<String, dynamic>? ?? {};
    var parsedPoints = <double, Map<String, double>>{};
    for (var entry in rawPoints.entries) {
      double t = double.tryParse(entry.key) ?? 0.0;
      var values = entry.value as Map<String, dynamic>;
      parsedPoints[t] = values.map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    return TrackingData(
      id: json['id'],
      targetType: json['targetType'] ?? 'subject',
      confidence: (json['confidence'] ?? 1.0).toDouble(),
      points: parsedPoints,
    );
  }
}
