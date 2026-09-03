import 'package:buzz/features/projects/project_issue_providers.dart';
import 'package:buzz/features/projects/project_models.dart';
import 'package:buzz/features/projects/projects_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const owner =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  testWidgets(
    'shows listed repositories and keeps unresolved members visible',
    (tester) async {
      final available = ProjectRepository(
        coordinate: const RepositoryCoordinate(owner: owner, dtag: 'app'),
        name: 'App',
        description: 'Mobile repository',
        channelId: 'channel',
        createdAt: 100,
        isAvailable: true,
      );
      final unavailable = ProjectRepository(
        coordinate: const RepositoryCoordinate(owner: owner, dtag: 'missing'),
        name: 'Repository unavailable',
        description: '',
        channelId: null,
        createdAt: null,
        isAvailable: false,
      );
      ProjectRepository? tapped;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectsProvider.overrideWith(
              (ref) async => [
                MobileProject(
                  address: '30621:$owner:mobile',
                  dtag: 'mobile',
                  owner: owner,
                  name: 'Mobile',
                  description: 'Android project',
                  createdAt: 100,
                  repositories: [available, unavailable],
                ),
              ],
            ),
          ],
          child: MaterialApp(
            home: ProjectsPage(onRepositoryTap: (value) => tapped = value),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('Mobile'), findsOneWidget);
      expect(find.text('App'), findsOneWidget);
      expect(find.text('Repository unavailable'), findsOneWidget);

      await tester.tap(find.text('Repository unavailable'));
      expect(tapped, isNull);
      await tester.tap(find.text('App'));
      expect(tapped, same(available));
    },
  );
}
