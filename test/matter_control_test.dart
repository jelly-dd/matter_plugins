import 'package:flutter_test/flutter_test.dart';
import 'package:matter_plugins/matter_plugins.dart';

void main() {
  test('MatterControl 使用假后端可正常配网与控制', () async {
    final matter = MatterControl(backend: FakeMatterBackend());
    addTearDown(matter.dispose);

    final device = await matter.commissionDevice(setupPayload: 'MT:TEST');
    expect(device.id, isNotEmpty);
    expect(matter.currentDevices, contains(device));

    final on = await matter.setOnOff(device.id, true);
    expect(on.state.on, isTrue);
  });
}
