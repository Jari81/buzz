import 'package:buzz/features/projects/project_issue_reducer.dart';
import 'package:buzz/features/projects/project_models.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const author =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const coordinator =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const jari = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const ania = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const reviewRoot =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const reviewAuthority = ProjectReviewAuthority(
  coordinatorPubkeys: [coordinator],
  humanPubkeys: [jari, ania],
);
const repositoryAddress = '${EventKind.repositoryAnnouncement}:$owner:demo';

NostrEvent issue({
  String id = 'issue',
  String content = 'First body line\nDetails',
  List<List<String>> extraTags = const [],
}) => NostrEvent(
  id: id,
  pubkey: author,
  createdAt: 100,
  kind: EventKind.issue,
  tags: [
    ['a', repositoryAddress],
    ...extraTags,
  ],
  content: content,
  sig: '',
);

NostrEvent status({
  required String id,
  required String pubkey,
  required int kind,
  required int createdAt,
  String content = '',
  List<List<String>> extraTags = const [],
}) => NostrEvent(
  id: id,
  pubkey: pubkey,
  createdAt: createdAt,
  kind: kind,
  tags: [
    ['e', 'issue', '', 'root'],
    ['a', repositoryAddress],
    ...extraTags,
  ],
  content: content,
  sig: '',
);

NostrEvent assignment({
  required String id,
  required String signer,
  required String assignee,
  String label = 'assignment',
  int createdAt = 150,
  String? prior,
}) => NostrEvent(
  id: id,
  pubkey: signer,
  createdAt: createdAt,
  kind: EventKind.note,
  tags: [
    ['e', 'issue', '', 'root'],
    ['a', repositoryAddress],
    ['p', assignee],
    ['t', label],
    if (prior != null) ['prior', prior],
  ],
  content: 'Assigned this issue',
  sig: '',
);

NostrEvent comment({
  required String id,
  required int createdAt,
  String content = 'Comment',
  List<List<String>> extraTags = const [],
}) => NostrEvent(
  id: id,
  pubkey: author,
  createdAt: createdAt,
  kind: EventKind.note,
  tags: [
    ['e', 'issue', '', 'root'],
    ['a', repositoryAddress],
    ...extraTags,
  ],
  content: content,
  sig: '',
);

NostrEvent reviewReady({String signer = coordinator}) => NostrEvent(
  id: '1111111111111111111111111111111111111111111111111111111111111111',
  pubkey: signer,
  createdAt: 250,
  kind: EventKind.note,
  tags: const [
    ['e', 'issue', '', 'root'],
    ['a', repositoryAddress],
    ['t', 'review-ready'],
    ['review', 'review-42'],
    ['review-root', reviewRoot],
    ['p', jari],
    ['p', ania],
  ],
  content: '''[REVIEW-READY]
Review-ID: review-42
Target: commit-abc
Evidence: Focused tests green
Test: Test the current APK.
Known limitations: none''',
  sig: '',
);

NostrEvent humanVerdict({
  String verdict = 'accepted',
  String signer = jari,
  int createdAt = 260,
}) {
  final rejected = verdict == 'rejected';
  return NostrEvent(
    id: '2222222222222222222222222222222222222222222222222222222222222222',
    pubkey: signer,
    createdAt: createdAt,
    kind: rejected ? EventKind.issueOpen : EventKind.issueDone,
    tags: [
      ['e', 'issue', '', 'root'],
      ['a', repositoryAddress],
      ['p', owner],
      ['p', author],
      ['t', 'human-verdict'],
      ['verdict', verdict],
      ['review', 'review-42'],
      ['review-root', reviewRoot],
    ],
    content: rejected ? 'Button overlaps the dialog' : '',
    sig: '',
  );
}

NostrEvent verdictConfirmation({
  String verdict = 'accepted',
  String signer = coordinator,
  int createdAt = 270,
}) {
  final rejected = verdict == 'rejected';
  final verdictEvent = humanVerdict(verdict: verdict);
  final kanbanStatus = rejected ? 'ready' : 'done';
  return NostrEvent(
    id: '3333333333333333333333333333333333333333333333333333333333333333',
    pubkey: signer,
    createdAt: createdAt,
    kind: EventKind.note,
    tags: [
      ['e', 'issue', '', 'root'],
      ['a', repositoryAddress],
      ['p', verdictEvent.pubkey],
      ['t', 'issue-verdict-confirmed'],
      ['review', 'review-42'],
      ['review-root', reviewRoot],
      ['verdict', verdict],
      ['verdict-event', verdictEvent.id],
      ['kanban-status', kanbanStatus],
    ],
    content:
        '''[ISSUE-VERDICT-CONFIRMED]
Issue: issue
Repository: $repositoryAddress
Board: buzz-workflow
Task: t_example
Review: review-42
Review-Root: $reviewRoot
Verdict-Event: ${verdictEvent.id}
Actor: ${verdictEvent.pubkey}
Verdict: $verdict
Kanban-Status: $kanbanStatus${rejected ? '\nReason: ${verdictEvent.content}' : ''}''',
    sig: '',
  );
}

void main() {
  test('uses subject then body first line then Untitled issue for title', () {
    expect(
      reduceProjectIssue(
        issue(
          extraTags: const [
            ['subject', 'Tagged title'],
          ],
        ),
      ).title,
      'Tagged title',
    );
    expect(reduceProjectIssue(issue()).title, 'First body line');
    expect(reduceProjectIssue(issue(content: '')).title, 'Untitled issue');
  });

  test('accepts lifecycle status only from a trusted actor', () {
    final reduced = reduceProjectIssue(
      issue(),
      statusEvents: [
        status(
          id: 'author-done',
          pubkey: author,
          kind: EventKind.issueDone,
          createdAt: 200,
        ),
        status(
          id: 'attacker-closed',
          pubkey:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          kind: EventKind.issueClosed,
          createdAt: 300,
        ),
      ],
    );

    expect(reduced.status, ProjectIssueStatus.done);
    expect(reduced.statusEventId, 'author-done');
  });

  test('grants lifecycle authority to a current assignee', () {
    const assignee =
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
    final reduced = reduceProjectIssue(
      issue(),
      commentEvents: [
        assignment(id: 'assignment', signer: owner, assignee: assignee),
      ],
      statusEvents: [
        status(
          id: 'assignee-done',
          pubkey: assignee,
          kind: EventKind.issueDone,
          createdAt: 200,
        ),
      ],
    );

    expect(reduced.assignees, [assignee]);
    expect(reduced.status, ProjectIssueStatus.done);
    expect(reduced.statusEventId, 'assignee-done');
  });

  test('ignores generic resolved at or after the current review attempt', () {
    for (final createdAt in [250, 300]) {
      final reduced = reduceProjectIssue(
        issue(),
        commentEvents: [reviewReady()],
        reviewAuthority: reviewAuthority,
        statusEvents: [
          status(
            id: 'generic-done-$createdAt',
            pubkey: owner,
            kind: EventKind.issueDone,
            createdAt: createdAt,
          ),
        ],
      );

      expect(reduced.currentReview?.reviewId, 'review-42');
      expect(reduced.status, ProjectIssueStatus.inReview);
      expect(
        reduced.statusEventId,
        '1111111111111111111111111111111111111111111111111111111111111111',
      );
    }
  });

  test('rejects review-ready metadata from an assignee', () {
    const assignee = jari;
    final reduced = reduceProjectIssue(
      issue(),
      commentEvents: [
        assignment(id: 'assignment', signer: owner, assignee: assignee),
        reviewReady(signer: assignee),
      ],
      reviewAuthority: reviewAuthority,
    );

    expect(reduced.currentReview, isNull);
    expect(reduced.status, ProjectIssueStatus.backlog);
  });

  test('accepts only the explicitly verified NIP-OA status event', () {
    final reduced = reduceProjectIssue(
      issue(),
      additionalTrustedStatusEventIds: const {'oa-agent-done'},
      statusEvents: [
        status(
          id: 'oa-agent-done',
          pubkey:
              'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
          kind: EventKind.issueDone,
          createdAt: 200,
        ),
      ],
    );

    expect(reduced.status, ProjectIssueStatus.done);
  });

  test('breaks equal status timestamps deterministically by event id', () {
    final reduced = reduceProjectIssue(
      issue(),
      statusEvents: [
        status(
          id: 'z-done',
          pubkey: author,
          kind: EventKind.issueDone,
          createdAt: 200,
        ),
        status(
          id: 'a-open',
          pubkey: author,
          kind: EventKind.issueOpen,
          createdAt: 200,
        ),
      ],
    );

    expect(reduced.statusEventId, 'a-open');
    expect(reduced.status, ProjectIssueStatus.backlog);
  });

  test('derives fallback lifecycle state from root labels', () {
    final inReview = reduceProjectIssue(
      issue(
        extraTags: const [
          ['t', 'in-review'],
        ],
      ),
      statusEvents: [
        status(
          id: 'open',
          pubkey: owner,
          kind: EventKind.issueOpen,
          createdAt: 200,
          content: 'Free-form content must not define lifecycle state.',
        ),
      ],
    );
    final inProgress = reduceProjectIssue(
      issue(
        extraTags: const [
          ['t', 'active'],
        ],
      ),
    );

    expect(inReview.status, ProjectIssueStatus.inReview);
    expect(inProgress.status, ProjectIssueStatus.inProgress);
  });

  test('sorts ordinary comments by timestamp then event id', () {
    final reduced = reduceProjectIssue(
      issue(),
      commentEvents: [
        comment(id: 'later', createdAt: 300),
        comment(id: 'z-same-second', createdAt: 200),
        comment(id: 'a-same-second', createdAt: 200),
      ],
    );

    expect(reduced.comments.map((entry) => entry.id), [
      'a-same-second',
      'z-same-second',
      'later',
    ]);
  });

  test(
    'reduces complete assignment and unassignment history deterministically',
    () {
      const assignee =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final reduced = reduceProjectIssue(
        issue(),
        commentEvents: [
          assignment(
            id: 'z-unassign',
            signer: owner,
            assignee: assignee,
            label: 'unassignment',
            createdAt: 200,
          ),
          assignment(
            id: 'a-assign',
            signer: owner,
            assignee: assignee,
            createdAt: 200,
          ),
        ],
      );

      expect(reduced.assignees, isEmpty);
    },
  );

  test('allows a member to self-assign but not assign somebody else', () {
    const volunteer =
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
    const target =
        '1111111111111111111111111111111111111111111111111111111111111111';
    final reduced = reduceProjectIssue(
      issue(),
      commentEvents: [
        assignment(id: 'self', signer: volunteer, assignee: volunteer),
        assignment(id: 'other', signer: volunteer, assignee: target),
      ],
    );

    expect(reduced.assignees, [volunteer]);
  });

  test('owner decision outranks a later uncaused self-assignment', () {
    const volunteer =
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
    final reduced = reduceProjectIssue(
      issue(),
      commentEvents: [
        assignment(
          id: 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
          signer: volunteer,
          assignee: volunteer,
          createdAt: 999,
        ),
        assignment(
          id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          signer: owner,
          assignee: volunteer,
          label: 'unassignment',
          createdAt: 200,
        ),
      ],
    );

    expect(reduced.assignees, isEmpty);
  });

  test('causal self-assignment may supersede the current owner decision', () {
    const volunteer =
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
    const ownerDecision =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final reduced = reduceProjectIssue(
      issue(),
      commentEvents: [
        assignment(
          id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          signer: volunteer,
          assignee: volunteer,
          createdAt: 100,
        ),
        assignment(
          id: ownerDecision,
          signer: owner,
          assignee: volunteer,
          label: 'unassignment',
          createdAt: 200,
        ),
        assignment(
          id: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          signer: volunteer,
          assignee: volunteer,
          createdAt: 300,
          prior: ownerDecision,
        ),
      ],
    );

    expect(reduced.assignees, [volunteer]);
  });

  test('reduces trusted review metadata separately from ordinary comments', () {
    final reduced = reduceProjectIssue(
      issue(),
      commentEvents: [
        reviewReady(),
        comment(id: 'ordinary', createdAt: 260),
      ],
      reviewAuthority: reviewAuthority,
    );

    expect(reduced.currentReview?.reviewId, 'review-42');
    expect(reduced.currentReview?.reviewRootId, reviewRoot);
    expect(reduced.currentReview?.target, 'commit-abc');
    expect(reduced.currentReview?.evidence, 'Focused tests green');
    expect(reduced.currentReview?.test, 'Test the current APK.');
    expect(reduced.currentReview?.limitations, 'none');
    expect(reduced.currentReview?.authorizedHumanPubkeys, [jari, ania]);
    expect(reduced.currentReview?.instructions, 'Test the current APK.');
    expect(reduced.comments.map((entry) => entry.id), ['ordinary']);
  });

  test('reduces only confirmed current-review human verdicts', () {
    for (final verdict in ['accepted', 'rejected']) {
      final reduced = reduceProjectIssue(
        issue(),
        statusEvents: [humanVerdict(verdict: verdict)],
        commentEvents: [
          reviewReady(),
          verdictConfirmation(verdict: verdict),
        ],
        reviewAuthority: reviewAuthority,
      );

      expect(reduced.currentReview?.verdict?.kind, verdict);
      expect(reduced.currentReview?.verdict?.actorPubkey, jari);
      expect(
        reduced.currentReview?.verdict?.reason,
        verdict == 'rejected' ? 'Button overlaps the dialog' : isNull,
      );
      expect(
        reduced.currentReview?.verdict?.confirmation?.kanbanStatus,
        verdict == 'accepted' ? 'done' : 'ready',
      );
      expect(
        reduced.status,
        verdict == 'accepted'
            ? ProjectIssueStatus.done
            : ProjectIssueStatus.backlog,
      );
    }
  });

  test('preserves read-only issue and comment detail fields', () {
    final reduced = reduceProjectIssue(
      issue(
        content: 'Body text',
        extraTags: const [
          ['t', 'bug'],
        ],
      ),
      commentEvents: [
        comment(id: 'comment', createdAt: 220, content: 'Reply text'),
      ],
    );

    expect(reduced.id, 'issue');
    expect(reduced.content, 'Body text');
    expect(reduced.author, author);
    expect(reduced.createdAt, 100);
    expect(reduced.repositoryAddress, repositoryAddress);
    expect(reduced.labels, ['bug']);
    expect(reduced.updatedAt, 220);
    expect(reduced.comments.single.content, 'Reply text');
    expect(reduced.comments.single.author, author);
    expect(reduced.comments.single.createdAt, 220);
  });

  test('preserves event tags for rich read-only rendering', () {
    final reduced = reduceProjectIssue(
      issue(
        extraTags: const [
          ['imeta', 'url https://example.test/issue.png'],
        ],
      ),
      commentEvents: [
        comment(
          id: 'comment',
          createdAt: 220,
          extraTags: const [
            ['imeta', 'url https://example.test/comment.png'],
          ],
        ),
      ],
    );

    expect(reduced.tags.last.first, 'imeta');
    expect(reduced.comments.single.tags.last.first, 'imeta');
  });
}
