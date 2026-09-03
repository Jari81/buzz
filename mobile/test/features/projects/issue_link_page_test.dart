import 'package:buzz/features/projects/issue_link_page.dart';
import 'package:buzz/features/projects/project_issue_providers.dart';
import 'package:buzz/features/projects/project_issue_reducer.dart';
import 'package:buzz/shared/deeplink/deep_link.dart';
import 'package:buzz/shared/profile/user_cache_provider.dart';
import 'package:buzz/shared/profile/user_profile.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _FakeUserCache extends UserCacheNotifier {
  @override
  Map<String, UserProfile> build() => const {};
}

void main() {
  testWidgets('resolves an issue permalink through the exact issue provider', (
    tester,
  ) async {
    final issue = reduceProjectIssue(
      const NostrEvent(
        id: 'issue-id',
        pubkey: owner,
        createdAt: 100,
        kind: EventKind.issue,
        tags: [
          ['a', '30617:$owner:buzz'],
          ['subject', 'Resolved issue'],
        ],
        content: 'Body',
        sig: '',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          linkedIssueProvider((
            repositoryAddress: '30617:$owner:buzz',
            eventId: 'issue-id',
            reviewAuthority: null,
          )).overrideWith((ref) async => issue),
          userCacheProvider.overrideWith(_FakeUserCache.new),
        ],
        child: MaterialApp(
          home: IssueLinkPage(
            link: const EntityDeepLink(
              type: 'issue',
              owner: owner,
              repository: 'buzz',
              eventId: 'issue-id',
            ),
            contentBuilder: (_, content, _) => Text('rich:$content'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resolved issue'), findsOneWidget);
    expect(find.text('rich:Body'), findsOneWidget);
  });
}
