import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_manifest.dart';

typedef UpdateDownloadRequest = Future<http.StreamedResponse> Function(Uri uri);
typedef UpdateTemporaryDirectory = Future<Directory> Function();
typedef UpdateDownload = Future<File> Function(UpdateManifest manifest);

/// Downloads one already trusted manifest candidate and verifies its bytes.
class UpdateDownloader {
  UpdateDownloader({
    required this.request,
    UpdateTemporaryDirectory? temporaryDirectory,
  }) : temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  factory UpdateDownloader.privateRelease() =>
      UpdateDownloader(request: _fetchPrivateApk);

  static final http.Client _privateClient = http.Client();

  static Future<http.StreamedResponse> _fetchPrivateApk(Uri uri) {
    final request = http.Request('GET', uri)..followRedirects = false;
    return _privateClient.send(request);
  }

  final UpdateDownloadRequest request;
  final UpdateTemporaryDirectory temporaryDirectory;

  Future<File> download(UpdateManifest manifest) async {
    final response = await request(manifest.apkUri);
    if (response.statusCode != 200) {
      throw UpdateDownloadException(
        'The APK download returned HTTP ${response.statusCode}.',
      );
    }
    if (response.contentLength != null &&
        response.contentLength != manifest.sizeBytes) {
      throw const UpdateDownloadException(
        'The APK download has an unexpected size.',
      );
    }

    final directory = await temporaryDirectory();
    final basename = 'mybuzz-update-${manifest.versionCode}';
    final temporaryFile = File(
      '${directory.path}${Platform.pathSeparator}$basename.part',
    );
    final apkFile = File(
      '${directory.path}${Platform.pathSeparator}$basename.apk',
    );
    final sink = temporaryFile.openWrite();
    final digestSink = _DigestSink();
    final hashSink = sha256.startChunkedConversion(digestSink);
    var hashClosed = false;
    var fileClosed = false;
    var writtenBytes = 0;

    try {
      await for (final bytes in response.stream) {
        writtenBytes += bytes.length;
        if (writtenBytes > manifest.sizeBytes) {
          throw const UpdateDownloadException(
            'The APK download exceeds its manifest size.',
          );
        }
        hashSink.add(bytes);
        sink.add(bytes);
      }
      hashSink.close();
      hashClosed = true;
      await sink.close();
      fileClosed = true;

      final digest = digestSink.value?.toString();
      if (writtenBytes != manifest.sizeBytes || digest != manifest.sha256) {
        throw const UpdateDownloadException(
          'The downloaded APK did not match its manifest.',
        );
      }
      if (await apkFile.exists()) await apkFile.delete();
      return temporaryFile.rename(apkFile.path);
    } catch (_) {
      if (!hashClosed) hashSink.close();
      if (!fileClosed) await sink.close();
      if (await temporaryFile.exists()) await temporaryFile.delete();
      rethrow;
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Downloaded bytes did not meet the immutable release manifest contract.
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => 'UpdateDownloadException: $message';
}
