import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 用户填写的 On-Network(IP 直连) 配网参数。
class NetworkCommissionParams {
  const NetworkCommissionParams({
    required this.ip,
    required this.port,
    required this.pin,
    required this.discriminator,
  });

  final String ip;
  final int port;
  final int pin;
  final int discriminator;
}

/// 弹出「网络配网」对话框，用于连接局域网内的虚拟灯（chip-lighting-app）。
///
/// 与 WiFi/BLE 配网不同：设备已在局域网中，App 直接用 IP + 端口 + 配对参数
/// 建立 PASE 通道入网，无需蓝牙。默认值填的是虚拟灯的常用出厂参数。
///
/// 返回用户填写的参数；用户取消则返回 null。
Future<NetworkCommissionParams?> showNetworkCommissionDialog(
  BuildContext context,
) {
  return showDialog<NetworkCommissionParams>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _NetworkCommissionDialog(),
  );
}

class _NetworkCommissionDialog extends StatefulWidget {
  const _NetworkCommissionDialog();

  @override
  State<_NetworkCommissionDialog> createState() =>
      _NetworkCommissionDialogState();
}

class _NetworkCommissionDialogState extends State<_NetworkCommissionDialog> {
  // 默认值对应虚拟灯出厂参数（端口 5540 / PIN 20202021 / discriminator 3840）。
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '5540');
  final _pinController = TextEditingController(text: '20202021');
  final _discriminatorController = TextEditingController(text: '3840');

  String? _error;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _pinController.dispose();
    _discriminatorController.dispose();
    super.dispose();
  }

  void _submit() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() => _error = '请填写虚拟灯所在电脑的局域网 IP');
      return;
    }
    final port = int.tryParse(_portController.text.trim());
    final pin = int.tryParse(_pinController.text.trim());
    final discriminator = int.tryParse(_discriminatorController.text.trim());
    if (port == null || pin == null || discriminator == null) {
      setState(() => _error = '端口 / PIN / discriminator 必须是数字');
      return;
    }
    Navigator.of(context).pop(
      NetworkCommissionParams(
        ip: ip,
        port: port,
        pin: pin,
        discriminator: discriminator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('网络配网（虚拟灯）'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '直接通过 IP 连接局域网内运行的虚拟灯，无需蓝牙。\n'
              '请确保手机与电脑在同一 WiFi 下。',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              autofocus: true,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: '电脑局域网 IP',
                hintText: '例如 192.168.1.20',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '端口',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _discriminatorController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Discriminator',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '配对 PIN',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('开始配网'),
        ),
      ],
    );
  }
}
