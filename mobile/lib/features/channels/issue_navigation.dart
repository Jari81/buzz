import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/deeplink/deep_link.dart';

typedef ChannelIssuesPageBuilder =
    Widget Function(BuildContext context, String channelId);
typedef EntityDeepLinkOpener =
    void Function(BuildContext context, EntityDeepLink link);

/// Project-agnostic navigation hooks supplied by the app composition root.
class ChannelIssueNavigation {
  final ChannelIssuesPageBuilder buildIssuesPage;
  final EntityDeepLinkOpener openEntity;

  const ChannelIssueNavigation({
    required this.buildIssuesPage,
    required this.openEntity,
  });

  WidgetBuilder issuesPageFor(String channelId) =>
      (context) => buildIssuesPage(context, channelId);

  ValueChanged<EntityDeepLink> entityOpenerFor(BuildContext context) =>
      (link) => openEntity(context, link);
}

final channelIssueNavigationProvider = Provider<ChannelIssueNavigation?>(
  (ref) => null,
);
