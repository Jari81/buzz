import 'package:flutter/material.dart';

import 'project_issue_reducer.dart';

class ProjectIssueCommentDraft {
  final String content;
  final List<List<String>> tags;
  final int createdAt;

  const ProjectIssueCommentDraft({
    required this.content,
    required this.tags,
    required this.createdAt,
  });
}

ProjectIssueCommentDraft buildProjectIssueCommentDraft({
  required ProjectIssue issue,
  required String repositoryOwner,
  required String author,
  required String content,
  required int nowSeconds,
}) {
  final body = content.trim();
  if (body.isEmpty) throw ArgumentError.value(content, 'content', 'empty');
  final normalizedAuthor = author.trim().toLowerCase();
  if (normalizedAuthor.isEmpty) {
    throw ArgumentError.value(author, 'author', 'empty');
  }
  final repositoryAddress = issue.repositoryAddress;
  if (repositoryAddress == null || repositoryAddress.trim().isEmpty) {
    throw StateError('Issue has no repository address.');
  }
  final recipients = <String>{
    repositoryOwner.toLowerCase(),
    issue.author.toLowerCase(),
    for (final tag in issue.tags)
      if (tag.length >= 2 && tag.first == 'p') tag[1].toLowerCase(),
  }..removeWhere((pubkey) => pubkey.isEmpty);
  var createdAt = nowSeconds;
  for (final comment in issue.comments) {
    if (comment.author.toLowerCase() == normalizedAuthor &&
        comment.createdAt >= createdAt) {
      createdAt = comment.createdAt + 1;
    }
  }
  final requiresAction = RegExp(
    r'^(?:test|expected|reply)\s*:',
    caseSensitive: false,
  ).hasMatch(body.trimLeft());
  return ProjectIssueCommentDraft(
    content: body,
    createdAt: createdAt,
    tags: [
      ['e', issue.id, '', 'root'],
      ['a', repositoryAddress],
      for (final recipient in recipients) ['p', recipient],
      if (requiresAction) ['t', 'action-required'],
    ],
  );
}

typedef IssueCommentSubmitter = Future<void> Function(String content);

class IssueCommentComposer extends StatefulWidget {
  final IssueCommentSubmitter onSubmit;
  final bool enabled;
  final void Function(Object error)? onError;

  const IssueCommentComposer({
    required this.onSubmit,
    this.enabled = true,
    this.onError,
    super.key,
  });

  @override
  State<IssueCommentComposer> createState() => _IssueCommentComposerState();
}

class _IssueCommentComposerState extends State<IssueCommentComposer> {
  final _controller = TextEditingController();
  bool _sending = false;

  bool get _canSend =>
      widget.enabled && !_sending && _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _submit() async {
    if (!_canSend) return;
    final content = _controller.text.trim();
    setState(() => _sending = true);
    try {
      await widget.onSubmit(content);
      if (mounted) _controller.clear();
    } catch (error) {
      widget.onError?.call(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: TextField(
          controller: _controller,
          enabled: widget.enabled && !_sending,
          minLines: 1,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'Add comment',
            hintText: 'Plain text',
          ),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton.icon(
        onPressed: _canSend ? _submit : null,
        icon: _sending
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send),
        label: const Text('Send'),
      ),
    ],
  );
}
