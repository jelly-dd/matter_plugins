import 'dart:async';

import '../models/matter_device.dart';
import '../models/device_state.dart';
import '../models/matter_exception.dart';
import 'matter_backend.dart';

/// 假数据后端：不连接任何真实 Matter 设备，用于在原生库就绪前先跑通整个 App 流程。
///
/// 行为尽量模拟真实场景：
/// - 配网有几秒延迟（模拟 BLE 握手 + 入网）。
/// - 设备状态保存在内存中，开关/调光会真实改变返回值。
class FakeMatterBackend implements MatterBackend {
  final List<MatterDevice> _devices = [];
  int _counter = 0;

  @override
  Future<MatterDevice> commissionDevice({
    required String setupPayload,
    String? wifiSsid,
    String? wifiPassword,
  }) async {
    if (setupPayload.trim().isEmpty) {
      throw const MatterException('invalid_payload', '配对码为空');
    }

    // 模拟配网耗时（BLE 发现 -> 建立安全通道 -> 下发凭据 -> 入网）。
    await Future.delayed(const Duration(seconds: 3));

    // 根据配对码内容伪造一个设备类型，方便演示不同 UI。
    final type = _guessTypeFromPayload(setupPayload);
    _counter++;
    final device = MatterDevice(
      id: 'fake-node-$_counter',
      name: '${type.label} $_counter',
      type: type,
      state: MatterDeviceState(
        on: false,
        brightness: type.supportsBrightness ? 80 : 100,
      ),
      online: true,
    );
    _devices.add(device);
    return device;
  }

  @override
  Future<MatterDevice> commissionOnNetwork({
    required String ipAddress,
    required int port,
    required int setupPinCode,
    required int discriminator,
  }) async {
    if (ipAddress.trim().isEmpty) {
      throw const MatterException('invalid_address', 'IP 地址为空');
    }
    // 模拟 On-Network 配网耗时（建立 PASE -> 下发凭据 -> CASE 入网）。
    await Future.delayed(const Duration(seconds: 2));
    _counter++;
    final device = MatterDevice(
      id: 'fake-net-$_counter',
      name: '网络灯 $_counter ($ipAddress)',
      type: MatterDeviceType.dimmableLight,
      state: const MatterDeviceState(on: false, brightness: 80),
      online: true,
    );
    _devices.add(device);
    return device;
  }

  @override
  Future<List<MatterDevice>> getDevices() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_devices);
  }

  @override
  Future<MatterDevice> setOnOff(String deviceId, bool on) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _update(
      deviceId,
      (d) => d.copyWith(state: d.state.copyWith(on: on)),
    );
  }

  @override
  Future<MatterDevice> setBrightness(String deviceId, int brightness) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final clamped = brightness.clamp(0, 100);
    return _update(
      deviceId,
      (d) => d.copyWith(
        state: d.state.copyWith(brightness: clamped, on: clamped > 0),
      ),
    );
  }

  @override
  Future<MatterDevice> setColor(
    String deviceId,
    int hue,
    int saturation,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final h = hue.clamp(0, 360);
    final s = saturation.clamp(0, 100);
    return _update(
      deviceId,
      (d) => d.copyWith(
        state: d.state.copyWith(hue: h, saturation: s),
      ),
    );
  }

  @override
  Future<MatterDevice> setColorTemperature(String deviceId, int mireds) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final m = mireds.clamp(1, 65279);
    return _update(
      deviceId,
      (d) => d.copyWith(state: d.state.copyWith(colorTempMireds: m)),
    );
  }

  @override
  Future<void> removeDevice(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _devices.removeWhere((d) => d.id == deviceId);
  }

  @override
  Future<Map<String, dynamic>> selfTest() async {
    // 假后端不加载任何原生库，直接返回成功。
    return {'ok': true, 'version': 'fake-backend', 'error': null};
  }

  MatterDevice _update(
    String deviceId,
    MatterDevice Function(MatterDevice) transform,
  ) {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) {
      throw MatterException('device_not_found', '找不到设备: $deviceId');
    }
    final updated = transform(_devices[index]);
    _devices[index] = updated;
    return updated;
  }

  MatterDeviceType _guessTypeFromPayload(String payload) {
    final lower = payload.toLowerCase();
    if (lower.contains('plug') || lower.contains('socket')) {
      return MatterDeviceType.onOffPlug;
    }
    if (lower.contains('dim') || lower.contains('level')) {
      return MatterDeviceType.dimmableLight;
    }
    if (lower.contains('sensor')) {
      return MatterDeviceType.contactSensor;
    }
    // 默认给一个可调光灯，方便演示最丰富的控制 UI。
    return MatterDeviceType.dimmableLight;
  }
}
