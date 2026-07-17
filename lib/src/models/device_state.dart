/// 设备的运行时状态（开关、亮度等）。
///
/// 不同类型设备使用的字段不同，未使用的字段保持默认值即可。
class MatterDeviceState {
  /// 是否开启（适用于灯、插座等）。
  final bool on;

  /// 亮度，范围 0-100（适用于可调光灯）。
  final int brightness;

  /// 色相，范围 0-360 度（适用于彩光灯）。
  final int hue;

  /// 饱和度，范围 0-100（适用于彩光灯）。
  final int saturation;

  /// 色温，Matter mireds 值（约 154 冷 .. 500 暖）。
  final int colorTempMireds;

  const MatterDeviceState({
    this.on = false,
    this.brightness = 100,
    this.hue = 0,
    this.saturation = 0,
    this.colorTempMireds = 250,
  });

  MatterDeviceState copyWith({
    bool? on,
    int? brightness,
    int? hue,
    int? saturation,
    int? colorTempMireds,
  }) {
    return MatterDeviceState(
      on: on ?? this.on,
      brightness: brightness ?? this.brightness,
      hue: hue ?? this.hue,
      saturation: saturation ?? this.saturation,
      colorTempMireds: colorTempMireds ?? this.colorTempMireds,
    );
  }

  factory MatterDeviceState.fromMap(Map<String, dynamic> map) {
    return MatterDeviceState(
      on: map['on'] as bool? ?? false,
      brightness: (map['brightness'] as num?)?.toInt() ?? 100,
      hue: (map['hue'] as num?)?.toInt() ?? 0,
      saturation: (map['saturation'] as num?)?.toInt() ?? 0,
      colorTempMireds: (map['colorTempMireds'] as num?)?.toInt() ?? 250,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'on': on,
      'brightness': brightness,
      'hue': hue,
      'saturation': saturation,
      'colorTempMireds': colorTempMireds,
    };
  }

  @override
  String toString() =>
      'MatterDeviceState(on: $on, brightness: $brightness, hue: $hue, '
      'saturation: $saturation, colorTempMireds: $colorTempMireds)';
}
