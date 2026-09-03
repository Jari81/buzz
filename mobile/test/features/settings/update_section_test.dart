import 'dart:convert';
import 'dart:io';

import 'package:buzz/features/settings/settings_page.dart';
import 'package:buzz/features/updates/update_repository.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('checks for an update only after the user taps the settings row', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'MyBuzz',
      packageName: 'xyz.block.buzz.mobile.projects_updater',
      version: '0.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final prefs = await SharedPreferences.getInstance();
    var calls = 0;
    final repository = UpdateRepository(
      manifestUri: Uri.parse(
        'https://robi-h110n.tail018bca.ts.net/buzz-mobile/latest.json',
      ),
      expectedPackageId: 'xyz.block.buzz.mobile.projects_updater',
      expectedCertificateSha256:
          '17745a13ffe9c32190d5257f4a31ff6ae72662f77dbc668288ff99665d85bcae',
      fetchManifest: (_) async {
        calls += 1;
        return jsonEncode({
          'schema': 1,
          'packageId': 'xyz.block.buzz.mobile.projects_updater',
          'versionCode': 2,
          'versionName': '0.0.0+2',
          'apkUrl':
              'https://robi-h110n.tail018bca.ts.net/buzz-mobile/releases/2/app.apk',
          'sha256':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'sizeBytes': 1024,
          'certificateSha256':
              '17745a13ffe9c32190d5257f4a31ff6ae72662f77dbc668288ff99665d85bcae',
          'builtFrom': '0123456789abcdef0123456789abcdef01234567',
          'publishedAt': '2026-08-30T09:00:00Z',
        });
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [savedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SettingsPage(
            profileHeader: const SizedBox.shrink(),
            invitePageBuilder: (_) => const SizedBox.shrink(),
            identityRecoveryPageBuilder: (_) => const SizedBox.shrink(),
            updateRepository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('updates-check')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Update 0.0.0+2 is ready'), findsOneWidget);
  });

  testWidgets('downloads and hands a checked update to Android only after tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'MyBuzz',
      packageName: 'xyz.block.buzz.mobile.projects_updater',
      version: '0.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final prefs = await SharedPreferences.getInstance();
    final verifiedApk = File('/virtual/mybuzz-verified.apk');
    final repository = UpdateRepository(
      manifestUri: Uri.parse(
        'https://robi-h110n.tail018bca.ts.net/buzz-mobile/latest.json',
      ),
      expectedPackageId: 'xyz.block.buzz.mobile.projects_updater',
      expectedCertificateSha256:
          '17745a13ffe9c32190d5257f4a31ff6ae72662f77dbc668288ff99665d85bcae',
      fetchManifest: (_) async => jsonEncode({
        'schema': 1,
        'packageId': 'xyz.block.buzz.mobile.projects_updater',
        'versionCode': 2,
        'versionName': '0.0.0+2',
        'apkUrl':
            'https://robi-h110n.tail018bca.ts.net/buzz-mobile/releases/2/app.apk',
        'sha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'sizeBytes': 1024,
        'certificateSha256':
            '17745a13ffe9c32190d5257f4a31ff6ae72662f77dbc668288ff99665d85bcae',
        'builtFrom': '0123456789abcdef0123456789abcdef01234567',
        'publishedAt': '2026-08-30T09:00:00Z',
      }),
    );
    File? installedApk;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [savedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SettingsPage(
            profileHeader: const SizedBox.shrink(),
            invitePageBuilder: (_) => const SizedBox.shrink(),
            identityRecoveryPageBuilder: (_) => const SizedBox.shrink(),
            updateRepository: repository,
            downloadUpdate: (_) async => verifiedApk,
            installUpdate: (apk) async => installedApk = apk,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('updates-check')));
    await tester.pump();
    await tester.pump();
    expect(installedApk, isNull);

    await tester.tap(find.byKey(const ValueKey('updates-install')));
    await tester.pump();
    await tester.pump();

    expect(installedApk, same(verifiedApk));
  });
}
