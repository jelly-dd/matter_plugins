import 'package:permission_handler/permission_handler.dart';

/// Matter BLE 配网所需的运行时权限申请。
///
/// Android 12（API 31）起，BLE 扫描/连接必须动态申请 `BLUETOOTH_SCAN` /
/// `BLUETOOTH_CONNECT`，否则扫描会静默失败，配网连不上设备。
/// 更早的版本则依赖定位权限（`ACCESS_FINE_LOCATION`）才能扫到 BLE 广播。
///
/// [permission_handler] 会根据系统版本自动映射到正确的底层权限，
/// 这里把两类都请求，覆盖各 Android 版本。
class MatterPermissions {
  const MatterPermissions._();

  /// 申请配网所需的全部权限。
  ///
  /// 返回 true 表示关键权限均已授予，可以进行 BLE 配网。
  static Future<bool> requestForCommissioning() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    // Android 12+ 只要 scan + connect 就够；低版本靠定位。
    final scanOk = _granted(statuses[Permission.bluetoothScan]);
    final connectOk = _granted(statuses[Permission.bluetoothConnect]);
    final locationOk = _granted(statuses[Permission.locationWhenInUse]);

    return (scanOk && connectOk) || locationOk;
  }

  static bool _granted(PermissionStatus? status) =>
      status == PermissionStatus.granted ||
      status == PermissionStatus.limited;
}
