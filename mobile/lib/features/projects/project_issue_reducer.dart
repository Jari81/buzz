import 'package:flutter/foundation.dart';

import '../../shared/relay/relay.dart';
import 'project_models.dart';

enum ProjectIssueStatus {
  triage,
  backlog,
  inProgress,
  approved,
  inReview,
  done,
  closed,
}

@immutable
class ProjectIssueComment {
  final String id;
  final String content;
  final String author;
  final int createdAt;
  final List<List<String>> tags;

  const ProjectIssueComment({
    required this.id,
    required this.content,
    required this.author,
    required this.createdAt,
    required this.tags,
  });
}

@immutable
class ProjectIssueVerdictConfirmation {
  final String eventId;
  final int createdAt;
  final String kanbanStatus;

  const ProjectIssueVerdictConfirmation({
    required this.eventId,
    required this.createdAt,
    required this.kanbanStatus,
  });
}

@immutable
class ProjectIssueHumanVerdict {
  final String eventId;
  final String kind;
  final String actorPubkey;
  final int createdAt;
  final String? reason;
  final ProjectIssueVerdictConfirmation? confirmation;

  const ProjectIssueHumanVerdict({
    required this.eventId,
    required this.kind,
    required this.actorPubkey,
    required this.createdAt,
    required this.reason,
    this.confirmation,
  });

  ProjectIssueHumanVerdict withConfirmation(
    ProjectIssueVerdictConfirmation value,
  ) => ProjectIssueHumanVerdict(
    eventId: eventId,
    kind: kind,
    actorPubkey: actorPubkey,
    createdAt: createdAt,
    reason: reason,
    confirmation: value,
  );
}

@immutable
class ProjectReviewMarker {
  final String markerEventId;
  final int markerCreatedAt;
  final String reviewId;
  final String reviewRootId;
  final String? target;
  final String evidence;
  final String test;
  final String limitations;
  final String instructions;
  final List<String> coordinatorPubkeys;
  final List<String> authorizedHumanPubkeys;
  final ProjectIssueHumanVerdict? verdict;

  const ProjectReviewMarker({
    required this.markerEventId,
    required this.markerCreatedAt,
    required this.reviewId,
    required this.reviewRootId,
    required this.target,
    required this.evidence,
    required this.test,
    required this.limitations,
    required this.instructions,
    required this.coordinatorPubkeys,
    required this.authorizedHumanPubkeys,
    this.verdict,
  });

  ProjectReviewMarker withVerdict(ProjectIssueHumanVerdict value) =>
      ProjectReviewMarker(
        markerEventId: markerEventId,
        markerCreatedAt: markerCreatedAt,
        reviewId: reviewId,
        reviewRootId: reviewRootId,
        target: target,
        evidence: evidence,
        test: test,
        limitations: limitations,
        instructions: instructions,
        coordinatorPubkeys: coordinatorPubkeys,
        authorizedHumanPubkeys: authorizedHumanPubkeys,
        verdict: value,
      );
}

@immutable
class ProjectIssue {
  final String id;
  final String title;
  final String content;
  final String author;
  final int createdAt;
  final String? repositoryAddress;
  final List<String> labels;
  final List<List<String>> tags;
  final int updatedAt;
  final ProjectIssueStatus status;
  final String? statusEventId;
  final int? statusCreatedAt;
  final List<String> assignees;
  final List<ProjectIssueComment> comments;
  final ProjectReviewMarker? currentReview;
  final ProjectReviewAuthority? reviewAuthority;

  const ProjectIssue({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    required this.createdAt,
    required this.repositoryAddress,
    required this.labels,
    required this.tags,
    required this.updatedAt,
    required this.status,
    required this.statusEventId,
    this.statusCreatedAt,
    required this.assignees,
    required this.comments,
    required this.currentReview,
    this.reviewAuthority,
  });
}

ProjectIssue reduceProjectIssue(
  NostrEvent issue, {
  Iterable<NostrEvent> statusEvents = const [],
  Iterable<NostrEvent> commentEvents = const [],
  Iterable<String> additionalTrustedStatusEventIds = const [],
  ProjectReviewAuthority? reviewAuthority,
}) {
  final subject = issue.getTagValue('subject');
  final firstLine = issue.content.split('\n').first;
  final statusEventList = statusEvents.toList();
  final commentEventList = commentEvents.toList();
  final statusActors = <String>{issue.pubkey.toLowerCase()};
  final repositoryOwner = _repositoryOwner(issue.getTagValue('a'));
  if (repositoryOwner != null) statusActors.add(repositoryOwner);
  final assignees = <String>{};
  final uncausedSelfOperations = <_AssignmentOperation>[];
  final authoritativeOperations = <_AssignmentOperation>[];
  final causalSelfOperations = <_AssignmentOperation>[];
  final assignmentEvents =
      commentEventList
          .where(
            (event) =>
                event.kind == EventKind.note &&
                event.tags.any(
                  (tag) =>
                      tag.length >= 2 && tag.first == 'e' && tag[1] == issue.id,
                ),
          )
          .toList()
        ..sort((left, right) {
          final byTime = left.createdAt.compareTo(right.createdAt);
          return byTime != 0 ? byTime : left.id.compareTo(right.id);
        });
  for (final event in assignmentEvents) {
    final labels = event.tags
        .where((tag) => tag.length >= 2 && tag.first == 't')
        .map((tag) => tag[1])
        .toSet();
    final assigning = labels.contains('assignment');
    if (!(assigning ^ labels.contains('unassignment'))) continue;
    final signer = event.pubkey.toLowerCase();
    final pubkeys = event.tags
        .where((tag) => tag.length >= 2 && tag.first == 'p')
        .map((tag) => tag[1].toLowerCase())
        .toList();
    final isSelfOperation = pubkeys.length == 1 && pubkeys.single == signer;
    final authoritative = statusActors.contains(signer);
    if (!authoritative && !isSelfOperation) continue;
    final operation = _AssignmentOperation(
      eventId: event.id.toLowerCase(),
      assigning: assigning,
      pubkeys: pubkeys,
    );
    if (authoritative) {
      authoritativeOperations.add(operation);
      continue;
    }
    final priorTags = event.tags.where(
      (tag) => tag.isNotEmpty && tag.first == 'prior',
    );
    if (priorTags.isEmpty) {
      uncausedSelfOperations.add(operation);
      continue;
    }
    if (priorTags.length != 1 ||
        priorTags.single.length < 2 ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(priorTags.single[1])) {
      continue;
    }
    causalSelfOperations.add(
      operation.withPrior(priorTags.single[1].toLowerCase()),
    );
  }
  final operationHeads = <String, String>{};
  for (final operation in [
    ...uncausedSelfOperations,
    ...authoritativeOperations,
    ...causalSelfOperations,
  ]) {
    if (operation.prior != null &&
        operationHeads[operation.pubkeys.single] != operation.prior) {
      continue;
    }
    operation.assigning
        ? assignees.addAll(operation.pubkeys)
        : assignees.removeAll(operation.pubkeys);
    for (final pubkey in operation.pubkeys) {
      operationHeads[pubkey] = operation.eventId;
    }
  }
  statusActors.addAll(assignees);
  final trustedStatusEventIds = additionalTrustedStatusEventIds
      .map((eventId) => eventId.toLowerCase())
      .toSet();
  final reviewMarker = _currentReviewForIssue(
    issue,
    commentEventList,
    reviewAuthority,
  );
  final rawVerdict = _humanVerdictForCurrentReview(
    issue,
    statusEventList,
    reviewMarker,
  );
  final confirmation = _confirmationForCurrentVerdict(
    issue,
    commentEventList,
    reviewMarker,
    rawVerdict,
  );
  final currentReview = reviewMarker == null
      ? null
      : rawVerdict == null
      ? reviewMarker
      : reviewMarker.withVerdict(
          confirmation == null
              ? rawVerdict
              : rawVerdict.withConfirmation(confirmation),
        );
  final comments =
      commentEventList
          .where(
            (event) =>
                event.kind == EventKind.note &&
                !event.tags.any(
                  (tag) =>
                      tag.length >= 2 &&
                      tag.first == 't' &&
                      {
                        'review-ready',
                        'issue-verdict-confirmed',
                        'assignment',
                        'unassignment',
                      }.contains(tag[1]),
                ) &&
                event.tags.any(
                  (tag) =>
                      tag.length >= 2 && tag.first == 'e' && tag[1] == issue.id,
                ),
          )
          .toList()
        ..sort((left, right) {
          final byTime = left.createdAt.compareTo(right.createdAt);
          return byTime != 0 ? byTime : left.id.compareTo(right.id);
        });
  final trustedStatuses =
      statusEventList.where((event) {
        final genericResolvedDuringReview =
            currentReview != null &&
            event.kind == EventKind.issueDone &&
            event.createdAt >= currentReview.markerCreatedAt;
        return !genericResolvedDuringReview &&
            (statusActors.contains(event.pubkey.toLowerCase()) ||
                trustedStatusEventIds.contains(event.id.toLowerCase())) &&
            event.tags.any(
              (tag) =>
                  tag.length >= 2 && tag.first == 'e' && tag[1] == issue.id,
            );
      }).toList()..sort((left, right) {
        final byTime = right.createdAt.compareTo(left.createdAt);
        return byTime != 0 ? byTime : left.id.compareTo(right.id);
      });
  final latestStatus = trustedStatuses.firstOrNull;
  final confirmedVerdict = currentReview?.verdict?.confirmation != null
      ? currentReview!.verdict!.kind
      : null;
  final latestLifecycleAfterMarker =
      latestStatus != null &&
          currentReview != null &&
          latestStatus.createdAt > currentReview.markerCreatedAt
      ? latestStatus
      : null;
  final resolvedStatus = confirmedVerdict == 'accepted'
      ? ProjectIssueStatus.done
      : confirmedVerdict == 'rejected'
      ? ProjectIssueStatus.backlog
      : currentReview != null
      ? latestLifecycleAfterMarker == null
            ? ProjectIssueStatus.inReview
            : _statusFromEvent(issue, latestLifecycleAfterMarker)
      : _statusFromEvent(issue, latestStatus);
  final effectiveEventId =
      currentReview?.verdict?.confirmation?.eventId ??
      currentReview?.verdict?.eventId ??
      (currentReview != null
          ? latestStatus?.id ?? currentReview.markerEventId
          : latestStatus?.id);
  final effectiveCreatedAt =
      currentReview?.verdict?.confirmation?.createdAt ??
      currentReview?.verdict?.createdAt ??
      (currentReview != null
          ? latestStatus?.createdAt ?? currentReview.markerCreatedAt
          : latestStatus?.createdAt);
  final updatedAt = [
    issue.createdAt,
    ?effectiveCreatedAt,
    for (final comment in comments) comment.createdAt,
  ].reduce((left, right) => left > right ? left : right);
  return ProjectIssue(
    id: issue.id,
    title: subject?.isNotEmpty == true
        ? subject!
        : firstLine.isNotEmpty
        ? firstLine
        : 'Untitled issue',
    content: issue.content,
    author: issue.pubkey,
    createdAt: issue.createdAt,
    repositoryAddress: issue.getTagValue('a'),
    labels: [
      for (final tag in issue.tags)
        if (tag.length >= 2 && tag.first == 't' && tag[1].isNotEmpty) tag[1],
    ],
    tags: List.unmodifiable(issue.tags),
    updatedAt: updatedAt,
    status: resolvedStatus,
    statusEventId: effectiveEventId,
    statusCreatedAt: effectiveCreatedAt,
    assignees: List.unmodifiable(assignees),
    comments: [
      for (final comment in comments)
        ProjectIssueComment(
          id: comment.id,
          content: comment.content,
          author: comment.pubkey,
          createdAt: comment.createdAt,
          tags: List.unmodifiable(comment.tags),
        ),
    ],
    currentReview: currentReview,
    reviewAuthority: reviewAuthority,
  );
}

ProjectReviewMarker? _currentReviewForIssue(
  NostrEvent issue,
  Iterable<NostrEvent> commentEvents,
  ProjectReviewAuthority? authority,
) {
  final repositoryAddress = issue.getTagValue('a');
  if (authority == null ||
      repositoryAddress == null ||
      parseRepositoryCoordinate(repositoryAddress) == null ||
      authority.coordinatorPubkeys.isEmpty ||
      authority.humanPubkeys.length != 2) {
    return null;
  }
  final coordinators = authority.coordinatorPubkeys.toSet();
  final humans = authority.humanPubkeys.toSet();
  final candidates =
      commentEvents
          .where(
            (event) =>
                event.kind == EventKind.note &&
                coordinators.contains(event.pubkey.toLowerCase()) &&
                event.tags.any(
                  (tag) =>
                      tag.length >= 2 &&
                      tag.first == 't' &&
                      tag[1] == 'review-ready',
                ),
          )
          .toList()
        ..sort((left, right) {
          final byTime = right.createdAt.compareTo(left.createdAt);
          return byTime != 0 ? byTime : left.id.compareTo(right.id);
        });
  final marker = candidates.firstOrNull;
  if (marker == null ||
      !_isHex64(marker.id) ||
      marker.createdAt < issue.createdAt ||
      !_exactlyOneTag(marker, 'e', [issue.id, '', 'root']) ||
      !_exactlyOneTag(marker, 'a', [repositoryAddress]) ||
      !_exactlyOneTag(marker, 't', const ['review-ready']) ||
      !_hasExactRecipientSet(marker, humans)) {
    return null;
  }
  final reviewId = _singleTagValue(marker, 'review');
  final reviewRootId = _singleTagValue(marker, 'review-root');
  final fields = _exactContentFields(marker.content, '[REVIEW-READY]', const [
    'Review-ID',
    'Target',
    'Evidence',
    'Test',
    'Known limitations',
  ]);
  if (reviewId == null ||
      reviewRootId == null ||
      !_isHex64(reviewRootId) ||
      fields == null ||
      fields['Review-ID'] != reviewId ||
      candidates
          .skip(1)
          .any(
            (candidate) => _singleTagValue(candidate, 'review') == reviewId,
          )) {
    return null;
  }
  return ProjectReviewMarker(
    markerEventId: marker.id,
    markerCreatedAt: marker.createdAt,
    reviewId: reviewId,
    reviewRootId: reviewRootId,
    target: fields['Target'],
    evidence: fields['Evidence']!,
    test: fields['Test']!,
    limitations: fields['Known limitations']!,
    instructions: fields['Test']!,
    coordinatorPubkeys: List.unmodifiable(authority.coordinatorPubkeys),
    authorizedHumanPubkeys: List.unmodifiable(authority.humanPubkeys),
  );
}

ProjectIssueHumanVerdict? _humanVerdictForCurrentReview(
  NostrEvent issue,
  Iterable<NostrEvent> statusEvents,
  ProjectReviewMarker? review,
) {
  final repositoryAddress = issue.getTagValue('a');
  final repositoryOwner = _repositoryOwner(repositoryAddress);
  if (review == null || repositoryAddress == null || repositoryOwner == null) {
    return null;
  }
  final humans = review.authorizedHumanPubkeys.toSet();
  final expectedRecipients = <String>{
    repositoryOwner,
    issue.pubkey.toLowerCase(),
  };
  final candidates =
      statusEvents.where((event) {
        final verdict = _singleTagValue(event, 'verdict');
        if (!_isHex64(event.id) ||
            !humans.contains(event.pubkey.toLowerCase()) ||
            event.createdAt < review.markerCreatedAt ||
            !_exactlyOneTag(event, 'e', [issue.id, '', 'root']) ||
            !_exactlyOneTag(event, 'a', [repositoryAddress]) ||
            !_exactlyOneTag(event, 't', const ['human-verdict']) ||
            !_exactlyOneTag(event, 'review', [review.reviewId]) ||
            !_exactlyOneTag(event, 'review-root', [review.reviewRootId]) ||
            !_hasExactRecipientSet(event, expectedRecipients)) {
          return false;
        }
        if (event.kind == EventKind.issueDone && verdict == 'accepted') {
          return event.content.isEmpty;
        }
        return event.kind == EventKind.issueOpen &&
            verdict == 'rejected' &&
            event.content.isNotEmpty &&
            event.content.length <= 500 &&
            event.content.trim() == event.content &&
            !_hasControlCharacters(event.content);
      }).toList()..sort((left, right) {
        final byTime = left.createdAt.compareTo(right.createdAt);
        return byTime != 0 ? byTime : left.id.compareTo(right.id);
      });
  final event = candidates.firstOrNull;
  if (event == null) return null;
  final kind = _singleTagValue(event, 'verdict')!;
  return ProjectIssueHumanVerdict(
    eventId: event.id,
    kind: kind,
    actorPubkey: event.pubkey.toLowerCase(),
    createdAt: event.createdAt,
    reason: kind == 'rejected' ? event.content : null,
  );
}

ProjectIssueVerdictConfirmation? _confirmationForCurrentVerdict(
  NostrEvent issue,
  Iterable<NostrEvent> commentEvents,
  ProjectReviewMarker? review,
  ProjectIssueHumanVerdict? verdict,
) {
  final repositoryAddress = issue.getTagValue('a');
  if (review == null || verdict == null || repositoryAddress == null) {
    return null;
  }
  final candidates = commentEvents
      .where(
        (event) =>
            event.kind == EventKind.note &&
            review.coordinatorPubkeys.contains(event.pubkey.toLowerCase()) &&
            event.createdAt >= review.markerCreatedAt &&
            event.tags.any(
              (tag) =>
                  tag.length >= 2 &&
                  tag.first == 't' &&
                  tag[1] == 'issue-verdict-confirmed',
            ),
      )
      .toList();
  if (candidates.length != 1) return null;
  final event = candidates.single;
  final kanbanStatus = _singleTagValue(event, 'kanban-status');
  final allowedStatuses = verdict.kind == 'accepted'
      ? const {'done'}
      : const {'ready', 'todo'};
  if (!_isHex64(event.id) ||
      event.createdAt < verdict.createdAt ||
      !_exactlyOneTag(event, 'e', [issue.id, '', 'root']) ||
      !_exactlyOneTag(event, 'a', [repositoryAddress]) ||
      !_exactlyOneTag(event, 't', const ['issue-verdict-confirmed']) ||
      !_exactlyOneTag(event, 'review', [review.reviewId]) ||
      !_exactlyOneTag(event, 'review-root', [review.reviewRootId]) ||
      !_exactlyOneTag(event, 'verdict', [verdict.kind]) ||
      !_exactlyOneTag(event, 'verdict-event', [verdict.eventId]) ||
      !_hasExactRecipientSet(event, {verdict.actorPubkey}) ||
      kanbanStatus == null ||
      !allowedStatuses.contains(kanbanStatus)) {
    return null;
  }
  final expectedNames = [
    'Issue',
    'Repository',
    'Board',
    'Task',
    'Review',
    'Review-Root',
    'Verdict-Event',
    'Actor',
    'Verdict',
    'Kanban-Status',
    if (verdict.kind == 'rejected') 'Reason',
  ];
  final fields = _exactContentFields(
    event.content,
    '[ISSUE-VERDICT-CONFIRMED]',
    expectedNames,
  );
  if (fields == null ||
      fields['Issue'] != issue.id ||
      fields['Repository'] != repositoryAddress ||
      fields['Review'] != review.reviewId ||
      fields['Review-Root'] != review.reviewRootId ||
      fields['Verdict-Event'] != verdict.eventId ||
      fields['Actor'] != verdict.actorPubkey ||
      fields['Verdict'] != verdict.kind ||
      fields['Kanban-Status'] != kanbanStatus ||
      (fields['Board']?.isEmpty ?? true) ||
      (fields['Task']?.isEmpty ?? true) ||
      (verdict.kind == 'rejected' && fields['Reason'] != verdict.reason)) {
    return null;
  }
  return ProjectIssueVerdictConfirmation(
    eventId: event.id,
    createdAt: event.createdAt,
    kanbanStatus: kanbanStatus,
  );
}

bool _hasControlCharacters(String value) =>
    value.codeUnits.any((code) => code <= 31 || code == 127);

bool _isHex64(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _exactlyOneTag(NostrEvent event, String name, List<String> values) {
  final matches = event.tags.where(
    (tag) => tag.isNotEmpty && tag.first == name,
  );
  return matches.length == 1 && listEquals(matches.single, [name, ...values]);
}

String? _singleTagValue(NostrEvent event, String name) {
  final matches = event.tags.where(
    (tag) => tag.isNotEmpty && tag.first == name,
  );
  return matches.length == 1 &&
          matches.single.length == 2 &&
          matches.single[1].isNotEmpty
      ? matches.single[1]
      : null;
}

bool _hasExactRecipientSet(NostrEvent event, Set<String> expected) {
  final tags = event.tags
      .where((tag) => tag.isNotEmpty && tag.first == 'p')
      .toList();
  if (tags.length != expected.length ||
      tags.any((tag) => tag.length != 2 || !_isHex64(tag[1]))) {
    return false;
  }
  final recipients = tags.map((tag) => tag[1]).toList();
  return recipients.toSet().length == recipients.length &&
      recipients.every(expected.contains);
}

Map<String, String>? _exactContentFields(
  String content,
  String header,
  List<String> expectedNames,
) {
  final lines = content.split('\n');
  if (lines.length != expectedNames.length + 1 || lines.first != header) {
    return null;
  }
  final fields = <String, String>{};
  for (final line in lines.skip(1)) {
    final separator = line.indexOf(': ');
    if (separator <= 0) return null;
    final name = line.substring(0, separator);
    final value = line.substring(separator + 2);
    if (!expectedNames.contains(name) ||
        value.isEmpty ||
        fields.containsKey(name)) {
      return null;
    }
    fields[name] = value;
  }
  return fields.length == expectedNames.length ? fields : null;
}

class _AssignmentOperation {
  final String eventId;
  final bool assigning;
  final List<String> pubkeys;
  final String? prior;

  const _AssignmentOperation({
    required this.eventId,
    required this.assigning,
    required this.pubkeys,
    this.prior,
  });

  _AssignmentOperation withPrior(String value) => _AssignmentOperation(
    eventId: eventId,
    assigning: assigning,
    pubkeys: pubkeys,
    prior: value,
  );
}

String? _repositoryOwner(String? address) {
  if (address == null) return null;
  final firstSeparator = address.indexOf(':');
  final secondSeparator = address.indexOf(':', firstSeparator + 1);
  if (firstSeparator < 0 || secondSeparator < 0) return null;
  final owner = address
      .substring(firstSeparator + 1, secondSeparator)
      .toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(owner) ? owner : null;
}

ProjectIssueStatus _statusFromEvent(NostrEvent issue, NostrEvent? event) {
  if (event?.kind == EventKind.issueDone) return ProjectIssueStatus.done;
  if (event?.kind == EventKind.issueClosed) return ProjectIssueStatus.closed;
  if (event?.kind == EventKind.issueDraft) return ProjectIssueStatus.triage;
  final labels = issue.tags
      .where((tag) => tag.length >= 2 && tag.first == 't')
      .map((tag) => tag[1].toLowerCase())
      .toSet();
  if (labels.contains('in-review') || labels.contains('review')) {
    return ProjectIssueStatus.inReview;
  }
  if (labels.contains('in-progress') || labels.contains('active')) {
    return ProjectIssueStatus.inProgress;
  }
  if (labels.contains('triage')) return ProjectIssueStatus.triage;
  return ProjectIssueStatus.backlog;
}
