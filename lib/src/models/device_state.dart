/// 设备的运行时状态（开关、亮度等）。
///
/// 不同类型设备使用的字段不同，未使用的字段保持默认值即可。
class MatterDeviceState {
  /// 是否开启（适用于灯、插座等）。
  final bool on;

  /// 亮度，范围 0-100（适用于可调光灯）。
  final int brightness;

  const MatterDeviceState({
    this.on = false,
    this.brightness = 100,
  });

  MatterDeviceState copyWith({
    bool? on,
    int? brightness,
  }) {
    return MatterDeviceState(
      on: on ?? this.on,
      brightness: brightness ?? this.brightness,
    );
  }

  factory MatterDeviceState.fromMap(Map<String, dynamic> map) {
    return MatterDeviceState(
      on: map['on'] as bool? ?? false,
      brightness: (map['brightness'] as num?)?.toInt() ?? 100,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'on': on,
      'brightness': brightness,
    };
  }

  @override
  String toString() => 'MatterDeviceState(on: $on, brightness: $brightness)';
}
