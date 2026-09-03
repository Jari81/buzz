import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/deeplink/deep_link.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import 'issue_detail_page.dart';
import 'project_issue_providers.dart';

class IssueLinkPage extends ConsumerWidget {
  final EntityDeepLink link;
  final ProjectContentBuilder contentBuilder;

  const IssueLinkPage({
    required this.link,
    required this.contentBuilder,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventId = link.eventId;
    if (link.type != 'issue' || eventId == null) {
      return const _IssueLinkFailure(message: 'Issue link unavailable');
    }
    final repositoryAddress = '30617:${link.owner}:${link.repository}';
    return ref
        .watch(
          linkedIssueProvider((
            repositoryAddress: repositoryAddress,
            eventId: eventId,
            reviewAuthority: null,
          )),
        )
        .when(
          loading: () => const FrostedScaffold(
            appBar: FrostedAppBar(title: Text('Issue')),
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) =>
              const _IssueLinkFailure(message: 'Could not load issue'),
          data: (issue) {
            if (issue == null) {
              return const _IssueLinkFailure(message: 'Issue not found');
            }
            return IssueDetailPage(
              issue: issue,
              contentBuilder: contentBuilder,
            );
          },
        );
  }
}

class _IssueLinkFailure extends StatelessWidget {
  final String message;

  const _IssueLinkFailure({required this.message});

  @override
  Widget build(BuildContext context) => FrostedScaffold(
    appBar: const FrostedAppBar(title: Text('Issue')),
    body: Center(child: Text(message)),
  );
}
