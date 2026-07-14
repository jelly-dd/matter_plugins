import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../matter_control_base.dart';
import '../matter_permissions.dart';
import '../models/matter_device.dart';
import '../models/matter_exception.dart';
import 'wifi_credentials_dialog.dart';
import 'network_commission_dialog.dart';

/// 添加设备页：扫描 Matter 二维码或手动输入配对码，然后配网。
class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key, required this.controller});

  final MatterControl controller;

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final _manualController = TextEditingController();
  final _scannerController = MobileScannerController();

  bool _commissioning = false;
  bool _handled = false;

  @override
  void dispose() {
    _manualController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || _commissioning) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    _handled = true;
    _commission(code);
  }

  Future<void> _commission(String payload) async {
    setState(() => _commissioning = true);
    try {
      // BLE 配网前先申请运行时权限（Android 12+ 必需）。
      final granted = await MatterPermissions.requestForCommissioning();
      if (!granted) {
        _showError('缺少蓝牙/定位权限，无法进行 BLE 配网。请在系统设置中授予。');
        return;
      }

      // WiFi 设备自身没有输入界面，需由 App 把 WiFi 凭据传给设备。
      if (!mounted) return;
      final wifi = await showWifiCredentialsDialog(context);
      if (wifi == null) {
        // 用户取消。
        return;
      }

      final MatterDevice device = await widget.controller.commissionDevice(
        setupPayload: payload,
        wifiSsid: wifi.ssid,
        wifiPassword: wifi.password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已添加：${device.name}')));
      Navigator.of(context).pop(device);
    } on MatterException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) {
        setState(() => _commissioning = false);
        _handled = false;
      }
    }
  }

  Future<void> _commissionOnNetwork({
    required String ip,
    required int port,
    required int pin,
    required int discriminator,
  }) async {
    setState(() => _commissioning = true);
    try {
      final MatterDevice device = await widget.controller.commissionOnNetwork(
        ipAddress: ip,
        port: port,
        setupPinCode: pin,
        discriminator: discriminator,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已添加：${device.name}')));
      Navigator.of(context).pop(device);
    } on MatterException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) {
        setState(() => _commissioning = false);
        _handled = false;
      }
    }
  }

  Future<void> _openNetworkDialog() async {
    final params = await showNetworkCommissionDialog(context);
    if (params == null) return;
    await _commissionOnNetwork(
      ip: params.ip,
      port: params.port,
      pin: params.pin,
      discriminator: params.discriminator,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('配网失败：$message'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加设备'),
        actions: [
          IconButton(
            tooltip: '网络配网（测试虚拟灯）',
            icon: const Icon(Icons.wifi_find),
            onPressed: _commissioning ? null : _openNetworkDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) =>
                      _ScannerUnavailable(error: error),
                ),
                _ScanOverlay(commissioning: _commissioning),
              ],
            ),
          ),
          _ManualEntry(
            controller: _manualController,
            enabled: !_commissioning,
            onSubmit: () {
              final text = _manualController.text.trim();
              if (text.isNotEmpty) _commission(text);
            },
          ),
        ],
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.commissioning});

  final bool commissioning;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        alignment: Alignment.center,
        color: commissioning ? Colors.black54 : Colors.transparent,
        child: commissioning
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('正在配网，请稍候…', style: TextStyle(color: Colors.white)),
                ],
              )
            : Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
      ),
    );
  }
}

class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white70,
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            '相机不可用，请使用下方手动输入配对码',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ManualEntry extends StatelessWidget {
  const _ManualEntry({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('或手动输入配对码 / 二维码内容'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      hintText: '例如 MT:... 或 11 位配对码',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: enabled ? onSubmit : null,
                  child: const Text('配网'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
