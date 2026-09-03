import 'dart:io';

import 'package:buzz/features/updates/update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens only a verified APK file through the injected installer', () async {
    File? opened;
    final installer = UpdateInstaller(
      openApk: (file) async {
        opened = file;
        return true;
      },
    );
    final apk = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}mybuzz-verified.apk',
    );
    await apk.writeAsBytes([0]);
    addTearDown(() => apk.delete());

    await installer.install(apk);

    expect(opened, apk);
  });
}
