import 'dart:convert';

import 'package:buzz/features/updates/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _origin = 'https://robi-h110n.tail018bca.ts.net';
const _packageId = 'xyz.block.buzz.mobile.projects_updater';
const _certificateSha256 =
    '17745a13ffe9c32190d5257f4a31ff6ae72662f77dbc668288ff99665d85bcae';
const _apkSha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

String _manifestJson({
  String origin = _origin,
  String packageId = _packageId,
  int versionCode = 2,
  String certificateSha256 = _certificateSha256,
}) => jsonEncode({
  'schema': 1,
  'packageId': packageId,
  'versionCode': versionCode,
  'versionName': '0.0.0+2',
  'apkUrl': '$origin/buzz-mobile/projects-updater/v2.apk',
  'sha256': _apkSha256,
  'sizeBytes': 1024,
  'certificateSha256': certificateSha256,
  'builtFrom': '0123456789abcdef0123456789abcdef01234567',
  'publishedAt': '2026-08-30T09:00:00Z',
});

void main() {
  group('UpdateManifest.parse', () {
    test('accepts a newer candidate from the configured origin', () {
      final manifest = UpdateManifest.parse(
        _manifestJson(),
        expectedOrigin: Uri.parse(_origin),
        expectedPackageId: _packageId,
        expectedCertificateSha256: _certificateSha256,
        installedVersionCode: 1,
      );

      expect(manifest.versionCode, 2);
      expect(
        manifest.apkUri,
        Uri.parse('$_origin/buzz-mobile/projects-updater/v2.apk'),
      );
      expect(manifest.sizeBytes, 1024);
    });

    test('rejects an APK URL outside the configured origin', () {
      expect(
        () => UpdateManifest.parse(
          _manifestJson(origin: 'https://download.example'),
          expectedOrigin: Uri.parse(_origin),
          expectedPackageId: _packageId,
          expectedCertificateSha256: _certificateSha256,
          installedVersionCode: 1,
        ),
        throwsA(isA<UpdateManifestException>()),
      );
    });

    test('rejects a non-newer version', () {
      expect(
        () => UpdateManifest.parse(
          _manifestJson(versionCode: 1),
          expectedOrigin: Uri.parse(_origin),
          expectedPackageId: _packageId,
          expectedCertificateSha256: _certificateSha256,
          installedVersionCode: 1,
        ),
        throwsA(isA<UpdateManifestException>()),
      );
    });
  });
}
