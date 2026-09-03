import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/theme/theme.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import 'project_issue_providers.dart';
import 'project_models.dart';

class ProjectsPage extends ConsumerWidget {
  final ValueChanged<ProjectRepository>? onRepositoryTap;

  const ProjectsPage({this.onRepositoryTap, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return FrostedScaffold(
      appBar: const FrostedAppBar(title: Text('Projects')),
      body: projects.when(
        data: (value) =>
            _ProjectList(projects: value, onRepositoryTap: onRepositoryTap),
        error: (_, _) => const Center(child: Text('Could not load Projects')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ProjectList extends StatelessWidget {
  final List<MobileProject> projects;
  final ValueChanged<ProjectRepository>? onRepositoryTap;

  const _ProjectList({required this.projects, required this.onRepositoryTap});

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return const Center(child: Text('No listed projects'));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        Grid.gutter,
        frostedAppBarHeight(context) + Grid.gutter,
        Grid.gutter,
        Grid.xxl,
      ),
      itemCount: projects.length,
      separatorBuilder: (_, _) => const SizedBox(height: Grid.gutter),
      itemBuilder: (context, index) {
        final project = projects[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Grid.gutter,
                  Grid.gutter,
                  Grid.gutter,
                  Grid.xxs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: context.textTheme.titleMedium),
                    if (project.description.isNotEmpty) ...[
                      const SizedBox(height: Grid.half),
                      Text(
                        project.description,
                        style: context.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              for (final repository in project.repositories)
                ListTile(
                  enabled: repository.isAvailable,
                  title: Text(repository.name),
                  subtitle: repository.description.isEmpty
                      ? null
                      : Text(repository.description),
                  onTap: repository.isAvailable && onRepositoryTap != null
                      ? () => onRepositoryTap!(repository)
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}
