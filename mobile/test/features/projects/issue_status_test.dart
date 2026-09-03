import 'package:flutter_test/flutter_test.dart';
import 'package:buzz/features/projects/issue_status.dart';

void main() {
  const issueAuthor =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const repositoryOwner =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const assignee =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  const oaOwner =
      'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
  const outsider =
      'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

  group('ordinary lifecycle authority', () {
    test('allows the issue author, repository owner, and assignee', () {
      for (final viewer in [issueAuthor, repositoryOwner, assignee]) {
        expect(
          canChangeProjectIssueStatus(
            viewer: viewer,
            issueAuthor: issueAuthor,
            repositoryOwner: repositoryOwner,
            issueAssignees: const [assignee],
            isVerifiedOaOwner: false,
          ),
          isTrue,
          reason: viewer,
        );
      }
    });

    test('allows a verified NIP-OA owner', () {
      expect(
        canChangeProjectIssueStatus(
          viewer: oaOwner,
          issueAuthor: issueAuthor,
          repositoryOwner: repositoryOwner,
          issueAssignees: const [assignee],
          isVerifiedOaOwner: true,
        ),
        isTrue,
      );
    });

    test('rejects an outsider and an unauthenticated viewer', () {
      for (final viewer in <String?>[outsider, null, '']) {
        expect(
          canChangeProjectIssueStatus(
            viewer: viewer,
            issueAuthor: issueAuthor,
            repositoryOwner: repositoryOwner,
            issueAssignees: const [assignee],
            isVerifiedOaOwner: false,
          ),
          isFalse,
        );
      }
    });
  });

  group('lifecycle picker', () {
    test('offers every ordinary state when there is no current review', () {
      expect(
        availableProjectIssueLifecycleStatuses(hasCurrentReview: false),
        ProjectIssueLifecycleStatus.values,
      );
    });

    test('removes resolved while a current review exists', () {
      expect(
        availableProjectIssueLifecycleStatuses(hasCurrentReview: true),
        const [
          ProjectIssueLifecycleStatus.draft,
          ProjectIssueLifecycleStatus.open,
          ProjectIssueLifecycleStatus.closed,
        ],
      );
    });

    test('maps ordinary states to their NIP-34 event kinds', () {
      expect(
        projectIssueLifecycleEventKind(ProjectIssueLifecycleStatus.draft),
        1633,
      );
      expect(
        projectIssueLifecycleEventKind(ProjectIssueLifecycleStatus.open),
        1630,
      );
      expect(
        projectIssueLifecycleEventKind(ProjectIssueLifecycleStatus.resolved),
        1631,
      );
      expect(
        projectIssueLifecycleEventKind(ProjectIssueLifecycleStatus.closed),
        1632,
      );
    });
  });

  group('human product authority', () {
    const reviewId = 'review-42';

    test('allows only a technically addressed project owner or tester', () {
      for (final viewer in [repositoryOwner, assignee]) {
        expect(
          canSubmitProjectIssueHumanVerdict(
            viewer: viewer,
            currentReviewId: reviewId,
            markerReviewId: reviewId,
            markerTrusted: true,
            authorizedHumanPubkeys: const [repositoryOwner, assignee],
          ),
          isTrue,
        );
      }
      expect(
        canSubmitProjectIssueHumanVerdict(
          viewer: issueAuthor,
          currentReviewId: reviewId,
          markerReviewId: reviewId,
          markerTrusted: true,
          authorizedHumanPubkeys: const [repositoryOwner, assignee],
        ),
        isFalse,
      );
    });

    test('fails closed for unauthenticated or outsider viewers', () {
      for (final viewer in <String?>[null, '', outsider]) {
        expect(
          canSubmitProjectIssueHumanVerdict(
            viewer: viewer,
            currentReviewId: reviewId,
            markerReviewId: reviewId,
            markerTrusted: true,
            authorizedHumanPubkeys: const [repositoryOwner, assignee],
          ),
          isFalse,
        );
      }
    });

    test(
      'fails closed for stale, mismatched, missing, or untrusted markers',
      () {
        final cases = [
          (
            currentReviewId: 'new-review',
            markerReviewId: 'old-review',
            markerTrusted: true,
          ),
          (
            currentReviewId: reviewId,
            markerReviewId: 'other-review',
            markerTrusted: true,
          ),
          (currentReviewId: '', markerReviewId: reviewId, markerTrusted: true),
          (
            currentReviewId: reviewId,
            markerReviewId: reviewId,
            markerTrusted: false,
          ),
        ];
        for (final entry in cases) {
          expect(
            canSubmitProjectIssueHumanVerdict(
              viewer: repositoryOwner,
              currentReviewId: entry.currentReviewId,
              markerReviewId: entry.markerReviewId,
              markerTrusted: entry.markerTrusted,
              authorizedHumanPubkeys: const [repositoryOwner, assignee],
            ),
            isFalse,
          );
        }
      },
    );
  });
}
