import 'dart:convert';
import 'dart:io';

import 'package:buzz/features/updates/update_downloader.dart';
import 'package:buzz/features/updates/update_manifest.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'buzz-update-test-',
    );
  });
  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('stores an APK only when its byte count and SHA-256 match', () async {
    final bytes = utf8.encode('verified APK bytes');
    final manifest = UpdateManifest(
      versionCode: 2,
      versionName: '0.0.0+2',
      apkUri: Uri.parse('https://updates.example/app.apk'),
      sha256: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
      certificateSha256:
          '17745a13ffe9c32190d5257f4a31ff6ae72662f77dbc668288ff99665d85bcae',
      builtFrom: '0123456789abcdef0123456789abcdef01234567',
      publishedAt: DateTime.utc(2026, 8, 30),
    );
    final downloader = UpdateDownloader(
      request: (_) async => http.StreamedResponse(Stream.value(bytes), 200),
      temporaryDirectory: () async => temporaryDirectory,
    );

    final apk = await downloader.download(manifest);

    expect(await apk.readAsBytes(), bytes);
    expect(apk.path, endsWith('.apk'));
  });
}
