import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'update_manifest.dart';

typedef UpdateManifestFetcher = Future<String> Function(Uri uri);

/// Retrieves the one private update manifest without following redirects.
class UpdateRepository {
  const UpdateRepository({
    required this.manifestUri,
    required this.expectedPackageId,
    required this.expectedCertificateSha256,
    required this.fetchManifest,
  });

  static final privateManifestUri = Uri.parse(
    'https://robi-h110n.tail018bca.ts.net/buzz-mobile/latest.json',
  );
  static const privatePackageId = 'xyz.block.buzz.mobile.projects_updater';
  static const privateCertificateSha256 =
      '17745a13ffe9c32190d5257f4a31ff6ae72662f77dbc668288ff99665d85bcae';

  factory UpdateRepository.privateRelease() => UpdateRepository(
    manifestUri: privateManifestUri,
    expectedPackageId: privatePackageId,
    expectedCertificateSha256: privateCertificateSha256,
    fetchManifest: _fetchPrivateManifest,
  );

  final Uri manifestUri;
  final String expectedPackageId;
  final String expectedCertificateSha256;
  final UpdateManifestFetcher fetchManifest;

  Future<UpdateManifest> check({required int installedVersionCode}) async {
    final source = await fetchManifest(manifestUri);
    return UpdateManifest.parse(
      source,
      expectedOrigin: _originOf(manifestUri),
      expectedPackageId: expectedPackageId,
      expectedCertificateSha256: expectedCertificateSha256,
      installedVersionCode: installedVersionCode,
    );
  }

  static Uri _originOf(Uri uri) => Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );

  static Future<String> _fetchPrivateManifest(Uri uri) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw UpdateTransportException(
          'The update service returned HTTP ${response.statusCode}.',
        );
      }
      return utf8.decode(await response.stream.toBytes());
    } on TimeoutException {
      throw const UpdateTransportException('The update service timed out.');
    } finally {
      client.close();
    }
  }
}

/// The private manifest could not be retrieved without a transport failure.
class UpdateTransportException implements Exception {
  const UpdateTransportException(this.message);

  final String message;

  @override
  String toString() => 'UpdateTransportException: $message';
}
