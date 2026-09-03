part of '../settings_page.dart';

class _UpdateSection extends StatefulWidget {
  const _UpdateSection({
    required this.repository,
    required this.download,
    required this.install,
    required this.installedVersionCode,
  });

  final UpdateRepository repository;
  final UpdateDownload download;
  final UpdateInstall install;
  final int installedVersionCode;

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  UpdateManifest? _candidate;
  String? _error;
  var _checking = false;
  var _installing = false;

  Future<void> _check() async {
    if (_checking || _installing) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final candidate = await widget.repository.check(
        installedVersionCode: widget.installedVersionCode,
      );
      if (!mounted) return;
      setState(() => _candidate = candidate);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install() async {
    final candidate = _candidate;
    if (candidate == null || _checking || _installing) return;
    setState(() {
      _installing = true;
      _error = null;
    });

    try {
      final apk = await widget.download(candidate);
      await widget.install(apk);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    final subtitle = _checking
        ? 'Checking the private update channel…'
        : _installing
        ? 'Verifying the download before Android installs it…'
        : candidate != null
        ? 'Update ${candidate.versionName} is ready'
        : _error ?? 'Private Tailnet test updates';

    return AppListCard(
      label: 'Updates',
      verticalPadding: Grid.twelve,
      children: [
        AppListRow(
          key: const ValueKey('updates-check'),
          icon: LucideIcons.download,
          title: 'Check for update',
          subtitle: subtitle,
          trailing: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const _RowChevron(),
          onTap: _checking || _installing ? null : _check,
        ),
        if (candidate != null)
          AppListRow(
            key: const ValueKey('updates-install'),
            icon: LucideIcons.download,
            title: 'Download & install ${candidate.versionName}',
            subtitle: 'Android will ask for final confirmation',
            trailing: _installing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const _RowChevron(),
            onTap: _checking || _installing ? null : _install,
          ),
      ],
    );
  }
}
