import 'package:flutter/services.dart';

import '../models/matter_device.dart';
import '../models/matter_exception.dart';
import 'matter_backend.dart';

/// 真实平台后端：通过 [MethodChannel] 调用 Android 原生层（Kotlin），
/// 最终由原生层调用 connectedhomeip 的 Matter 协议栈。
///
/// 目前原生层是桩实现（返回假数据），等接入真实库后无需改动本文件。
class PlatformMatterBackend implements MatterBackend {
  static const MethodChannel _channel = MethodChannel('matter_control/methods');

  @override
  Future<MatterDevice> commissionDevice({
    required String setupPayload,
    String? wifiSsid,
    String? wifiPassword,
  }) async {
    final result = await _invoke('commissionDevice', {
      'setupPayload': setupPayload,
      'wifiSsid': wifiSsid,
      'wifiPassword': wifiPassword,
    });
    return MatterDevice.fromMap(_asMap(result));
  }

  @override
  Future<MatterDevice> commissionOnNetwork({
    required String ipAddress,
    required int port,
    required int setupPinCode,
    required int discriminator,
  }) async {
    final result = await _invoke('commissionOnNetwork', {
      'ipAddress': ipAddress,
      'port': port,
      'setupPinCode': setupPinCode,
      'discriminator': discriminator,
    });
    return MatterDevice.fromMap(_asMap(result));
  }

  @override
  Future<List<MatterDevice>> getDevices() async {
    final result = await _invoke('getDevices', {});
    final list = (result as List?) ?? const [];
    return list
        .map((e) => MatterDevice.fromMap(_asMap(e)))
        .toList(growable: false);
  }

  @override
  Future<MatterDevice> setOnOff(String deviceId, bool on) async {
    final result = await _invoke('setOnOff', {'deviceId': deviceId, 'on': on});
    return MatterDevice.fromMap(_asMap(result));
  }

  @override
  Future<MatterDevice> setBrightness(String deviceId, int brightness) async {
    final result = await _invoke('setBrightness', {
      'deviceId': deviceId,
      'brightness': brightness,
    });
    return MatterDevice.fromMap(_asMap(result));
  }

  @override
  Future<void> removeDevice(String deviceId) async {
    await _invoke('removeDevice', {'deviceId': deviceId});
  }

  @override
  Future<Map<String, dynamic>> selfTest() async {
    final result = await _invoke('selfTest', {});
    return _asMap(result);
  }

  Future<Object?> _invoke(String method, Map<String, dynamic> args) async {
    try {
      return await _channel.invokeMethod(method, args);
    } on PlatformException catch (e) {
      throw MatterException(e.code, e.message ?? '原生调用失败');
    } on MissingPluginException {
      throw const MatterException(
        'plugin_not_available',
        '原生 Matter 插件未就绪（当前可能未接入 connectedhomeip 库）',
      );
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    throw const MatterException('bad_response', '原生返回数据格式不正确');
  }
}
