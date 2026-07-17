import 'dart:async';

import 'backend/matter_backend.dart';
import 'backend/fake_matter_backend.dart';
import 'models/matter_device.dart';

/// 模块对外的统一入口（门面）。
///
/// 正式 App 只需与本类打交道，完全不用了解 MethodChannel / Kotlin / Matter 协议细节。
///
/// 用法示例：
/// ```dart
/// final matter = MatterControl();            // 默认假数据后端
/// final device = await matter.commissionDevice(setupPayload: qr);
/// await matter.setOnOff(device.id, true);
/// matter.devices.listen((list) => print(list));
/// ```
///
/// 切换到真实后端只需：`MatterControl(backend: PlatformMatterBackend())`。
class MatterControl {
  MatterControl({MatterBackend? backend})
    : _backend = backend ?? FakeMatterBackend();

  final MatterBackend _backend;

  final _devicesController = StreamController<List<MatterDevice>>.broadcast();

  List<MatterDevice> _cache = const [];

  /// 已绑定设备列表的实时流。UI 监听它即可自动刷新。
  Stream<List<MatterDevice>> get devices => _devicesController.stream;

  /// 当前缓存的设备列表（同步读取）。
  List<MatterDevice> get currentDevices => List.unmodifiable(_cache);

  /// 从后端刷新设备列表并推送到 [devices] 流。
  Future<List<MatterDevice>> refresh() async {
    _cache = await _backend.getDevices();
    _devicesController.add(_cache);
    return _cache;
  }

  /// 阶段 1 自检：验证原生 Matter 库能否正常加载。
  ///
  /// 返回 `{ ok: bool, version: String?, error: String? }`。
  Future<Map<String, dynamic>> selfTest() => _backend.selfTest();

  /// 扫码配网一个新设备。
  Future<MatterDevice> commissionDevice({
    required String setupPayload,
    String? wifiSsid,
    String? wifiPassword,
  }) async {
    final device = await _backend.commissionDevice(
      setupPayload: setupPayload,
      wifiSsid: wifiSsid,
      wifiPassword: wifiPassword,
    );
    await refresh();
    return device;
  }

  /// 通过 IP 直连配网局域网内的设备（用于连接电脑上的虚拟灯测试）。
  Future<MatterDevice> commissionOnNetwork({
    required String ipAddress,
    required int port,
    required int setupPinCode,
    required int discriminator,
  }) async {
    final device = await _backend.commissionOnNetwork(
      ipAddress: ipAddress,
      port: port,
      setupPinCode: setupPinCode,
      discriminator: discriminator,
    );
    await refresh();
    return device;
  }

  /// 打开/关闭设备。
  Future<MatterDevice> setOnOff(String deviceId, bool on) async {
    final device = await _backend.setOnOff(deviceId, on);
    _replaceInCache(device);
    return device;
  }

  /// 设置亮度（0-100）。
  Future<MatterDevice> setBrightness(String deviceId, int brightness) async {
    final device = await _backend.setBrightness(deviceId, brightness);
    _replaceInCache(device);
    return device;
  }

  /// 设置彩光颜色。[hue] 0-360 度，[saturation] 0-100。
  Future<MatterDevice> setColor(
    String deviceId,
    int hue,
    int saturation,
  ) async {
    final device = await _backend.setColor(deviceId, hue, saturation);
    _replaceInCache(device);
    return device;
  }

  /// 设置色温（暖冷光）。[mireds] 为 Matter mireds 值（约 154 冷 .. 500 暖）。
  Future<MatterDevice> setColorTemperature(String deviceId, int mireds) async {
    final device = await _backend.setColorTemperature(deviceId, mireds);
    _replaceInCache(device);
    return device;
  }

  /// 解绑设备。
  Future<void> removeDevice(String deviceId) async {
    await _backend.removeDevice(deviceId);
    await refresh();
  }

  void _replaceInCache(MatterDevice device) {
    final index = _cache.indexWhere((d) => d.id == device.id);
    if (index != -1) {
      final updated = List<MatterDevice>.from(_cache);
      updated[index] = device;
      _cache = updated;
      _devicesController.add(_cache);
    }
  }

  /// 释放资源。
  void dispose() {
    _devicesController.close();
  }
}
