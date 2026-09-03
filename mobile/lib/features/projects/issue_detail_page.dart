import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/profile/user_cache_provider.dart';
import '../../shared/profile/user_profile.dart';
import '../../shared/relay/relay.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/avatar_image.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import 'project_issue_reducer.dart';
import 'project_models.dart';

typedef ProjectContentBuilder =
    Widget Function(
      BuildContext context,
      String content,
      List<List<String>> tags,
    );

class IssueDetailPage extends ConsumerStatefulWidget {
  final ProjectIssue issue;
  final ProjectContentBuilder contentBuilder;

  const IssueDetailPage({
    required this.issue,
    required this.contentBuilder,
    super.key,
  });

  @override
  ConsumerState<IssueDetailPage> createState() => _IssueDetailPageState();
}

class _IssueDetailPageState extends ConsumerState<IssueDetailPage> {
  late ProjectIssue _issue;

  @override
  void initState() {
    super.initState();
    _issue = widget.issue;
  }

  @override
  void didUpdateWidget(covariant IssueDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.issue.id != _issue.id || widget.issue.updatedAt >= _issue.updatedAt) {
      _issue = widget.issue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    final profiles = ref.watch(userCacheProvider);
    final authors = {
      issue.author,
      ...issue.assignees,
      ...issue.comments.map((comment) => comment.author),
    };
    for (final author in authors) {
      if (!profiles.containsKey(author.toLowerCase())) {
        ref.read(userCacheProvider.notifier).get(author);
      }
    }
    return FrostedScaffold(
      appBar: const FrostedAppBar(title: Text('Issue')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Grid.gutter,
          frostedAppBarHeight(context) + Grid.gutter,
          Grid.gutter,
          Grid.xxl,
        ),
        children: [
          Text(issue.title, style: context.textTheme.headlineSmall),
          const SizedBox(height: Grid.xxs),
          Wrap(
            spacing: Grid.xxs,
            runSpacing: Grid.half,
            children: [
              Chip(label: Text(_statusLabel(issue.status))),
              for (final label in issue.labels) Chip(label: Text(label)),
            ],
          ),
          const SizedBox(height: Grid.gutter),
          _Identity(
            profile: profiles[issue.author.toLowerCase()],
            pubkey: issue.author,
          ),
          const SizedBox(height: Grid.xxs),
          widget.contentBuilder(context, issue.content, issue.tags),
          const SizedBox(height: Grid.gutter),
          Text(
            'Created ${_formatTimestamp(issue.createdAt)} · '
            'Updated ${_formatTimestamp(issue.updatedAt)}',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (issue.assignees.isNotEmpty) ...[
            const SizedBox(height: Grid.xl),
            Text('Assignees', style: context.textTheme.titleMedium),
            const SizedBox(height: Grid.xxs),
            Wrap(
              spacing: Grid.xxs,
              runSpacing: Grid.xxs,
              children: [
                for (final assignee in issue.assignees)
                  _Identity(
                    profile: profiles[assignee.toLowerCase()],
                    pubkey: assignee,
                  ),
              ],
            ),
          ],
          if (issue.currentReview case final review?) ...[
            const SizedBox(height: Grid.xl),
            Text('Current review', style: context.textTheme.titleMedium),
            const SizedBox(height: Grid.xxs),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Grid.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Review-ID'),
                    Text(review.reviewId),
                    if (review.target?.isNotEmpty == true) ...[
                      const Text('Target'),
                      Text(review.target!),
                    ],
                    const Text('Evidence'),
                    Text(review.evidence),
                    const Text('Test'),
                    Text(review.test),
                    const Text('Known limitations'),
                    Text(review.limitations),
                    if (review.verdict != null) ...[
                      const SizedBox(height: Grid.xxs),
                      Text(
                        review.verdict!.kind == 'accepted'
                            ? 'Done'
                            : 'Rejected; rework requested',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: Grid.xl),
          Text('Comments', style: context.textTheme.titleMedium),
          if (issue.comments.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: Grid.xxs),
              child: Text('No comments'),
            )
          else
            for (final comment in issue.comments) ...[
              const SizedBox(height: Grid.gutter),
              _Identity(
                profile: profiles[comment.author.toLowerCase()],
                pubkey: comment.author,
              ),
              const SizedBox(height: Grid.half),
              widget.contentBuilder(context, comment.content, comment.tags),
              const SizedBox(height: Grid.half),
              Text(
                _formatTimestamp(comment.createdAt),
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
        ],
      ),
    );
  }

}

class _Identity extends StatelessWidget {
  final UserProfile? profile;
  final String pubkey;

  const _Identity({required this.profile, required this.pubkey});

  @override
  Widget build(BuildContext context) {
    final label = profile?.label ?? _shortPubkey(pubkey);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AvatarImage(
          imageUrl: profile?.avatarUrl,
          radius: 12,
          fallback: Text(label.characters.first.toUpperCase()),
        ),
        const SizedBox(width: Grid.half),
        Text(label),
      ],
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

String _shortPubkey(String pubkey) =>
    pubkey.length <= 8 ? pubkey : '${pubkey.substring(0, 8)}…';

String _formatTimestamp(int timestamp) => DateFormat.yMMMd().add_jm().format(
  DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toLocal(),
);
