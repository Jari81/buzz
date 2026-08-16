part of '../channel_detail_page.dart';

class _HuddleCallParticipants extends StatelessWidget {
  const _HuddleCallParticipants({
    required this.connected,
    required this.error,
    required this.profiles,
    required this.fallbackLabels,
    required this.remotePubkeys,
    required this.localPubkey,
    required this.activeSpeakerPubkeys,
    required this.retryTooltip,
    required this.retryIcon,
    required this.onRetry,
  });

  final bool connected;
  final String? error;
  final Map<String, UserProfile> profiles;
  final Map<String, String> fallbackLabels;
  final List<String> remotePubkeys;
  final String? localPubkey;
  final Set<String> activeSpeakerPubkeys;
  final String retryTooltip;
  final IconData retryIcon;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error case final message?) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.triangleAlert,
                size: 32,
                color: context.colors.error,
              ),
              const SizedBox(height: Grid.xxs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.error,
                ),
              ),
              const SizedBox(height: Grid.xs),
              IconButton.filledTonal(
                key: const ValueKey('huddle-retry'),
                tooltip: retryTooltip,
                onPressed: onRetry,
                icon: Icon(retryIcon),
              ),
            ],
          ),
        ),
      );
    }

    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final hasRemoteParticipants = connected && remotePubkeys.isNotEmpty;
    final movementDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final entryDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Stack(
      key: const ValueKey('huddle-participant-stage'),
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            key: const ValueKey('huddle-local-participant-motion'),
            duration: movementDuration,
            curve: Curves.easeInOutCubic,
            tween: Tween(
              begin: hasRemoteParticipants ? 1 : 0,
              end: hasRemoteParticipants ? 1 : 0,
            ),
            builder: (context, value, child) => FractionallySizedBox(
              heightFactor: 0.5,
              alignment: Alignment.lerp(
                Alignment.center,
                Alignment.bottomCenter,
                value,
              )!,
              child: Align(
                key: const ValueKey('huddle-local-participant'),
                alignment: Alignment.lerp(
                  Alignment.center,
                  const Alignment(0, -0.35),
                  value,
                )!,
                child: child,
              ),
            ),
            child: _HuddleCallAvatar(
              pubkey: localPubkey ?? '',
              profile: localPubkey == null ? null : profiles[localPubkey],
              fallbackLabel: null,
              active:
                  localPubkey != null &&
                  activeSpeakerPubkeys.contains(localPubkey),
              isSelf: true,
            ),
          ),
        ),
        Positioned.fill(
          child: FractionallySizedBox(
            heightFactor: 0.5,
            alignment: Alignment.topCenter,
            child: Align(
              key: const ValueKey('huddle-remote-participant-group'),
              alignment: const Alignment(0, 0.35),
              child: connected
                  ? SingleChildScrollView(
                      key: const ValueKey('huddle-remote-participants'),
                      padding: const EdgeInsets.symmetric(vertical: Grid.xs),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: Grid.md,
                        runSpacing: Grid.xs,
                        children: [
                          for (final pubkey in remotePubkeys)
                            SizedBox(
                              key: ValueKey('huddle-participant-entry-$pubkey'),
                              width: _huddleAvatarFrameSize,
                              child: TweenAnimationBuilder<double>(
                                duration: entryDuration,
                                curve: Curves.easeOutCubic,
                                tween: Tween(begin: 0, end: 1),
                                builder: (context, value, child) => Opacity(
                                  opacity: value,
                                  child: Transform.scale(
                                    scale: 0.95 + value * 0.05,
                                    child: child,
                                  ),
                                ),
                                child: _HuddleCallAvatar(
                                  pubkey: pubkey,
                                  profile: profiles[pubkey],
                                  fallbackLabel: fallbackLabels[pubkey],
                                  active: activeSpeakerPubkeys.contains(pubkey),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : const BuzzLoadingIndicator(size: 40),
            ),
          ),
        ),
      ],
    );
  }
}
