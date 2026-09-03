part of '../thread_detail_page.dart';

FrostedAppBar _buildThreadAppBar({
  required BuildContext context,
  required bool usesNativeIosGlassBackButton,
  required ValueListenable<bool> messageActionBackdropActive,
  required bool projectsPreviewEnabled,
  required WidgetBuilder? issuesPageBuilder,
}) {
  return FrostedAppBar(
    leading: usesNativeIosGlassBackButton
        ? IosGlassNavigationButton(
            key: const ValueKey('thread-ios-glass-back'),
            icon: IosGlassNavigationIcon.back,
            semanticLabel: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            width: iosGlassChannelHeaderLeadingWidth,
            buttonCenterX: iosGlassChannelHeaderButtonCenterX,
            nativeViewSuppressed: messageActionBackdropActive,
          )
        : null,
    iconColor: context.colors.primary,
    title: Padding(
      padding: EdgeInsets.only(
        left: usesNativeIosGlassBackButton
            ? iosGlassChannelHeaderTitleSpacing
            : 0,
      ),
      child: const Text('Thread', key: ValueKey('thread-app-bar-title')),
    ),
    titleStyle: channelTitleTextStyle,
    actions: [
      if (projectsPreviewEnabled && issuesPageBuilder != null)
        IconButton(
          tooltip: 'Issues',
          color: context.colors.primary,
          icon: const Icon(Icons.adjust),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: issuesPageBuilder)),
        ),
    ],
  );
}
