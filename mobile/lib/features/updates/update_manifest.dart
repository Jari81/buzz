import 'dart:convert';

/// A single immutable Android update candidate from the private release origin.
class UpdateManifest {
  const UpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkUri,
    required this.sha256,
    required this.sizeBytes,
    required this.certificateSha256,
    required this.builtFrom,
    required this.publishedAt,
  });

  final int versionCode;
  final String versionName;
  final Uri apkUri;
  final String sha256;
  final int sizeBytes;
  final String certificateSha256;
  final String builtFrom;
  final DateTime publishedAt;

  /// Parses one manifest and rejects every candidate outside the update trust
  /// boundary before any APK bytes are downloaded.
  factory UpdateManifest.parse(
    String source, {
    required Uri expectedOrigin,
    required String expectedPackageId,
    required String expectedCertificateSha256,
    required int installedVersionCode,
  }) {
    if (expectedOrigin.scheme != 'https' || expectedOrigin.host.isEmpty) {
      throw const UpdateManifestException(
        'The configured update origin is invalid.',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const UpdateManifestException(
        'The update manifest is not valid JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateManifestException(
        'The update manifest must be an object.',
      );
    }

    T read<T>(String key) {
      final value = decoded[key];
      if (value is! T) {
        throw UpdateManifestException(
          'The update manifest field $key is invalid.',
        );
      }
      return value;
    }

    if (read<int>('schema') != 1) {
      throw const UpdateManifestException(
        'The update manifest schema is unsupported.',
      );
    }
    if (read<String>('packageId') != expectedPackageId) {
      throw const UpdateManifestException(
        'The update package does not match this app.',
      );
    }

    final versionCode = read<int>('versionCode');
    if (versionCode <= installedVersionCode) {
      throw const UpdateManifestException(
        'The update is not newer than the installed app.',
      );
    }

    final apkUri = Uri.tryParse(read<String>('apkUrl'));
    if (apkUri == null || !_isSameOrigin(apkUri, expectedOrigin)) {
      throw const UpdateManifestException(
        'The APK URL is outside the private update origin.',
      );
    }

    final sha256 = read<String>('sha256');
    final certificateSha256 = read<String>('certificateSha256');
    if (!_isLowercaseSha256(sha256) ||
        !_isLowercaseSha256(certificateSha256) ||
        certificateSha256 != expectedCertificateSha256) {
      throw const UpdateManifestException(
        'The update certificate or checksum is invalid.',
      );
    }

    final sizeBytes = read<int>('sizeBytes');
    if (sizeBytes <= 0 || sizeBytes > _maximumApkBytes) {
      throw const UpdateManifestException(
        'The APK size is outside the allowed range.',
      );
    }

    final builtFrom = read<String>('builtFrom');
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(builtFrom)) {
      throw const UpdateManifestException(
        'The update build identity is invalid.',
      );
    }

    final DateTime publishedAt;
    try {
      publishedAt = DateTime.parse(read<String>('publishedAt')).toUtc();
    } on FormatException {
      throw const UpdateManifestException(
        'The update publication time is invalid.',
      );
    }

    return UpdateManifest(
      versionCode: versionCode,
      versionName: read<String>('versionName'),
      apkUri: apkUri,
      sha256: sha256,
      sizeBytes: sizeBytes,
      certificateSha256: certificateSha256,
      builtFrom: builtFrom,
      publishedAt: publishedAt,
    );
  }

  static const _maximumApkBytes = 512 * 1024 * 1024;

  static bool _isSameOrigin(Uri candidate, Uri origin) =>
      candidate.scheme == 'https' &&
      candidate.scheme == origin.scheme &&
      candidate.host == origin.host &&
      candidate.port == origin.port &&
      candidate.userInfo.isEmpty;

  static bool _isLowercaseSha256(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

/// A release candidate failed the app's immutable update trust contract.
class UpdateManifestException implements Exception {
  const UpdateManifestException(this.message);

  final String message;

  @override
  String toString() => 'UpdateManifestException: $message';
}
