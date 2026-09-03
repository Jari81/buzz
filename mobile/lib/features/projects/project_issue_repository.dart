import '../../shared/crypto/nip_oa.dart';
import '../../shared/relay/relay.dart';
import 'project_issue_reducer.dart';
import 'project_models.dart';

typedef ProjectEventFetcher =
    Future<List<NostrEvent>> Function(List<NostrFilter> filters);
const _eventPageSize = 500;
const _relayMaxPageSize = 1000;
const _issueIdChunkSize = 100;

class ProjectIssueRepository {
  final ProjectEventFetcher _fetch;

  ProjectIssueRepository(this._fetch);

  Future<List<MobileProject>> fetchProjects() async {
    final projectEvents = await _fetchExhaustively(
      kinds: const [EventKind.projectAnnouncement],
      errorContext: 'project announcements',
    );
    final listedProjectEvents = projectEvents
        .where(isListedProjectEvent)
        .toList();
    final memberDtagsByOwner = <String, Set<String>>{};
    for (final project in listedProjectEvents) {
      for (final tag in project.tags) {
        if (tag.length < 2 || tag.first != 'a') continue;
        final coordinate = parseRepositoryCoordinate(tag[1]);
        if (coordinate == null) continue;
        memberDtagsByOwner
            .putIfAbsent(coordinate.owner, () => <String>{})
            .add(coordinate.dtag);
      }
    }

    final filters = [
      for (final entry in memberDtagsByOwner.entries)
        for (final dtagChunk in _chunks(entry.value.toList()..sort()))
          NostrFilter(
            kinds: const [EventKind.repositoryAnnouncement],
            authors: [entry.key],
            tags: {'#d': dtagChunk},
            limit: 500,
          ),
    ];
    final repositoryEvents = filters.isEmpty
        ? const <NostrEvent>[]
        : await _fetch(filters);
    return buildProjectModels(
      projectEvents: listedProjectEvents,
      repositoryEvents: repositoryEvents,
    );
  }

  Future<List<ProjectIssue>> fetchIssues(
    String repositoryAddress, {
    ProjectReviewAuthority? reviewAuthority,
  }) async {
    final allIssueEvents = await _fetchExhaustively(
      kinds: const [EventKind.issue],
      errorContext: 'issue roots',
    );
    final issueEvents = allIssueEvents
        .where(
          (event) =>
              event.kind == EventKind.issue &&
              event.getTagValue('a') == repositoryAddress,
        )
        .toList();
    return _fetchIssueModels(
      repositoryAddress,
      issueEvents,
      reviewAuthority: reviewAuthority,
    );
  }

  Future<ProjectIssue?> fetchIssue(
    String repositoryAddress,
    String eventId, {
    ProjectReviewAuthority? reviewAuthority,
  }) async {
    final issueEvents = await _fetch([
      NostrFilter(
        kinds: const [EventKind.issue],
        ids: [eventId],
        tags: {
          '#a': [repositoryAddress],
        },
        limit: 1,
      ),
    ]);
    final exactIssue = issueEvents
        .where(
          (event) =>
              event.id == eventId &&
              event.kind == EventKind.issue &&
              event.getTagValue('a') == repositoryAddress,
        )
        .firstOrNull;
    if (exactIssue == null) return null;
    final issues = await _fetchIssueModels(repositoryAddress, [
      exactIssue,
    ], reviewAuthority: reviewAuthority);
    return issues.firstOrNull;
  }

  Future<List<ProjectIssue>> _fetchIssueModels(
    String repositoryAddress,
    List<NostrEvent> issueEvents, {
    ProjectReviewAuthority? reviewAuthority,
  }) async {
    if (issueEvents.isEmpty) return const [];
    final issueIds = [for (final issue in issueEvents) issue.id];
    final statusEvents = await _fetchStatusEvents(issueIds);
    final commentEvents = await _fetchBoundedComments(issueIds);
    final statusAuthors = <String>{};
    for (final status in statusEvents) {
      final author = status.pubkey.toLowerCase();
      for (final issue in issueEvents) {
        final linked = status.tags.any(
          (tag) => tag.length >= 2 && tag.first == 'e' && tag[1] == issue.id,
        );
        final repositoryOwner = _repositoryOwner(issue.getTagValue('a'));
        if (linked &&
            author != issue.pubkey.toLowerCase() &&
            author != repositoryOwner) {
          statusAuthors.add(author);
        }
      }
    }
    final profileEvents = statusAuthors.isEmpty
        ? const <NostrEvent>[]
        : await _fetch([
            NostrFilter(
              kinds: const [0],
              authors: statusAuthors.toList(),
              limit: statusAuthors.length,
            ),
          ]);
    final profilesByAuthor = <String, NostrEvent>{};
    for (final profile in profileEvents.where((event) => event.kind == 0)) {
      final author = profile.pubkey.toLowerCase();
      final current = profilesByAuthor[author];
      if (current == null || profile.createdAt > current.createdAt) {
        profilesByAuthor[author] = profile;
      }
    }
    final assignmentEvents = await _fetchAssignmentEvents(issueIds);
    final commentsById = <String, NostrEvent>{
      for (final event in commentEvents.where(
        (event) => event.kind == EventKind.note,
      ))
        event.id: event,
      for (final event in assignmentEvents) event.id: event,
    };
    final issues = [
      for (final issue in issueEvents)
        reduceProjectIssue(
          issue,
          statusEvents: statusEvents,
          commentEvents: commentsById.values,
          additionalTrustedStatusEventIds: _trustedOaStatusEventIds(
            issue,
            statusEvents,
            profilesByAuthor,
          ),
          reviewAuthority: reviewAuthority,
        ),
    ];
    issues.sort((left, right) {
      final byActivity = right.updatedAt.compareTo(left.updatedAt);
      return byActivity != 0 ? byActivity : left.id.compareTo(right.id);
    });
    return issues;
  }

  Iterable<String> _trustedOaStatusEventIds(
    NostrEvent issue,
    List<NostrEvent> statusEvents,
    Map<String, NostrEvent> profilesByAuthor,
  ) sync* {
    final repositoryOwner = _repositoryOwner(issue.getTagValue('a'));
    if (repositoryOwner == null) return;
    for (final status in statusEvents) {
      if (!status.tags.any(
        (tag) => tag.length >= 2 && tag.first == 'e' && tag[1] == issue.id,
      )) {
        continue;
      }
      final profile = profilesByAuthor[status.pubkey.toLowerCase()];
      if (profile == null) continue;
      final owner = verifiedOaOwnerPubkeyForEvent(
        profile.tags,
        status.pubkey,
        kind: status.kind,
        createdAt: status.createdAt,
      );
      if (owner == repositoryOwner) yield status.id;
    }
  }

  Future<List<NostrEvent>> _fetchStatusEvents(List<String> issueIds) async {
    final eventsById = <String, NostrEvent>{};
    for (final chunk in _chunks(issueIds)) {
      final events = await _fetchExhaustively(
        kinds: const [
          EventKind.issueOpen,
          EventKind.issueDone,
          EventKind.issueClosed,
          EventKind.issueDraft,
        ],
        tags: {'#e': chunk},
        errorContext: 'issue lifecycle history',
      );
      for (final event in events) {
        eventsById[event.id] = event;
      }
    }
    return eventsById.values.toList();
  }

  Future<List<NostrEvent>> _fetchBoundedComments(List<String> issueIds) async {
    final eventsById = <String, NostrEvent>{};
    for (final chunk in _chunks(issueIds)) {
      final events = await _fetch([
        NostrFilter(
          kinds: const [EventKind.note],
          tags: {'#e': chunk},
          limit: _eventPageSize,
        ),
      ]);
      for (final event in events.where(
        (event) => event.kind == EventKind.note,
      )) {
        eventsById[event.id] = event;
      }
    }
    return eventsById.values.toList();
  }

  Future<List<NostrEvent>> _fetchAssignmentEvents(List<String> issueIds) async {
    final eventsById = <String, NostrEvent>{};
    for (final chunk in _chunks(issueIds)) {
      final events = await _fetchExhaustively(
        kinds: const [EventKind.note],
        tags: {'#e': chunk},
        errorContext: 'issue assignment history',
      );
      for (final event in events) {
        final labels = event.tags
            .where((tag) => tag.length >= 2 && tag.first == 't')
            .map((tag) => tag[1]);
        if (labels.contains('assignment') || labels.contains('unassignment')) {
          eventsById[event.id] = event;
        }
      }
    }
    return eventsById.values.toList();
  }

  Future<List<NostrEvent>> _fetchExhaustively({
    required List<int> kinds,
    required String errorContext,
    List<String>? authors,
    Map<String, List<String>> tags = const {},
  }) async {
    final eventsById = <String, NostrEvent>{};
    var limit = _eventPageSize;
    int? until;
    for (;;) {
      final page = await _fetch([
        NostrFilter(
          kinds: kinds,
          authors: authors,
          tags: tags,
          limit: limit,
          until: until,
        ),
      ]);
      for (final event in page.where((event) => kinds.contains(event.kind))) {
        eventsById[event.id] = event;
      }
      if (page.length < limit) break;
      final oldest = page
          .map((event) => event.createdAt)
          .reduce((left, right) => left < right ? left : right);
      if (until == null || oldest < until) {
        until = oldest;
        continue;
      }
      if (oldest == until && limit < _relayMaxPageSize) {
        limit = _relayMaxPageSize;
        continue;
      }
      throw StateError(
        'Could not exhaustively load $errorContext: more than a full relay '
        'page shares one timestamp.',
      );
    }
    return eventsById.values.toList();
  }

  Iterable<List<String>> _chunks(List<String> values) sync* {
    for (var index = 0; index < values.length; index += _issueIdChunkSize) {
      final end = (index + _issueIdChunkSize).clamp(0, values.length);
      yield values.sublist(index, end);
    }
  }
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
