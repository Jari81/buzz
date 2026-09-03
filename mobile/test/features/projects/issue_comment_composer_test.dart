import 'dart:async';

import 'package:buzz/features/projects/issue_comment_composer.dart';
import 'package:buzz/features/projects/project_issue_reducer.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const author =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const commenter =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const address = '${EventKind.repositoryAnnouncement}:$owner:app';

void main() {
  group('comment event contract', () {
    test('rejects empty or whitespace-only comments', () {
      for (final content in ['', '  \n ']) {
        expect(
          () => buildProjectIssueCommentDraft(
            issue: _issue(),
            repositoryOwner: owner,
            author: commenter,
            content: content,
            nowSeconds: 200,
          ),
          throwsArgumentError,
        );
      }
    });

    test(
      'builds root, repository, deduplicated recipient, and action tags',
      () {
        final draft = buildProjectIssueCommentDraft(
          issue: _issue(),
          repositoryOwner: owner,
          author: commenter,
          content: '  Test: install the APK  ',
          nowSeconds: 200,
        );

        expect(draft.content, 'Test: install the APK');
        expect(draft.createdAt, 200);
        expect(draft.tags, [
          ['e', 'issue', '', 'root'],
          ['a', address],
          ['p', owner],
          ['p', author],
          ['p', commenter],
          ['t', 'action-required'],
        ]);
      },
    );

    test('does not add the current commenter as an implicit recipient', () {
      final draft = buildProjectIssueCommentDraft(
        issue: _issue(withRootRecipient: false),
        repositoryOwner: owner,
        author: commenter,
        content: 'Ordinary comment',
        nowSeconds: 200,
      );
      expect(draft.tags.where((tag) => tag.first == 'p').toList(), [
        ['p', owner],
        ['p', author],
      ]);
    });

    test(
      'recognizes Test, Expected, and Reply prefixes case-insensitively',
      () {
        for (final content in [
          'Test: one',
          ' expected : two',
          '\nREPLY: three',
        ]) {
          final draft = buildProjectIssueCommentDraft(
            issue: _issue(),
            repositoryOwner: owner,
            author: commenter,
            content: content,
            nowSeconds: 200,
          );
          expect(draft.tags.last, ['t', 'action-required'], reason: content);
        }
        final ordinary = buildProjectIssueCommentDraft(
          issue: _issue(),
          repositoryOwner: owner,
          author: commenter,
          content: 'Technical evidence only',
          nowSeconds: 200,
        );
        expect(ordinary.tags.any((tag) => tag.first == 't'), isFalse);
      },
    );

    test('advances beyond the same author latest comment timestamp', () {
      final draft = buildProjectIssueCommentDraft(
        issue: _issue(withPriorComment: true),
        repositoryOwner: owner,
        author: commenter.toUpperCase(),
        content: 'Next',
        nowSeconds: 200,
      );
      expect(draft.createdAt, 301);
    });
  });

  testWidgets(
    'composer rejects blank, disables while sending, and clears on success',
    (tester) async {
      final pending = Completer<void>();
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IssueCommentComposer(
              onSubmit: (content) {
                submitted = content;
                return pending.future;
              },
            ),
          ),
        ),
      );

      final sendButton = find.widgetWithText(FilledButton, 'Send');
      expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  Reply: looks good  ');
      await tester.pump();
      expect(tester.widget<FilledButton>(sendButton).onPressed, isNotNull);
      await tester.tap(sendButton);
      await tester.pump();
      expect(submitted, 'Reply: looks good');
      expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Reply: looks good'), findsNothing);
      expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);
    },
  );
}

ProjectIssue _issue({
  bool withPriorComment = false,
  bool withRootRecipient = true,
}) => reduceProjectIssue(
  NostrEvent(
    id: 'issue',
    pubkey: author,
    createdAt: 100,
    kind: EventKind.issue,
    tags: [
      ['a', address],
      if (withRootRecipient) ['p', commenter],
    ],
    content: 'Body',
    sig: '',
  ),
  commentEvents: withPriorComment
      ? const [
          NostrEvent(
            id: 'prior',
            pubkey: commenter,
            createdAt: 300,
            kind: EventKind.note,
            tags: [
              ['e', 'issue', '', 'root'],
            ],
            content: 'Prior',
            sig: '',
          ),
        ]
      : const [],
);
