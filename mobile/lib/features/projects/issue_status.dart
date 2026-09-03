import '../../shared/relay/relay.dart';

enum ProjectIssueLifecycleStatus { draft, open, resolved, closed }

enum ProjectIssueHumanVerdictKind { accepted, rejected }

List<ProjectIssueLifecycleStatus> availableProjectIssueLifecycleStatuses({
  required bool hasCurrentReview,
}) => List.unmodifiable(
  ProjectIssueLifecycleStatus.values.where(
    (status) =>
        !hasCurrentReview || status != ProjectIssueLifecycleStatus.resolved,
  ),
);

int projectIssueLifecycleEventKind(ProjectIssueLifecycleStatus status) =>
    switch (status) {
      ProjectIssueLifecycleStatus.draft => EventKind.issueDraft,
      ProjectIssueLifecycleStatus.open => EventKind.issueOpen,
      ProjectIssueLifecycleStatus.resolved => EventKind.issueDone,
      ProjectIssueLifecycleStatus.closed => EventKind.issueClosed,
    };

bool canChangeProjectIssueStatus({
  required String? viewer,
  required String issueAuthor,
  required String repositoryOwner,
  required Iterable<String> issueAssignees,
  required bool isVerifiedOaOwner,
}) {
  final actor = _normalizedPubkey(viewer);
  if (actor == null) return false;
  if (isVerifiedOaOwner) return true;
  return actor == _normalizedPubkey(issueAuthor) ||
      actor == _normalizedPubkey(repositoryOwner) ||
      issueAssignees.any((assignee) => actor == _normalizedPubkey(assignee));
}

bool canSubmitProjectIssueHumanVerdict({
  required String? viewer,
  required String? currentReviewId,
  required String? markerReviewId,
  required bool markerTrusted,
  required Iterable<String> authorizedHumanPubkeys,
}) {
  final actor = _normalizedPubkey(viewer);
  final current = currentReviewId?.trim();
  final marker = markerReviewId?.trim();
  if (actor == null ||
      !markerTrusted ||
      current == null ||
      current.isEmpty ||
      marker == null ||
      marker.isEmpty ||
      current != marker) {
    return false;
  }
  return authorizedHumanPubkeys.any(
    (pubkey) => actor == _normalizedPubkey(pubkey),
  );
}

String? _normalizedPubkey(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
