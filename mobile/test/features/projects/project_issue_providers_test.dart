import 'package:buzz/features/projects/project_issue_providers.dart';
import 'package:buzz/features/projects/project_issue_repository.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _FakeRelaySession extends RelaySessionNotifier {
  int queryCount = 0;

  @override
  SessionState build() => const SessionState(status: SessionStatus.connected);

  @override
  Future<List<NostrEvent>> queryRelay(
    List<NostrFilter> filters, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    queryCount++;
    if (filters.first.kinds.contains(EventKind.projectAnnouncement)) {
      return [
        NostrEvent(
          id: 'project',
          pubkey: owner,
          createdAt: 100,
          kind: EventKind.projectAnnouncement,
          tags: const [
            ['d', 'mobile'],
            ['buzz-visibility', 'listed'],
            ['a', '${EventKind.repositoryAnnouncement}:$owner:app'],
          ],
          content: '',
          sig: '',
        ),
      ];
    }
    return [
      NostrEvent(
        id: 'repository',
        pubkey: owner,
        createdAt: 100,
        kind: EventKind.repositoryAnnouncement,
        tags: const [
          ['d', 'app'],
          ['name', 'App'],
        ],
        content: '',
        sig: '',
      ),
    ];
  }
}

void main() {
  test('projects provider uses the authenticated relay session', () async {
    final fakeSession = _FakeRelaySession();
    final container = ProviderContainer(
      overrides: [relaySessionProvider.overrideWith(() => fakeSession)],
    );
    addTearDown(container.dispose);

    final projects = await container.read(projectsProvider.future);

    expect(projects.single.repositories.single.name, 'App');
    expect(fakeSession.queryCount, 2);
  });

  test('repository issues provider scopes issues to one repository', () async {
    const address = '${EventKind.repositoryAnnouncement}:$owner:app';
    final issueRootFilters = <NostrFilter>[];
    final repository = ProjectIssueRepository((filters) async {
      if (filters.first.kinds.contains(EventKind.issue)) {
        issueRootFilters.add(filters.first);
        return [
          NostrEvent(
            id: 'issue',
            pubkey: owner,
            createdAt: 100,
            kind: EventKind.issue,
            tags: const [
              ['a', address],
              ['subject', 'Fix mobile'],
            ],
            content: '',
            sig: '',
          ),
        ];
      }
      return const [];
    });
    final container = ProviderContainer(
      overrides: [projectIssueRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final issues = await container.read(
      repositoryIssuesProvider((
        repositoryAddress: address,
        reviewAuthority: null,
      )).future,
    );

    expect(issues.single.title, 'Fix mobile');
    expect(issueRootFilters.single.tags['#a'], isNull);
    expect(issueRootFilters.single.limit, 500);
  });
}
