import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/theme/theme.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import 'project_issue_providers.dart';
import 'project_issue_reducer.dart';
import 'project_models.dart';

class RepositoryIssuesPage extends ConsumerWidget {
  final ProjectRepository repository;
  final ValueChanged<ProjectIssue>? onIssueTap;

  const RepositoryIssuesPage({
    required this.repository,
    this.onIssueTap,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(
      repositoryIssuesProvider((
        repositoryAddress: repository.coordinate.value,
        reviewAuthority: repository.reviewAuthority,
      )),
    );
    return FrostedScaffold(
      appBar: FrostedAppBar(title: Text('${repository.name} issues')),
      body: issues.when(
        data: (value) => _IssueList(issues: value, onIssueTap: onIssueTap),
        error: (_, _) => const Center(child: Text('Could not load issues')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _IssueList extends StatelessWidget {
  final List<ProjectIssue> issues;
  final ValueChanged<ProjectIssue>? onIssueTap;

  const _IssueList({required this.issues, required this.onIssueTap});

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const Center(child: Text('No issues'));
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        Grid.gutter,
        frostedAppBarHeight(context) + Grid.xxs,
        Grid.gutter,
        Grid.xxl,
      ),
      itemCount: issues.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final issue = issues[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Grid.xxs),
          title: Text(issue.title),
          subtitle: Text(_statusLabel(issue.status)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onIssueTap == null ? null : () => onIssueTap!(issue),
        );
      },
    );
  }
}

String _statusLabel(ProjectIssueStatus status) => switch (status) {
  ProjectIssueStatus.triage => 'Triage',
  ProjectIssueStatus.backlog => 'Backlog',
  ProjectIssueStatus.inProgress => 'In progress',
  ProjectIssueStatus.inReview => 'In review',
  ProjectIssueStatus.approved => 'Approved',
  ProjectIssueStatus.done => 'Done',
  ProjectIssueStatus.closed => 'Closed',
};
