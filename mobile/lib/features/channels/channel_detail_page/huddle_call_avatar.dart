part of '../channel_detail_page.dart';

class _HuddleCallAvatar extends HookWidget {
  const _HuddleCallAvatar({
    required this.pubkey,
    required this.profile,
    required this.fallbackLabel,
    required this.active,
    this.isSelf = false,
  });

  final String pubkey;
  final UserProfile? profile;
  final String? fallbackLabel;
  final bool active;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final showsLabel = useState(false);
    final profileName = profile?.displayName?.trim();
    final directoryName = fallbackLabel?.trim();
    final label = isSelf
        ? 'You'
        : (profileName?.isNotEmpty == true ? profileName : null) ??
              (directoryName?.isNotEmpty == true ? directoryName : null) ??
              (pubkey.isEmpty ? 'Participant' : shortPubkey(pubkey));
    void toggleLabel() => showsLabel.value = !showsLabel.value;

    return SizedBox(
      width: _huddleAvatarFrameSize,
      child: Semantics(
        label: active ? '$label, speaking' : label,
        hint: showsLabel.value
            ? 'Tap to hide participant name'
            : 'Tap to show participant name',
        button: true,
        onTap: toggleLabel,
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('huddle-participant-avatar-$pubkey'),
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: toggleLabel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                key: ValueKey('huddle-speaking-ring-$pubkey'),
                duration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                tween: Tween(end: active ? 1 : 0),
                builder: (context, value, child) => SizedBox.square(
                  dimension: _huddleAvatarFrameSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: value,
                        child: Transform.scale(
                          scale: 1 + value * 0.08,
                          child: Container(
                            width: _huddleSpeakingRingSize,
                            height: _huddleSpeakingRingSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.colors.primary,
                                width: 4,
                              ),
                            ),
                          ),
                        ),
                      ),
                      child!,
                    ],
                  ),
                ),
                child: AvatarImage(
                  imageUrl: profile?.avatarUrl,
                  radius: _huddleAvatarRadius,
                  backgroundColor: context.colors.primaryContainer,
                  fallback: Icon(
                    LucideIcons.userRound,
                    size: 44,
                    color: context.colors.onPrimaryContainer,
                  ),
                ),
              ),
              AnimatedSwitcher(
                key: ValueKey('huddle-participant-label-reveal-$pubkey'),
                duration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                reverseDuration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, ?currentChild],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
                child: showsLabel.value
                    ? Padding(
                        key: ValueKey('huddle-participant-label-$pubkey'),
                        padding: const EdgeInsets.only(top: Grid.half),
                        child: SizedBox(
                          width: _huddleAvatarFrameSize,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: context.textTheme.labelLarge?.copyWith(
                              color: context.colors.onSurface,
                              fontWeight: active ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                      )
                    : SizedBox(
                        key: ValueKey('huddle-participant-label-empty-$pubkey'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
