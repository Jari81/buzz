import 'dart:async';

import 'package:buzz/features/projects/issue_detail_page.dart';
import 'package:buzz/features/projects/issue_status.dart';
import 'package:buzz/features/projects/project_issue_reducer.dart';
import 'package:buzz/features/projects/project_issue_repository.dart';
import 'package:buzz/features/projects/project_models.dart';
import 'package:buzz/shared/mentions/agent_identity_provider.dart';
import 'package:buzz/shared/profile/user_cache_provider.dart';
import 'package:buzz/shared/profile/user_profile.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const author =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const assignee =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const address = '${EventKind.repositoryAnnouncement}:$owner:app';

class _FakeUserCache extends UserCacheNotifier {
  @override
  Map<String, UserProfile> build() => const {
    author: UserProfile(pubkey: author, displayName: 'Alice'),
    assignee: UserProfile(pubkey: assignee, displayName: 'Bob'),
  };
}

void main() {
  testWidgets('renders complete read-only issue detail with rich content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final issue = reduceProjectIssue(
      NostrEvent(
        id: 'issue',
        pubkey: author,
        createdAt: 100,
        kind: EventKind.issue,
        tags: const [
          ['a', address],
          ['subject', 'Fix mobile'],
          ['t', 'bug'],
          ['imeta', 'url https://example.test/body.png'],
        ],
        content: 'Body text',
        sig: '',
      ),
      reviewAuthority: const ProjectReviewAuthority(
        coordinatorPubkeys: [owner],
        humanPubkeys: [owner, assignee],
      ),
      statusEvents: [
        NostrEvent(
          id: 'done',
          pubkey: owner,
          createdAt: 200,
          kind: EventKind.issueDone,
          tags: const [
            ['e', 'issue', '', 'root'],
          ],
          content: '',
          sig: '',
        ),
      ],
      commentEvents: [
        NostrEvent(
          id: 'assignment',
          pubkey: owner,
          createdAt: 150,
          kind: EventKind.note,
          tags: const [
            ['e', 'issue', '', 'root'],
            ['p', assignee],
            ['t', 'assignment'],
          ],
          content: 'Assigned',
          sig: '',
        ),
        NostrEvent(
          id: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          pubkey: owner,
          createdAt: 250,
          kind: EventKind.note,
          tags: const [
            ['e', 'issue', '', 'root'],
            ['a', address],
            ['t', 'review-ready'],
            ['review', 'review-42'],
            [
              'review-root',
              'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
            ],
            ['p', owner],
            ['p', assignee],
          ],
          content: '''[REVIEW-READY]
Review-ID: review-42
Target: commit-abc
Evidence: focused tests are green
Test: Install the APK and open Projects.
Known limitations: none''',
          sig: '',
        ),
        NostrEvent(
          id: 'comment',
          pubkey: author,
          createdAt: 220,
          kind: EventKind.note,
          tags: const [
            ['e', 'issue', '', 'root'],
            ['imeta', 'url https://example.test/comment.png'],
          ],
          content: 'Comment text',
          sig: '',
        ),
      ],
    );
    final renderedTags = <List<List<String>>>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [userCacheProvider.overrideWith(_FakeUserCache.new)],
        child: MaterialApp(
          home: IssueDetailPage(
            issue: issue,
            contentBuilder: (context, content, tags) {
              renderedTags.add(tags);
              return Text('rich:$content');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fix mobile'), findsOneWidget);
    expect(find.text('In review'), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('review-42'), findsOneWidget);
    expect(find.text('commit-abc'), findsOneWidget);
    expect(find.text('Install the APK and open Projects.'), findsOneWidget);
    expect(find.text('rich:Body text'), findsOneWidget);
    expect(find.text('rich:Comment text'), findsOneWidget);
    expect(renderedTags, hasLength(2));
    expect(renderedTags.first.last.first, 'imeta');
    expect(renderedTags.last.last.first, 'imeta');
  });

}
