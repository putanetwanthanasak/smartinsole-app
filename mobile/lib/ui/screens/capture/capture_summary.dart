import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../capture/capture_providers.dart';
import '../../../capture/capture_session.dart';
import '../../../capture/export.dart';
import '../../../storage/storage_providers.dart';
import '../../routes.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/placeholder_body.dart';
import 'capture_widgets.dart';

/// The summary as a pushed page (from the flow's app bar).
class CaptureSummaryScreen extends StatelessWidget {
  const CaptureSummaryScreen({super.key, required this.session});

  final CaptureSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: Text('${session.subject.code.code} · Summary'),
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) => PageBody(
          children: [CaptureSummary(session: session, pushed: true)],
        ),
      ),
    );
  }
}

/// Every trial and attempt, Export, and Delete from phone.
class CaptureSummary extends ConsumerStatefulWidget {
  const CaptureSummary({super.key, required this.session, this.pushed = false});

  final CaptureSession session;

  /// Shown as its own page: redo pops back to the flow.
  final bool pushed;

  @override
  ConsumerState<CaptureSummary> createState() => _CaptureSummaryState();
}

class _CaptureSummaryState extends ConsumerState<CaptureSummary> {
  String? _exportResult;
  bool _busy = false;

  CaptureSession get s => widget.session;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final root = await ref.read(exportRootProvider);
      if (root == null) {
        setState(() => _exportResult = 'No app-specific external storage.');
        return;
      }
      final (entries, alerts) = await exportSession(
        s,
        root,
        ref.read(alertRepositoryProvider),
      );
      setState(
        () => _exportResult =
            'Staged ${entries.length} files ($alerts alerts) with '
            'manifest.json in\n'
            '${root.path}/${s.sessionId}\n'
            'On the laptop: tools/capture/export_capture.py',
      );
    } on Object catch (e) {
      setState(() => _exportResult = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('capture-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _delete() async {
    if (!await _confirm(
      'Delete from phone?',
      'Only after the export is pulled to the laptop, checked, and backed '
          'up in a second place.',
      'Continue',
    )) {
      return;
    }
    if (!mounted) return;
    if (!await _confirm(
      'Delete ${s.sessionId}?',
      'Every file of this session is removed from the phone. This cannot '
          'be undone.',
      'Delete',
    )) {
      return;
    }
    // Its alerts leave the phone with it (BACKLOG 40).
    await deleteSession(s, ref.read(alertRepositoryProvider));
    // Back to the capture home, whose list no longer has this session.
    if (mounted) {
      Navigator.of(context).popUntil(ModalRoute.withName(Routes.capture));
    }
  }

  Future<void> _redo(int index) async {
    final plan = s.trials[index].plan;
    if (!await _confirm(
      'Record ${plan.gait?.en ?? 'calibration'} again?',
      'Its current attempt is kept, marked invalid (redo).',
      'Redo',
    )) {
      return;
    }
    s.reopen(index);
    if (widget.pushed && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canRedo =
        s.phase == CapturePhase.done || s.phase == CapturePhase.ready;
    final done = s.trials.where((t) => t.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaptureBanner(
          palette: done == s.trials.length
              ? StatusColors.safe
              : StatusColors.noData,
          icon: LucideIcons.list_checks,
          text: '$done of ${s.trials.length} trials recorded',
        ),
        const SizedBox(height: Dimens.cardGap),
        for (var i = 0; i < s.trials.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _TrialRow(
            key: ValueKey('capture-trial-$i'),
            trial: s.trials[i],
            onRedo: canRedo && s.trials[i].done ? () => _redo(i) : null,
          ),
        ],
        const SizedBox(height: Dimens.cardGap),
        FilledButton.icon(
          key: const ValueKey('capture-export'),
          onPressed: _busy ? null : _export,
          icon: const Icon(LucideIcons.hard_drive_upload),
          label: const Text('Export for USB (adb)'),
        ),
        if (_exportResult != null) ...[
          const SizedBox(height: 8),
          Text(
            _exportResult!,
            key: const ValueKey('capture-export-result'),
            style: AppText.secondary,
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('capture-delete'),
          onPressed: s.exports.isEmpty || _busy ? null : _delete,
          child: const Text('Delete from phone'),
        ),
        Text(
          s.exports.isEmpty
              ? 'Delete is available after an export.'
              : 'Last export: ${s.exports.last}',
          style: AppText.secondary,
        ),
      ],
    );
  }
}

class _TrialRow extends StatelessWidget {
  const _TrialRow({super.key, required this.trial, required this.onRedo});

  final TrialState trial;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final g = trial.plan.gait;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              trial.done ? LucideIcons.circle_check : LucideIcons.circle,
              color: trial.done
                  ? StatusColors.safe.icon
                  : StatusColors.noData.icon,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${trial.plan.number}. ${g?.en ?? 'Calibration'}'
                    '${g == null ? '' : ' · ${g.th}'}',
                    style: AppText.bodyStrong,
                  ),
                  for (final a in trial.attempts)
                    Text(
                      'a${a.attempt}: ${a.endReason == null ? 'recording' : endReasonId(a.endReason!)}'
                      '${a.valid ? '' : ' · invalid (${a.invalidReason})'}'
                      '${a.gapCount > 0 ? ' · ${a.gapCount} gap(s)' : ''}'
                      '${a.samples.isEmpty ? '' : ' · L ${a.samples[FootSide.left]} / R ${a.samples[FootSide.right]}'}',
                      style: AppText.secondary,
                    ),
                ],
              ),
            ),
            if (onRedo != null)
              TextButton(onPressed: onRedo, child: const Text('Redo')),
          ],
        ),
      ),
    );
  }
}
