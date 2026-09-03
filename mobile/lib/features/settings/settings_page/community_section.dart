part of '../settings_page.dart';

class _CommunitySection extends ConsumerWidget {
  const _CommunitySection({required this.invitePageBuilder});

  final WidgetBuilder invitePageBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(currentCommunityRoleProvider);
    final canInvite =
        roleAsync.hasError || canManageCommunityInvites(roleAsync.value);
    final preference = ref.watch(communityThemeProvider);

    return AppListCard(
      label: 'Community',
      verticalPadding: Grid.twelve,
      children: [
        if (canInvite)
          AppListRow(
            icon: LucideIcons.userPlus,
            title: 'Invite to community',
            trailing: const _RowChevron(),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: invitePageBuilder)),
          ),
        AppListRow(
          key: const ValueKey('community-theme-row'),
          icon: LucideIcons.palette,
          title: 'Theme',
          value: themeSelectionLabel(preference.theme, preference.mode),
          trailing: const _RowChevron(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ThemePickerPage()),
          ),
        ),
      ],
    );
  }
}

class _MobilePreviewSection extends ConsumerWidget {
  const _MobilePreviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final community = ref.watch(activeCommunityProvider).value;
    if (community == null) return const SizedBox.shrink();

    return AppListCard(
      label: 'Mobile Preview · This community',
      verticalPadding: Grid.twelve,
      children: [
        AppListRow(
          key: const ValueKey('mobile-preview-projects-row'),
          icon: LucideIcons.folderGit2,
          title: 'Projects',
          trailing: Switch.adaptive(
            key: const ValueKey('mobile-preview-projects-toggle'),
            value: community.previewProjects,
            onChanged: (enabled) {
              unawaited(
                ref
                    .read(communityListProvider.notifier)
                    .setPreviewProjects(community.id, enabled),
              );
            },
          ),
        ),
      ],
    );
  }
}
