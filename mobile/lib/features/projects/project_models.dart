import 'package:flutter/foundation.dart';

import '../../shared/relay/relay.dart';

@immutable
class ProjectReviewAuthority {
  final List<String> coordinatorPubkeys;
  final List<String> humanPubkeys;

  const ProjectReviewAuthority({
    required this.coordinatorPubkeys,
    required this.humanPubkeys,
  });

  @override
  bool operator ==(Object other) =>
      other is ProjectReviewAuthority &&
      listEquals(other.coordinatorPubkeys, coordinatorPubkeys) &&
      listEquals(other.humanPubkeys, humanPubkeys);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(coordinatorPubkeys),
    Object.hashAll(humanPubkeys),
  );
}

@immutable
class RepositoryCoordinate {
  final String owner;
  final String dtag;

  const RepositoryCoordinate({required this.owner, required this.dtag});

  String get value => '${EventKind.repositoryAnnouncement}:$owner:$dtag';
}

@immutable
class ProjectRepository {
  final RepositoryCoordinate coordinate;
  final String name;
  final String description;
  final String? channelId;
  final int? createdAt;
  final bool isAvailable;
  final ProjectReviewAuthority? reviewAuthority;

  const ProjectRepository({
    required this.coordinate,
    required this.name,
    required this.description,
    required this.channelId,
    required this.createdAt,
    required this.isAvailable,
    this.reviewAuthority,
  });
}

@immutable
class MobileProject {
  final String address;
  final String dtag;
  final String owner;
  final String name;
  final String description;
  final int createdAt;
  final List<ProjectRepository> repositories;
  final ProjectReviewAuthority? reviewAuthority;

  const MobileProject({
    required this.address,
    required this.dtag,
    required this.owner,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.repositories,
    this.reviewAuthority,
  });
}

RepositoryCoordinate? parseRepositoryCoordinate(String value) {
  final firstSeparator = value.indexOf(':');
  final secondSeparator = value.indexOf(':', firstSeparator + 1);
  if (firstSeparator < 0 ||
      secondSeparator < 0 ||
      value.substring(0, firstSeparator) !=
          EventKind.repositoryAnnouncement.toString()) {
    return null;
  }

  final owner = value.substring(firstSeparator + 1, secondSeparator);
  final dtag = value.substring(secondSeparator + 1);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(owner) || dtag.isEmpty) return null;
  return RepositoryCoordinate(owner: owner, dtag: dtag);
}

ProjectReviewAuthority? parseProjectReviewAuthority(List<List<String>> tags) {
  final coordinatorTags = tags
      .where((tag) => tag.isNotEmpty && tag.first == 'review-coordinator')
      .toList();
  final humanTags = tags
      .where((tag) => tag.isNotEmpty && tag.first == 'review-human')
      .toList();
  if (coordinatorTags.isEmpty || humanTags.length != 2) return null;
  final authorityTags = [...coordinatorTags, ...humanTags];
  if (authorityTags.any(
    (tag) => tag.length != 2 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(tag[1]),
  )) {
    return null;
  }
  final coordinators = coordinatorTags.map((tag) => tag[1]).toList();
  final humans = humanTags.map((tag) => tag[1]).toList();
  if (coordinators.toSet().length != coordinators.length ||
      humans.toSet().length != humans.length) {
    return null;
  }
  return ProjectReviewAuthority(
    coordinatorPubkeys: List.unmodifiable(coordinators),
    humanPubkeys: List.unmodifiable(humans),
  );
}

List<MobileProject> buildProjectModels({
  required Iterable<NostrEvent> projectEvents,
  required Iterable<NostrEvent> repositoryEvents,
}) {
  final repositories = <String, NostrEvent>{};
  for (final event in repositoryEvents) {
    if (event.kind != EventKind.repositoryAnnouncement) continue;
    final dtag = _tag(event, 'd');
    if (dtag == null) continue;
    final coordinate =
        '${EventKind.repositoryAnnouncement}:${event.pubkey.toLowerCase()}:$dtag';
    final current = repositories[coordinate];
    if (current == null || _isNewer(event, current)) {
      repositories[coordinate] = event;
    }
  }

  final projects = <String, NostrEvent>{};
  for (final event in projectEvents) {
    if (!isListedProjectEvent(event)) continue;
    final dtag = _tag(event, 'd');
    if (dtag == null) continue;
    final address =
        '${EventKind.projectAnnouncement}:${event.pubkey.toLowerCase()}:$dtag';
    final current = projects[address];
    if (current == null || _isNewer(event, current)) projects[address] = event;
  }

  return [
    for (final entry in projects.entries)
      _projectFromEvent(entry.key, entry.value, repositories),
  ]..sort((left, right) {
    final byTime = right.createdAt.compareTo(left.createdAt);
    return byTime != 0 ? byTime : left.address.compareTo(right.address);
  });
}

bool isListedProjectEvent(NostrEvent event) =>
    event.kind == EventKind.projectAnnouncement &&
    _tag(event, 'buzz-visibility')?.trim().toLowerCase() != 'unlisted';

MobileProject _projectFromEvent(
  String address,
  NostrEvent event,
  Map<String, NostrEvent> repositories,
) {
  final dtag = _tag(event, 'd')!;
  final reviewAuthority = parseProjectReviewAuthority(event.tags);
  final members = <ProjectRepository>[];
  for (final tag in event.tags) {
    if (tag.length < 2 || tag.first != 'a') continue;
    final coordinate = parseRepositoryCoordinate(tag[1]);
    if (coordinate == null) continue;
    final repository = repositories[coordinate.value];
    members.add(
      ProjectRepository(
        coordinate: coordinate,
        name: repository == null
            ? 'Repository unavailable'
            : _tag(repository, 'name') ?? coordinate.dtag,
        description: repository == null
            ? ''
            : _tag(repository, 'description') ?? repository.content,
        channelId: repository == null
            ? null
            : _tag(repository, 'h') ?? _tag(repository, 'buzz-channel'),
        createdAt: repository?.createdAt,
        isAvailable: repository != null,
        reviewAuthority: reviewAuthority,
      ),
    );
  }
  return MobileProject(
    address: address,
    dtag: dtag,
    owner: event.pubkey.toLowerCase(),
    name: _tag(event, 'name') ?? dtag,
    description: _tag(event, 'description') ?? event.content,
    createdAt: event.createdAt,
    repositories: List.unmodifiable(members),
    reviewAuthority: reviewAuthority,
  );
}

String? _tag(NostrEvent event, String name) {
  final value = event.getTagValue(name);
  return value == null || value.isEmpty ? null : value;
}

bool _isNewer(NostrEvent candidate, NostrEvent current) =>
    candidate.createdAt > current.createdAt ||
    (candidate.createdAt == current.createdAt &&
        candidate.id.compareTo(current.id) < 0);
