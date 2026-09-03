import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/relay/relay.dart';
import 'project_issue_reducer.dart';
import 'project_issue_repository.dart';
import 'project_models.dart';

final projectIssueRepositoryProvider = Provider<ProjectIssueRepository>((ref) {
  final session = ref.read(relaySessionProvider.notifier);
  return ProjectIssueRepository(session.queryRelay);
});

final projectsProvider = FutureProvider.autoDispose<List<MobileProject>>((ref) {
  return ref.read(projectIssueRepositoryProvider).fetchProjects();
});

typedef RepositoryIssuesKey = ({
  String repositoryAddress,
  ProjectReviewAuthority? reviewAuthority,
});

final repositoryIssuesProvider = FutureProvider.autoDispose
    .family<List<ProjectIssue>, RepositoryIssuesKey>((ref, key) {
      return ref.read(projectIssueRepositoryProvider).fetchIssues(
        key.repositoryAddress,
        reviewAuthority: key.reviewAuthority,
      );
    });

typedef LinkedIssueKey = ({
  String repositoryAddress,
  String eventId,
  ProjectReviewAuthority? reviewAuthority,
});

final linkedIssueProvider = FutureProvider.autoDispose
    .family<ProjectIssue?, LinkedIssueKey>((ref, key) {
      return ref.read(projectIssueRepositoryProvider).fetchIssue(
        key.repositoryAddress,
        key.eventId,
        reviewAuthority: key.reviewAuthority,
      );
    });
