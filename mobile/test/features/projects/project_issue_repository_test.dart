import 'dart:convert';
import 'dart:typed_data';

import 'package:buzz/features/projects/issue_status.dart';
import 'package:buzz/features/projects/project_issue_reducer.dart';
import 'package:buzz/features/projects/project_issue_repository.dart';
import 'package:buzz/features/projects/project_models.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;
import 'package:pointycastle/digests/sha256.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

List<String> authTag(
  nostr.Keys ownerKeys,
  String agentPubkey, {
  String conditions = '',
}) {
  final preimage = utf8.encode('nostr:agent-auth:$agentPubkey:$conditions');
  final digest = SHA256Digest().process(Uint8List.fromList(preimage));
  final message = digest
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  final signature = nostr.Schnorr.sign(
    secretKey: ownerKeys.secret,
    message: message,
  );
  return ['auth', ownerKeys.public, conditions, signature];
}

NostrEvent event({
  required String id,
  required int kind,
  required List<List<String>> tags,
  String pubkey = owner,
  int createdAt = 100,
  String content = '',
}) => NostrEvent(
  id: id,
  pubkey: pubkey,
  createdAt: createdAt,
  kind: kind,
  tags: tags,
  content: content,
  sig: '',
);

void main() {
  test(
    'fetches listed projects then repository members grouped by owner',
    () async {
      final calls = <List<NostrFilter>>[];
      final repository = ProjectIssueRepository((filters) async {
        calls.add(filters);
        if (filters.single.kinds.single == EventKind.projectAnnouncement) {
          return [
            event(
              id: 'project',
              kind: EventKind.projectAnnouncement,
              tags: [
                ['d', 'mobile'],
                ['buzz-visibility', 'listed'],
                ['a', '${EventKind.repositoryAnnouncement}:$owner:app'],
                ['a', '${EventKind.repositoryAnnouncement}:$owner:server'],
              ],
            ),
            event(
              id: 'private-project',
              kind: EventKind.projectAnnouncement,
              tags: [
                ['d', 'private'],
                ['buzz-visibility', 'unlisted'],
                ['a', '${EventKind.repositoryAnnouncement}:$owner:secret'],
              ],
            ),
          ];
        }
        return [
          event(
            id: 'app',
            kind: EventKind.repositoryAnnouncement,
            tags: [
              ['d', 'app'],
              ['name', 'App'],
            ],
          ),
        ];
      });

      final projects = await repository.fetchProjects();

      expect(projects.single.repositories, hasLength(2));
      expect(calls, hasLength(2));
      expect(calls.first.single.kinds, [EventKind.projectAnnouncement]);
      expect(calls.last.single.kinds, [EventKind.repositoryAnnouncement]);
      expect(calls.last.single.authors, [owner]);
      expect(calls.last.single.tags['#d'], ['app', 'server']);
    },
  );

  test(
    'drains project announcement pages before applying visibility',
    () async {
      final projectFilters = <NostrFilter>[];
      final repository = ProjectIssueRepository((filters) async {
        if (filters.single.kinds.single != EventKind.projectAnnouncement) {
          return const [];
        }
        final filter = filters.single;
        projectFilters.add(filter);
        if (filter.until == null) {
          return [
            for (var index = 0; index < 500; index++)
              event(
                id: 'private-$index',
                kind: EventKind.projectAnnouncement,
                createdAt: 1000 - index,
                tags: [
                  ['d', 'private-$index'],
                  ['buzz-visibility', 'unlisted'],
                ],
              ),
          ];
        }
        return [
          event(
            id: 'listed-project',
            kind: EventKind.projectAnnouncement,
            createdAt: 500,
            tags: const [
              ['d', 'listed'],
              ['buzz-visibility', 'listed'],
            ],
          ),
        ];
      });

      final projects = await repository.fetchProjects();

      expect(projectFilters, hasLength(2));
      expect(projectFilters.last.until, 501);
      expect(projects.single.dtag, 'listed');
    },
  );

  test(
    'chunks repository resolution across aggregate owner membership',
    () async {
      final repositoryFilters = <NostrFilter>[];
      final coordinates = [
        for (var index = 0; index < 501; index++)
          '${EventKind.repositoryAnnouncement}:$owner:repo-$index',
      ];
      final repository = ProjectIssueRepository((filters) async {
        if (filters.first.kinds.contains(EventKind.projectAnnouncement)) {
          return [
            for (var projectIndex = 0; projectIndex < 8; projectIndex++)
              event(
                id: 'project-$projectIndex',
                kind: EventKind.projectAnnouncement,
                tags: [
                  ['d', 'project-$projectIndex'],
                  ['buzz-visibility', 'listed'],
                  for (final coordinate
                      in coordinates.skip(projectIndex * 64).take(64))
                    ['a', coordinate],
                ],
              ),
          ];
        }
        repositoryFilters.addAll(filters);
        return [
          for (final filter in filters)
            for (final dtag in (filter.tags['#d'] ?? const <String>[]).take(
              filter.limit,
            ))
              event(
                id: 'repository-$dtag',
                kind: EventKind.repositoryAnnouncement,
                tags: [
                  ['d', dtag],
                  ['name', dtag],
                ],
              ),
        ];
      });

      final projects = await repository.fetchProjects();
      final repositories = [
        for (final project in projects) ...project.repositories,
      ];

      expect(repositories, hasLength(501));
      expect(
        repositories.where((item) => item.name == 'Repository unavailable'),
        isEmpty,
      );
      expect(repositoryFilters, isNotEmpty);
      expect(
        repositoryFilters.every(
          (filter) => (filter.tags['#d']?.length ?? 0) <= 100,
        ),
        isTrue,
      );
    },
  );

  test('fetches scoped issue state and separate assignment history', () async {
    const repositoryAddress = '${EventKind.repositoryAnnouncement}:$owner:app';
    const assignee =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final calls = <List<NostrFilter>>[];
    final repository = ProjectIssueRepository((filters) async {
      calls.add(filters);
      if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
        return [
          event(
            id: 'issue-root',
            kind: EventKind.issue,
            tags: [
              ['a', repositoryAddress],
              ['subject', 'Fix mobile'],
            ],
          ),
        ];
      }
      if (filters.singleOrNull?.kinds.contains(EventKind.issueDone) == true) {
        return [
          event(
            id: 'done',
            kind: EventKind.issueDone,
            createdAt: 200,
            tags: [
              ['e', 'issue-root', '', 'root'],
              ['a', repositoryAddress],
            ],
          ),
        ];
      }
      if (filters.singleOrNull?.kinds.singleOrNull == EventKind.note) {
        return [
          event(
            id: 'assignment',
            kind: EventKind.note,
            tags: [
              ['e', 'issue-root', '', 'root'],
              ['a', repositoryAddress],
              ['p', assignee],
              ['t', 'assignment'],
            ],
          ),
        ];
      }
      return const [];
    });

    final issues = await repository.fetchIssues(repositoryAddress);

    expect(issues.single.title, 'Fix mobile');
    expect(issues.single.assignees, [assignee]);
    expect(issues.single.status.name, 'done');
    expect(calls.first.single.limit, 500);
    expect(calls.first.single.tags['#a'], isNull);
    expect(
      calls.any(
        (call) =>
            call.singleOrNull?.kinds.contains(EventKind.issueDone) == true &&
            call.single.limit == 500,
      ),
      isTrue,
    );
    expect(
      calls.any(
        (call) =>
            call.singleOrNull?.kinds.singleOrNull == EventKind.note &&
            call.single.tags['#t'] == null &&
            call.single.limit == 500,
      ),
      isTrue,
    );
    expect(calls.last.single.tags['#e'], ['issue-root']);
    expect(calls.last.single.tags['#t'], isNull);
  });

  test(
    'enumerates issue roots before applying repository address locally',
    () async {
      const repositoryAddress =
          '${EventKind.repositoryAnnouncement}:$owner:app';
      final issueFilters = <NostrFilter>[];
      final repository = ProjectIssueRepository((filters) async {
        if (filters.singleOrNull?.kinds.singleOrNull != EventKind.issue) {
          return const [];
        }
        final filter = filters.single;
        issueFilters.add(filter);
        if (filter.tags.containsKey('#a')) return const [];
        return [
          event(
            id: 'other-repository',
            kind: EventKind.issue,
            tags: const [
              ['a', '${EventKind.repositoryAnnouncement}:$owner:other'],
            ],
          ),
          event(
            id: 'target-repository',
            kind: EventKind.issue,
            tags: const [
              ['a', repositoryAddress],
            ],
          ),
        ];
      });

      final issues = await repository.fetchIssues(repositoryAddress);

      expect(issueFilters.single.tags['#a'], isNull);
      expect(issues.single.id, 'target-repository');
    },
  );

  test(
    'drains unfiltered comments and widens dense assignment boundaries',
    () async {
      const repositoryAddress =
          '${EventKind.repositoryAnnouncement}:$owner:app';
      const lateAssignee =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      final assignmentFilters = <NostrFilter>[];
      var noteCalls = 0;
      final repository = ProjectIssueRepository((filters) async {
        if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
          return [
            event(
              id: 'issue-root',
              kind: EventKind.issue,
              tags: [
                ['a', repositoryAddress],
              ],
            ),
          ];
        }
        if (filters.singleOrNull?.kinds.singleOrNull == EventKind.note) {
          noteCalls++;
          final filter = filters.single;
          if (noteCalls == 1) return const []; // Bounded visible comments.
          assignmentFilters.add(filter);
          if (filter.limit == 1000) {
            return [
              for (var index = 0; index < 500; index++)
                event(
                  id: 'plain-$index',
                  kind: EventKind.note,
                  createdAt: 1000,
                  tags: [
                    ['e', 'issue-root', '', 'root'],
                  ],
                ),
              event(
                id: 'late-assignment',
                kind: EventKind.note,
                createdAt: 1000,
                tags: [
                  ['e', 'issue-root', '', 'root'],
                  ['p', lateAssignee],
                  ['t', 'assignment'],
                ],
              ),
            ];
          }
          return [
            for (var index = 0; index < 500; index++)
              event(
                id: 'plain-$index',
                kind: EventKind.note,
                createdAt: 1000,
                tags: [
                  ['e', 'issue-root', '', 'root'],
                ],
              ),
          ];
        }
        return const [];
      });

      final issues = await repository.fetchIssues(repositoryAddress);

      expect(assignmentFilters, hasLength(3));
      expect(assignmentFilters.map((filter) => filter.limit), [500, 500, 1000]);
      expect(assignmentFilters.map((filter) => filter.until), [
        null,
        1000,
        1000,
      ]);
      expect(
        assignmentFilters.map((filter) => filter.tags['#t']),
        everyElement(isNull),
      );
      expect(issues.single.assignees, [lateAssignee]);
    },
  );

  test(
    'widens dense lifecycle timestamp boundaries without dropping state',
    () async {
      const repositoryAddress =
          '${EventKind.repositoryAnnouncement}:$owner:app';
      final statusFilters = <NostrFilter>[];
      final repository = ProjectIssueRepository((filters) async {
        if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
          return [
            event(
              id: 'issue-root',
              kind: EventKind.issue,
              tags: [
                ['a', repositoryAddress],
              ],
            ),
          ];
        }
        final statusFilter = filters
            .where((filter) => filter.kinds.contains(EventKind.issueDone))
            .firstOrNull;
        if (statusFilter != null) {
          statusFilters.add(statusFilter);
          if (statusFilter.limit == 1000) {
            return [
              for (var index = 0; index < 500; index++)
                event(
                  id: 'attacker-$index',
                  kind: EventKind.issueOpen,
                  pubkey:
                      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                  createdAt: 1000,
                  tags: [
                    ['e', 'issue-root', '', 'root'],
                    ['a', repositoryAddress],
                  ],
                ),
              event(
                id: 'owner-done',
                kind: EventKind.issueDone,
                createdAt: 1000,
                tags: [
                  ['e', 'issue-root', '', 'root'],
                  ['a', repositoryAddress],
                ],
              ),
            ];
          }
          return [
            for (var index = 0; index < 500; index++)
              event(
                id: 'attacker-$index',
                kind: EventKind.issueOpen,
                pubkey:
                    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                createdAt: 1000,
                tags: [
                  ['e', 'issue-root', '', 'root'],
                  ['a', repositoryAddress],
                ],
              ),
          ];
        }
        return const [];
      });

      final issues = await repository.fetchIssues(repositoryAddress);

      expect(statusFilters, hasLength(3));
      expect(statusFilters.map((filter) => filter.limit), [500, 500, 1000]);
      expect(statusFilters.map((filter) => filter.until), [null, 1000, 1000]);
      expect(issues.single.status.name, 'done');
    },
  );

  test(
    'fails closed when a lifecycle second exceeds the relay page clamp',
    () async {
      const repositoryAddress =
          '${EventKind.repositoryAnnouncement}:$owner:app';
      final repository = ProjectIssueRepository((filters) async {
        if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
          return [
            event(
              id: 'issue-root',
              kind: EventKind.issue,
              tags: const [
                ['a', repositoryAddress],
              ],
            ),
          ];
        }
        if (filters.singleOrNull?.kinds.contains(EventKind.issueDone) == true) {
          return [
            for (var index = 0; index < filters.single.limit; index++)
              event(
                id: 'dense-$index',
                kind: EventKind.issueOpen,
                createdAt: 1000,
                tags: const [
                  ['e', 'issue-root', '', 'root'],
                ],
              ),
          ];
        }
        return const [];
      });

      expect(
        repository.fetchIssues(repositoryAddress),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('issue lifecycle history'),
          ),
        ),
      );
    },
  );

  test('accepts lifecycle events from a condition-scoped NIP-OA agent', () async {
    final ownerKeys = nostr.Keys.generate();
    final agentKeys = nostr.Keys.generate();
    final repositoryAddress =
        '${EventKind.repositoryAnnouncement}:${ownerKeys.public}:app';
    final profileQueries = <NostrFilter>[];
    final repository = ProjectIssueRepository((filters) async {
      if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
        return [
          event(
            id: 'issue-root',
            kind: EventKind.issue,
            pubkey:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            tags: [
              ['a', repositoryAddress],
            ],
          ),
        ];
      }
      if (filters.any((filter) => filter.kinds.contains(EventKind.issueDone))) {
        return [
          event(
            id: 'agent-done',
            kind: EventKind.issueDone,
            pubkey: agentKeys.public,
            createdAt: 200,
            tags: [
              ['e', 'issue-root', '', 'root'],
              ['a', repositoryAddress],
            ],
          ),
        ];
      }
      if (filters.singleOrNull?.kinds.singleOrNull == 0) {
        profileQueries.add(filters.single);
        return [
          event(
            id: 'agent-profile',
            kind: 0,
            pubkey: agentKeys.public,
            tags: [
              authTag(
                ownerKeys,
                agentKeys.public,
                conditions: 'kind=${EventKind.issueDone}&created_at>199',
              ),
            ],
          ),
        ];
      }
      return const [];
    });

    final issues = await repository.fetchIssues(repositoryAddress);

    expect(issues.single.status.name, 'done');
    expect(profileQueries.single.authors, [agentKeys.public]);
  });

  test('resolves NIP-OA authority per status and linked issue', () async {
    final ownerKeys = nostr.Keys.generate();
    final agentKeys = nostr.Keys.generate();
    final repositoryAddress =
        '${EventKind.repositoryAnnouncement}:${ownerKeys.public}:app';
    final profileQueries = <NostrFilter>[];
    final repository = ProjectIssueRepository((filters) async {
      if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
        return [
          event(
            id: 'issue-by-agent',
            kind: EventKind.issue,
            pubkey: agentKeys.public,
            tags: [
              ['a', repositoryAddress],
            ],
          ),
          event(
            id: 'issue-by-member',
            kind: EventKind.issue,
            pubkey:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            tags: [
              ['a', repositoryAddress],
            ],
          ),
        ];
      }
      if (filters.any((filter) => filter.kinds.contains(EventKind.issueDone))) {
        return [
          event(
            id: 'agent-done-for-member-issue',
            kind: EventKind.issueDone,
            pubkey: agentKeys.public,
            createdAt: 200,
            tags: [
              ['e', 'issue-by-member', '', 'root'],
              ['a', repositoryAddress],
            ],
          ),
        ];
      }
      if (filters.singleOrNull?.kinds.singleOrNull == 0) {
        profileQueries.add(filters.single);
        return [
          event(
            id: 'agent-profile',
            kind: 0,
            pubkey: agentKeys.public,
            tags: [authTag(ownerKeys, agentKeys.public)],
          ),
        ];
      }
      return const [];
    });

    final issues = await repository.fetchIssues(repositoryAddress);
    final memberIssue = issues.singleWhere(
      (issue) => issue.id == 'issue-by-member',
    );

    expect(memberIssue.status.name, 'done');
    expect(profileQueries.single.authors, [agentKeys.public]);
  });

  test('sorts reduced issues by latest activity', () async {
    const repositoryAddress = '${EventKind.repositoryAnnouncement}:$owner:app';
    final repository = ProjectIssueRepository((filters) async {
      if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
        return [
          event(
            id: 'newer-root',
            kind: EventKind.issue,
            createdAt: 200,
            tags: const [
              ['a', repositoryAddress],
            ],
          ),
          event(
            id: 'older-active',
            kind: EventKind.issue,
            createdAt: 100,
            tags: const [
              ['a', repositoryAddress],
            ],
          ),
        ];
      }
      if (filters.singleOrNull?.kinds.singleOrNull == EventKind.note) {
        return [
          event(
            id: 'recent-comment',
            kind: EventKind.note,
            createdAt: 300,
            tags: const [
              ['e', 'older-active', '', 'root'],
            ],
          ),
        ];
      }
      return const [];
    });

    final issues = await repository.fetchIssues(repositoryAddress);

    expect(issues.map((issue) => issue.id), ['older-active', 'newer-root']);
  });

  test('fetches an exact issue root by event id', () async {
    const repositoryAddress = '${EventKind.repositoryAnnouncement}:$owner:app';
    final calls = <List<NostrFilter>>[];
    final repository = ProjectIssueRepository((filters) async {
      calls.add(filters);
      if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
        return [
          event(
            id: 'old-issue',
            kind: EventKind.issue,
            tags: [
              ['a', repositoryAddress],
              ['subject', 'Old exact issue'],
            ],
          ),
        ];
      }
      return const [];
    });

    final issue = await repository.fetchIssue(repositoryAddress, 'old-issue');

    expect(issue?.title, 'Old exact issue');
    expect(calls.first.single.ids, ['old-issue']);
    expect(calls.first.single.limit, 1);
  });

  group('status mutations', () {
    const repositoryAddress = '${EventKind.repositoryAnnouncement}:$owner:app';

    test(
      'publishes protocol-complete monotonic status and confirms read-back',
      () async {
        final submitter = _RecordingSubmitter(pubkey: owner);
        NostrEvent? published;
        submitter.onPublished = (event) => published = event;
        final repository = ProjectIssueRepository(
          (filters) async {
            if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
              return [
                event(
                  id: 'issue-root',
                  kind: EventKind.issue,
                  tags: const [
                    ['a', repositoryAddress],
                  ],
                ),
              ];
            }
            if (filters.any(
              (filter) => filter.kinds.contains(EventKind.issueDone),
            )) {
              return [if (published != null) published!];
            }
            return const [];
          },
          submit: submitter.call,
          nowSeconds: () => 200,
          readBackAttempts: 1,
          delay: (_) async {},
        );
        final issue = reduceProjectIssue(
          event(
            id: 'issue-root',
            kind: EventKind.issue,
            tags: const [
              ['a', repositoryAddress],
            ],
          ),
          statusEvents: [
            event(
              id: 'previous-status',
              kind: EventKind.issueOpen,
              createdAt: 300,
              tags: const [
                ['e', 'issue-root', '', 'root'],
                ['a', repositoryAddress],
              ],
            ),
          ],
        );

        final result = await repository.updateIssueStatus(
          issue: issue,
          viewer: owner,
          isVerifiedOaOwner: false,
          status: ProjectIssueLifecycleStatus.closed,
        );

        expect(result.confirmation, ProjectIssueWriteConfirmation.confirmed);
        expect(result.issue?.status, ProjectIssueStatus.closed);
        expect(submitter.kind, EventKind.issueClosed);
        expect(submitter.createdAt, 301);
        expect(submitter.content, isEmpty);
        expect(submitter.tags, [
          ['e', 'issue-root', '', 'root'],
          ['a', repositoryAddress],
          ['p', owner],
        ]);
      },
    );

    test(
      'returns published-pending-confirmation when relay state stays stale',
      () async {
        final submitter = _RecordingSubmitter(pubkey: owner);
        final repository = ProjectIssueRepository(
          (filters) async {
            if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
              return [
                event(
                  id: 'issue-root',
                  kind: EventKind.issue,
                  tags: const [
                    ['a', repositoryAddress],
                  ],
                ),
              ];
            }
            return const [];
          },
          submit: submitter.call,
          nowSeconds: () => 200,
          readBackAttempts: 2,
          delay: (_) async {},
        );
        final issue = reduceProjectIssue(
          event(
            id: 'issue-root',
            kind: EventKind.issue,
            tags: const [
              ['a', repositoryAddress],
            ],
          ),
        );

        final result = await repository.updateIssueStatus(
          issue: issue,
          viewer: owner,
          isVerifiedOaOwner: false,
          status: ProjectIssueLifecycleStatus.draft,
        );

        expect(
          result.confirmation,
          ProjectIssueWriteConfirmation.publishedPendingConfirmation,
        );
        expect(result.issue, isNull);
        expect(submitter.count, 1);
      },
    );

    test('rejects unauthorized status before signing', () async {
      final submitter = _RecordingSubmitter(pubkey: owner);
      final repository = ProjectIssueRepository(
        (_) async => const [],
        submit: submitter.call,
      );
      final issue = reduceProjectIssue(
        event(
          id: 'issue-root',
          kind: EventKind.issue,
          tags: const [
            ['a', repositoryAddress],
          ],
        ),
      );

      expect(
        repository.updateIssueStatus(
          issue: issue,
          viewer:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          isVerifiedOaOwner: false,
          status: ProjectIssueLifecycleStatus.open,
        ),
        throwsA(isA<StateError>()),
      );
      expect(submitter.count, 0);
    });

    test('rejects generic resolved while a current review exists', () async {
      final submitter = _RecordingSubmitter(pubkey: owner);
      final repository = ProjectIssueRepository(
        (_) async => const [],
        submit: submitter.call,
      );
      final issue = reduceProjectIssue(
        event(
          id: 'issue-root',
          kind: EventKind.issue,
          tags: const [
            ['a', repositoryAddress],
          ],
        ),
        reviewAuthority: const ProjectReviewAuthority(
          coordinatorPubkeys: [owner],
          humanPubkeys: [
            owner,
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ],
        ),
        commentEvents: [
          event(
            id: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            kind: EventKind.note,
            tags: const [
              ['e', 'issue-root', '', 'root'],
              ['a', repositoryAddress],
              ['t', 'review-ready'],
              ['review', 'review-42'],
              [
                'review-root',
                'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
              ],
              ['p', owner],
              [
                'p',
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              ],
            ],
            content: '''[REVIEW-READY]
Review-ID: review-42
Target: build-42
Evidence: focused tests are green
Test: Review it
Known limitations: none''',
          ),
        ],
      );

      expect(
        repository.updateIssueStatus(
          issue: issue,
          viewer: owner,
          isVerifiedOaOwner: false,
          status: ProjectIssueLifecycleStatus.resolved,
        ),
        throwsA(isA<StateError>()),
      );
      expect(submitter.count, 0);
    });
  });

  group('human verdict mutations', () {
    const repositoryAddress = '${EventKind.repositoryAnnouncement}:$owner:app';
    const reviewer =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const markerId =
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
    const reviewRootId =
        'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
    const issueId =
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

    test(
      'signs an exact accepted verdict and waits for workflow confirmation',
      () async {
        final submitter = _RecordingSubmitter(pubkey: owner);
        final repository = ProjectIssueRepository(
          (_) async => const [],
          submit: submitter.call,
          nowSeconds: () => 300,
          readBackAttempts: 1,
          delay: (_) async {},
        );
        final issue = ProjectIssue(
          id: issueId,
          title: 'Reviewable issue',
          content: '',
          author: owner,
          createdAt: 100,
          repositoryAddress: repositoryAddress,
          labels: const [],
          tags: const [
            ['a', repositoryAddress],
          ],
          updatedAt: 200,
          status: ProjectIssueStatus.inReview,
          statusEventId: markerId,
          statusCreatedAt: 200,
          assignees: const [],
          comments: const [],
          reviewAuthority: null,
          currentReview: const ProjectReviewMarker(
            markerEventId: markerId,
            markerCreatedAt: 200,
            reviewId: 'review-42',
            reviewRootId: reviewRootId,
            target: 'build-42',
            evidence: 'focused tests green',
            test: 'Open the issue',
            limitations: 'none',
            instructions: 'Open the issue',
            coordinatorPubkeys: [owner],
            authorizedHumanPubkeys: [owner, reviewer],
          ),
        );

        final result = await repository.submitHumanVerdict(
          issue: issue,
          viewer: owner,
          verdict: ProjectIssueHumanVerdictKind.accepted,
        );

        expect(
          result.confirmation,
          ProjectIssueWriteConfirmation.publishedPendingConfirmation,
        );
        expect(submitter.count, 1);
        expect(submitter.kind, EventKind.issueDone);
        expect(submitter.content, isEmpty);
        expect(submitter.createdAt, 300);
        expect(submitter.tags, [
          ['e', issueId, '', 'root'],
          ['a', repositoryAddress],
          ['p', owner],
          ['t', 'human-verdict'],
          ['verdict', 'accepted'],
          ['review', 'review-42'],
          ['review-root', reviewRootId],
        ]);
      },
    );
  });

  group('comment mutations', () {
    const repositoryAddress = '${EventKind.repositoryAnnouncement}:$owner:app';
    const commenter =
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

    test(
      'publishes protocol-complete comment and confirms read-back',
      () async {
        final submitter = _RecordingSubmitter(pubkey: commenter);
        NostrEvent? published;
        submitter.onPublished = (event) => published = event;
        final repository = ProjectIssueRepository(
          (filters) async {
            if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
              return [
                event(
                  id: 'issue-root',
                  kind: EventKind.issue,
                  tags: const [
                    ['a', repositoryAddress],
                    ['p', commenter],
                  ],
                ),
              ];
            }
            if (filters.singleOrNull?.kinds.singleOrNull == EventKind.note) {
              return [if (published != null) published!];
            }
            return const [];
          },
          submit: submitter.call,
          nowSeconds: () => 200,
          readBackAttempts: 1,
          delay: (_) async {},
        );
        final issue = reduceProjectIssue(
          event(
            id: 'issue-root',
            kind: EventKind.issue,
            tags: const [
              ['a', repositoryAddress],
              ['p', commenter],
            ],
          ),
        );

        final result = await repository.addIssueComment(
          issue: issue,
          author: commenter,
          content: ' Expected: desktop sees it ',
        );

        expect(result.confirmation, ProjectIssueWriteConfirmation.confirmed);
        expect(
          result.issue?.comments.single.content,
          'Expected: desktop sees it',
        );
        expect(submitter.kind, EventKind.note);
        expect(submitter.createdAt, 200);
        expect(submitter.tags, [
          ['e', 'issue-root', '', 'root'],
          ['a', repositoryAddress],
          ['p', owner],
          ['p', commenter],
          ['t', 'action-required'],
        ]);
      },
    );

    test('reports partial confirmation without publishing twice', () async {
      final submitter = _RecordingSubmitter(pubkey: commenter);
      final repository = ProjectIssueRepository(
        (filters) async {
          if (filters.singleOrNull?.kinds.singleOrNull == EventKind.issue) {
            return [
              event(
                id: 'issue-root',
                kind: EventKind.issue,
                tags: const [
                  ['a', repositoryAddress],
                ],
              ),
            ];
          }
          return const [];
        },
        submit: submitter.call,
        readBackAttempts: 2,
        delay: (_) async {},
      );
      final issue = reduceProjectIssue(
        event(
          id: 'issue-root',
          kind: EventKind.issue,
          tags: const [
            ['a', repositoryAddress],
          ],
        ),
      );

      final result = await repository.addIssueComment(
        issue: issue,
        author: commenter,
        content: 'Comment',
      );

      expect(
        result.confirmation,
        ProjectIssueWriteConfirmation.publishedPendingConfirmation,
      );
      expect(result.issue, isNull);
      expect(submitter.count, 1);
    });
  });
}

class _RecordingSubmitter {
  final String pubkey;
  void Function(NostrEvent event)? onPublished;
  int count = 0;
  int? kind;
  String? content;
  List<List<String>>? tags;
  int? createdAt;

  _RecordingSubmitter({required this.pubkey});

  Future<NostrEvent> call({
    required int kind,
    required String content,
    required List<List<String>> tags,
    int? createdAt,
    void Function(NostrEvent event)? onSigned,
  }) async {
    count++;
    this.kind = kind;
    this.content = content;
    this.tags = tags;
    this.createdAt = createdAt;
    final signed = event(
      id: 'signed-$count',
      kind: kind,
      pubkey: pubkey,
      createdAt: createdAt ?? 0,
      tags: tags,
      content: content,
    );
    onSigned?.call(signed);
    onPublished?.call(signed);
    return event(id: 'relay-ok-$count', kind: kind, tags: const []);
  }
}
