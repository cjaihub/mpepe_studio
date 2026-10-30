/// Hardware capability tier representing device compute class.
enum DeviceHardwareTier {
  low,
  medium,
  high;

  static DeviceHardwareTier fromString(String? value) {
    if (value == null) return DeviceHardwareTier.medium;
    return switch (value.toLowerCase().trim()) {
      'high' => DeviceHardwareTier.high,
      'low' => DeviceHardwareTier.low,
      _ => DeviceHardwareTier.medium,
    };
  }

  bool get isHigh => this == DeviceHardwareTier.high;
  bool get isMedium => this == DeviceHardwareTier.medium;
  bool get isLow => this == DeviceHardwareTier.low;

  String get label => switch (this) {
        DeviceHardwareTier.high => 'Pro Tier (High)',
        DeviceHardwareTier.medium => 'Standard Tier (Medium)',
        DeviceHardwareTier.low => 'Efficiency Tier (Low)',
      };

  int get maxRecommendedLutSize => switch (this) {
        DeviceHardwareTier.high => 65,
        DeviceHardwareTier.medium => 33,
        DeviceHardwareTier.low => 17,
      };

  int get maxRealtimeLutStack => switch (this) {
        DeviceHardwareTier.high => 4,
        DeviceHardwareTier.medium => 2,
        DeviceHardwareTier.low => 1,
      };
}
