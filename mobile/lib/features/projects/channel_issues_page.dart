import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/theme/theme.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import 'project_issue_providers.dart';
import 'project_issue_reducer.dart';

class ChannelIssuesPage extends HookConsumerWidget {
  final String channelId;
  final ValueChanged<ProjectIssue>? onIssueTap;

  const ChannelIssuesPage({
    required this.channelId,
    this.onIssueTap,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final selectedAddress = useState<String?>(null);

    return FrostedScaffold(
      appBar: const FrostedAppBar(title: Text('Issues')),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load repositories')),
        data: (value) {
          final repositories = [
            for (final project in value)
              for (final repository in project.repositories)
                if (repository.isAvailable && repository.channelId == channelId)
                  repository,
          ];
          if (repositories.isEmpty) {
            return const Center(child: Text('No repositories linked'));
          }
          final selected =
              repositories
                  .where(
                    (repository) =>
                        repository.coordinate.value == selectedAddress.value,
                  )
                  .firstOrNull ??
              repositories.first;
          final issues = ref.watch(
            repositoryIssuesProvider((
              repositoryAddress: selected.coordinate.value,
              reviewAuthority: selected.reviewAuthority,
            )),
          );
          return Column(
            children: [
              SizedBox(height: frostedAppBarHeight(context)),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Grid.gutter,
                  Grid.xxs,
                  Grid.gutter,
                  Grid.xxs,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: Grid.xxs,
                    runSpacing: Grid.half,
                    children: [
                      for (final repository in repositories)
                        ChoiceChip(
                          label: Text(repository.name),
                          selected:
                              repository.coordinate.value ==
                              selected.coordinate.value,
                          onSelected: (_) => selectedAddress.value =
                              repository.coordinate.value,
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: issues.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) =>
                      const Center(child: Text('Could not load issues')),
                  data: (value) =>
                      _IssueList(issues: value, onIssueTap: onIssueTap),
                ),
              ),
            ],
          );
        },
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
      padding: const EdgeInsets.fromLTRB(
        Grid.gutter,
        Grid.xxs,
        Grid.gutter,
        Grid.xxl,
      ),
      itemCount: issues.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final issue = issues[index];
        return ListTile(
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
  ProjectIssueStatus.approved => 'Approved',
  ProjectIssueStatus.inReview => 'In review',
  ProjectIssueStatus.done => 'Done',
  ProjectIssueStatus.closed => 'Closed',
};
