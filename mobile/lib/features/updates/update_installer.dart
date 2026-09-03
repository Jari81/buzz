import 'dart:io';

import 'package:open_filex/open_filex.dart';

typedef OpenApk = Future<bool> Function(File apk);
typedef UpdateInstall = Future<void> Function(File apk);

/// Hands an already verified local APK to Android's normal package installer.
class UpdateInstaller {
  const UpdateInstaller({required this.openApk});

  factory UpdateInstaller.system() => UpdateInstaller(
    openApk: (apk) async {
      final result = await OpenFilex.open(apk.path);
      return result.type == ResultType.done;
    },
  );

  final OpenApk openApk;

  Future<void> install(File apk) async {
    if (!await apk.exists()) {
      throw UpdateInstallException('The verified APK is no longer available.');
    }
    if (!await openApk(apk)) {
      throw const UpdateInstallException(
        'Android could not open the package installer.',
      );
    }
  }
}

/// Android did not accept the handoff to the system package installer.
class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);

  final String message;

  @override
  String toString() => 'UpdateInstallException: $message';
}
