import 'device_state.dart';

/// 表示一个已配网（绑定）的 Matter 设备。
///
/// 这是模块对外暴露的核心数据结构。正式 App 拿到它后即可展示和控制设备。
class MatterDevice {
  /// 设备在本地控制器中的唯一标识（配网时分配的 node id）。
  final String id;

  /// 设备名称（可由用户命名，默认取设备类型）。
  final String name;

  /// 设备类型，例如 onOffLight、onOffPlug 等。
  final MatterDeviceType type;

  /// 设备当前状态（开关、亮度等）。
  final MatterDeviceState state;

  /// 设备是否在线可达。
  final bool online;

  const MatterDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.state,
    this.online = true,
  });

  MatterDevice copyWith({
    String? id,
    String? name,
    MatterDeviceType? type,
    MatterDeviceState? state,
    bool? online,
  }) {
    return MatterDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      state: state ?? this.state,
      online: online ?? this.online,
    );
  }

  factory MatterDevice.fromMap(Map<String, dynamic> map) {
    return MatterDevice(
      id: map['id'] as String,
      name: map['name'] as String? ?? '未命名设备',
      type: MatterDeviceType.fromWire(map['type'] as String?),
      state: MatterDeviceState.fromMap(
        (map['state'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      online: map['online'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.wire,
      'state': state.toMap(),
      'online': online,
    };
  }

  @override
  String toString() =>
      'MatterDevice(id: $id, name: $name, type: ${type.wire}, online: $online, state: $state)';
}

/// Matter 设备类型（对应 Matter 的 device type）。
///
/// 先覆盖最常见的几类，后续接入真实库时可继续扩展。
enum MatterDeviceType {
  onOffLight('on_off_light', '灯'),
  dimmableLight('dimmable_light', '可调光灯'),
  colorLight('color_light', '彩光灯'),
  onOffPlug('on_off_plug', '插座'),
  contactSensor('contact_sensor', '门窗传感器'),
  temperatureSensor('temperature_sensor', '温度传感器'),
  unknown('unknown', '未知设备');

  const MatterDeviceType(this.wire, this.label);

  /// 用于跨平台通道传输的字符串标识。
  final String wire;

  /// 用于 UI 展示的中文名称。
  final String label;

  static MatterDeviceType fromWire(String? wire) {
    return MatterDeviceType.values.firstWhere(
      (t) => t.wire == wire,
      orElse: () => MatterDeviceType.unknown,
    );
  }

  /// 该类型是否支持开关控制。
  bool get supportsOnOff =>
      this == onOffLight ||
      this == dimmableLight ||
      this == colorLight ||
      this == onOffPlug;

  /// 该类型是否支持亮度调节。
  bool get supportsBrightness => this == dimmableLight || this == colorLight;

  /// 该类型是否支持彩光/色温调节。
  bool get supportsColor => this == colorLight;
}
