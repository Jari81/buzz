part of '../channel_detail_page.dart';

class _HuddleCallControls extends StatelessWidget {
  const _HuddleCallControls({
    required this.isMuted,
    required this.isSpeakerEnabled,
    required this.onToggleMute,
    required this.onToggleSpeaker,
  });

  final bool isMuted;
  final bool isSpeakerEnabled;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Grid.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _HuddleRoundControl(
            key: const ValueKey('huddle-speaker-toggle'),
            tooltip: isSpeakerEnabled ? 'Use earpiece' : 'Use speaker',
            icon: LucideIcons.volume2,
            foregroundColor: isSpeakerEnabled
                ? context.colors.onPrimary
                : context.colors.onSurface,
            backgroundColor: isSpeakerEnabled
                ? context.colors.primary
                : context.colors.surfaceContainerHighest,
            dimension: 72,
            toggled: isSpeakerEnabled,
            onPressed: onToggleSpeaker,
          ),
          const SizedBox(width: Grid.sm),
          _HuddleRoundControl(
            key: const ValueKey('huddle-mute-toggle'),
            tooltip: isMuted ? 'Unmute' : 'Mute',
            icon: isMuted ? LucideIcons.micOff : LucideIcons.mic,
            foregroundColor: isMuted
                ? context.colors.onSurface
                : context.colors.onPrimary,
            backgroundColor: isMuted
                ? context.colors.surfaceContainerHighest
                : context.colors.primary,
            dimension: 72,
            toggled: isMuted,
            onPressed: onToggleMute,
          ),
        ],
      ),
    );
  }
}

class _HuddleRoundControl extends StatelessWidget {
  const _HuddleRoundControl({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.onPressed,
    this.dimension = 64,
    this.showTooltip = true,
    this.toggled,
  });

  final String tooltip;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;
  final VoidCallback? onPressed;
  final double dimension;
  final bool showTooltip;
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      enabled: onPressed != null,
      toggled: toggled,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: dimension,
          child: IconButton(
            tooltip: showTooltip ? tooltip : null,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              foregroundColor: foregroundColor,
              backgroundColor: backgroundColor,
              disabledForegroundColor: foregroundColor.withValues(alpha: 0.5),
              disabledBackgroundColor: backgroundColor.withValues(alpha: 0.5),
            ),
            icon: Icon(icon, size: 28),
          ),
        ),
      ),
    );
  }
}
