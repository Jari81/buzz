import 'package:buzz/features/projects/project_issue_providers.dart';
import 'package:buzz/features/projects/project_issue_reducer.dart';
import 'package:buzz/features/projects/project_models.dart';
import 'package:buzz/features/projects/repository_issues_page.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  testWidgets('shows read-only issue state and opens the selected issue', (
    tester,
  ) async {
    final repository = ProjectRepository(
      coordinate: const RepositoryCoordinate(owner: owner, dtag: 'app'),
      name: 'App',
      description: '',
      channelId: 'channel',
      createdAt: 100,
      isAvailable: true,
    );
    final root = NostrEvent(
      id: 'issue',
      pubkey: owner,
      createdAt: 100,
      kind: EventKind.issue,
      tags: [
        ['a', repository.coordinate.value],
        ['subject', 'Fix mobile'],
      ],
      content: 'Read-only body',
      sig: '',
    );
    final issue = reduceProjectIssue(
      root,
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
    );
    ProjectIssue? tapped;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryIssuesProvider((
            repositoryAddress: repository.coordinate.value,
            reviewAuthority: null,
          )).overrideWith((ref) async => [issue]),
        ],
        child: MaterialApp(
          home: RepositoryIssuesPage(
            repository: repository,
            onIssueTap: (value) => tapped = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('App issues'), findsOneWidget);
    expect(find.text('Fix mobile'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Fix mobile'));
    expect(tapped, same(issue));
  });
}
