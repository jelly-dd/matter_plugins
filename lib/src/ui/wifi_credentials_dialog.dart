import 'package:flutter/material.dart';

/// 用户填写的 WiFi 凭据。
class WifiCredentials {
  const WifiCredentials({required this.ssid, required this.password});

  final String ssid;
  final String password;
}

/// 弹出 WiFi 凭据输入对话框。
///
/// Matter WiFi 设备自身没有输入界面，配网时需由 App 把 WiFi 账号密码
/// 通过 BLE 加密通道传给设备，设备再自行连接。因此这里必须让用户手动输入。
///
/// 返回用户填写的凭据；用户取消则返回 null。
Future<WifiCredentials?> showWifiCredentialsDialog(BuildContext context) {
  return showDialog<WifiCredentials>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _WifiCredentialsDialog(),
  );
}

class _WifiCredentialsDialog extends StatefulWidget {
  const _WifiCredentialsDialog();

  @override
  State<_WifiCredentialsDialog> createState() => _WifiCredentialsDialogState();
}

class _WifiCredentialsDialogState extends State<_WifiCredentialsDialog> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return;
    Navigator.of(context).pop(
      WifiCredentials(ssid: ssid, password: _passwordController.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('连接设备到 WiFi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '请输入设备要连接的 WiFi。\n注意：多数 Matter 设备仅支持 2.4GHz。',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ssidController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'WiFi 名称 (SSID)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'WiFi 密码',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
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
