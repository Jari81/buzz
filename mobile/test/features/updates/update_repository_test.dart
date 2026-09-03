import 'dart:convert';

import 'package:buzz/features/updates/update_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _origin = 'https://robi-h110n.tail018bca.ts.net';
const _packageId = 'xyz.block.buzz.mobile.projects_updater';
const _certificateSha256 =
    '17745a13ffe9c32190d5257f4a31ff6ae72662f77dbc668288ff99665d85bcae';

void main() {
  test(
    'checks the fixed manifest location for a newer trusted candidate',
    () async {
      Uri? requestedUri;
      final repository = UpdateRepository(
        manifestUri: Uri.parse('$_origin/buzz-mobile/latest.json'),
        expectedPackageId: _packageId,
        expectedCertificateSha256: _certificateSha256,
        fetchManifest: (uri) async {
          requestedUri = uri;
          return jsonEncode({
            'schema': 1,
            'packageId': _packageId,
            'versionCode': 2,
            'versionName': '0.0.0+2',
            'apkUrl': '$_origin/buzz-mobile/releases/2/app.apk',
            'sha256':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'sizeBytes': 1024,
            'certificateSha256': _certificateSha256,
            'builtFrom': '0123456789abcdef0123456789abcdef01234567',
            'publishedAt': '2026-08-30T09:00:00Z',
          });
        },
      );

      final candidate = await repository.check(installedVersionCode: 1);

      expect(requestedUri, Uri.parse('$_origin/buzz-mobile/latest.json'));
      expect(candidate.versionCode, 2);
    },
  );
}
