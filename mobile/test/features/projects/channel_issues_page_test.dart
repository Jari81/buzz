import 'package:buzz/features/projects/channel_issues_page.dart';
import 'package:buzz/features/projects/project_issue_providers.dart';
import 'package:buzz/features/projects/project_issue_reducer.dart';
import 'package:buzz/features/projects/project_models.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

ProjectIssue issue(String id, String title, String address) =>
    reduceProjectIssue(
      NostrEvent(
        id: id,
        pubkey: owner,
        createdAt: 100,
        kind: EventKind.issue,
        tags: [
          ['a', address],
          ['subject', title],
        ],
        content: '',
        sig: '',
      ),
    );

void main() {
  testWidgets('shows issues only from repositories bound to the channel', (
    tester,
  ) async {
    const boundCoordinate = RepositoryCoordinate(owner: owner, dtag: 'bound');
    const otherCoordinate = RepositoryCoordinate(owner: owner, dtag: 'other');
    final boundRepository = ProjectRepository(
      coordinate: boundCoordinate,
      name: 'Bound repo',
      description: '',
      channelId: 'channel-a',
      createdAt: 100,
      isAvailable: true,
    );
    final otherRepository = ProjectRepository(
      coordinate: otherCoordinate,
      name: 'Other repo',
      description: '',
      channelId: 'channel-b',
      createdAt: 100,
      isAvailable: true,
    );
    final boundIssue = issue(
      'bound-issue',
      'Bound issue',
      boundCoordinate.value,
    );
    final otherIssue = issue(
      'other-issue',
      'Other issue',
      otherCoordinate.value,
    );
    ProjectIssue? tapped;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith(
            (ref) async => [
              MobileProject(
                address: '30621:$owner:project',
                dtag: 'project',
                owner: owner,
                name: 'Project',
                description: '',
                createdAt: 100,
                repositories: [boundRepository, otherRepository],
              ),
            ],
          ),
          repositoryIssuesProvider((
            repositoryAddress: boundCoordinate.value,
            reviewAuthority: null,
          )).overrideWith((ref) async => [boundIssue]),
          repositoryIssuesProvider((
            repositoryAddress: otherCoordinate.value,
            reviewAuthority: null,
          )).overrideWith((ref) async => [otherIssue]),
        ],
        child: MaterialApp(
          home: ChannelIssuesPage(
            channelId: 'channel-a',
            onIssueTap: (value) => tapped = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bound repo'), findsOneWidget);
    expect(find.text('Bound issue'), findsOneWidget);
    expect(find.text('Other issue'), findsNothing);

    await tester.tap(find.text('Bound issue'));
    expect(tapped, same(boundIssue));
  });
}
