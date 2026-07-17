import '../models/matter_device.dart';

/// Matter 控制后端的统一抽象接口。
///
/// 这是模块可迁移、可替换的核心：
/// - 现在用 [FakeMatterBackend] 返回假数据，UI 可以先跑通。
/// - 将来接入真实 Matter 库时，只需实现一个 [PlatformMatterBackend]（走原生通道），
///   UI 和上层业务代码完全不用改动。
abstract class MatterBackend {
  /// 通过扫码得到的配对信息（二维码内容或 11 位配对码）配网一个新设备。
  ///
  /// 成功后返回已绑定的 [MatterDevice]。
  Future<MatterDevice> commissionDevice({
    required String setupPayload,
    String? wifiSsid,
    String? wifiPassword,
  });

  /// 通过 IP 地址直连配网一个「已在局域网中」的设备（On-Network）。
  ///
  /// 与 [commissionDevice] 的区别：不走 BLE、不下发 WiFi 凭据，直接用
  /// 已知的 IP + 端口 + 配对参数建立 PASE 通道并入网。主要用于连接
  /// 电脑上运行的虚拟灯（chip-lighting-app）做测试。
  ///
  /// - [ipAddress] 设备所在的局域网 IP（如 192.168.1.20）
  /// - [port] 设备监听端口，虚拟灯默认 5540
  /// - [setupPinCode] 配对 PIN（虚拟灯默认 20202021）
  /// - [discriminator] 设备识别码（虚拟灯默认 3840）
  Future<MatterDevice> commissionOnNetwork({
    required String ipAddress,
    required int port,
    required int setupPinCode,
    required int discriminator,
  });

  /// 获取当前已绑定的所有设备。
  Future<List<MatterDevice>> getDevices();

  /// 打开/关闭设备。返回更新后的设备。
  Future<MatterDevice> setOnOff(String deviceId, bool on);

  /// 设置亮度（0-100）。返回更新后的设备。
  Future<MatterDevice> setBrightness(String deviceId, int brightness);

  /// 设置彩光颜色。[hue] 0-360 度，[saturation] 0-100。返回更新后的设备。
  Future<MatterDevice> setColor(String deviceId, int hue, int saturation);

  /// 设置色温（暖冷光）。[mireds] 为 Matter mireds 值（约 154 冷 .. 500 暖）。
  Future<MatterDevice> setColorTemperature(String deviceId, int mireds);

  /// 解绑（移除）一个设备。
  Future<void> removeDevice(String deviceId);

  /// 阶段 1 自检：验证真实 Matter 原生库能否正常加载。
  ///
  /// 返回 `{ ok: bool, version: String?, error: String? }`。
  /// 假后端默认返回 ok=true（无原生库）；真实后端会实际加载 .so 验证。
  Future<Map<String, dynamic>> selfTest() async {
    return {'ok': true, 'version': 'fake-backend', 'error': null};
  }
}
