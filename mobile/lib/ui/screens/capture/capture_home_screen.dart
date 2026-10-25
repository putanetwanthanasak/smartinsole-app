import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../capture/capture_protocol.dart';
import '../../../capture/capture_providers.dart';
import '../../../capture/capture_session.dart';
import '../../../device/device_providers.dart';
import '../../../device/display_snapshot.dart';
import '../../../storage/models.dart' show captureStampOf;
import '../../../storage/storage_providers.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/placeholder_body.dart';
import 'capture_flow_screen.dart';
import 'capture_widgets.dart';

/// Research capture start: pre-check, a new session's coded subject data
/// (doc 03: code, sex, age range, foot length; room temperature), and the
/// sessions already on the phone. Researcher-only, English (S4C).
class CaptureHomeScreen extends ConsumerStatefulWidget {
  const CaptureHomeScreen({super.key});

  @override
  ConsumerState<CaptureHomeScreen> createState() => _CaptureHomeScreenState();
}

class _CaptureHomeScreenState extends ConsumerState<CaptureHomeScreen> {
  final _code = TextEditingController();
  final _footL = TextEditingController();
  final _footR = TextEditingController();
  final _room = TextEditingController();
  Sex? _sex;
  String? _age;
  late int _seed = ref.read(orderSeedProvider)();
  Directory? _root;

  @override
  void initState() {
    super.initState();
    ref.read(researchRootProvider).then((d) {
      if (mounted) setState(() => _root = d);
    });
  }

  @override
  void dispose() {
    for (final c in [_code, _footL, _footR, _room]) {
      c.dispose();
    }
    super.dispose();
  }

  SubjectCode? get _subject => SubjectCode.parse(_code.text);

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _open(CaptureSession session) async {
    // While the session screen is open, alerts carry its stamp
    // (BACKLOG 40). Recording and its timing never depend on this.
    final stamp = captureStampOf(session.sessionId);
    final active = ref.read(activeCaptureProvider.notifier)..open(stamp);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CaptureFlowScreen(session: session),
        ),
      );
    } finally {
      active.close(stamp);
    }
    if (mounted) setState(() {});
  }

  SubjectInfo _subjectInfo(SubjectCode code) => SubjectInfo(
    code: code,
    sex: _sex,
    ageRange: _age,
    footLengthCm: {FootSide.left: ?_num(_footL), FootSide.right: ?_num(_footR)},
  );

  /// Text typed that isn't a number (the formatter still lets "2.5.5" in).
  bool _badNumber(TextEditingController c) =>
      c.text.trim().isNotEmpty && _num(c) == null;

  Future<void> _start() async {
    final code = _subject;
    final root = _root;
    if (code == null || root == null) return;
    final deps = await ref.read(captureDepsProvider.future);
    final session = CaptureSession.create(
      deps: deps,
      researchRoot: root,
      subject: _subjectInfo(code),
      roomTempC: _num(_room),
      seed: _seed,
    );
    setState(() {
      _seed = ref.read(orderSeedProvider)();
      for (final c in [_code, _footL, _footR, _room]) {
        c.clear();
      }
      _sex = null;
      _age = null;
    });
    await _open(session);
  }

  Future<void> _resume(SessionListing s) async {
    final deps = await ref.read(captureDepsProvider.future);
    await _open(CaptureSession.resume(deps: deps, dir: s.dir));
  }

  /// Two confirmations, then [clearTestData]; tagged alerts and the
  /// capture files are never touched.
  Future<void> _clearTestData(int sessionCount) async {
    final kept = sessionCount == 0
        ? ''
        : '\n\n$sessionCount session${sessionCount == 1 ? '' : 's'} on this '
              'phone keep${sessionCount == 1 ? 's' : ''} ${sessionCount == 1 ? 'its' : 'their'} alerts.';
    final first = await _confirm(
      key: 'clear-confirm-1',
      title: 'Clear app database?',
      text:
          'Deletes every alert not tagged with a capture session, and all '
          'temperature readings, daily summaries, foot checks and foot '
          'photos on this phone.$kept',
      action: 'Continue',
    );
    if (!first || !mounted) return;
    final second = await _confirm(
      key: 'clear-confirm-2',
      title: 'This cannot be undone',
      text: 'Clear the app database now?',
      action: 'Clear',
    );
    if (!second || !mounted) return;
    final done = await ref.read(clearTestDataProvider)();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('clear-done'),
        title: const Text('Cleared'),
        content: Text(
          'Removed ${done.alerts} alerts, ${done.temperatureReadings} '
          'temperature readings, ${done.dailySummaries} daily summaries, '
          '${done.footChecks} foot checks and ${done.photos} photo files.'
          '\n\nRestart the app now (close it from Recents and open it '
          'again), so the alert engine starts clean.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm({
    required String key,
    required String title,
    required String text,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: ValueKey(key),
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: ValueKey('$key-ok'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(displaySnapshotProvider).value;
    final sources = {
      for (final side in FootSide.values)
        side: ref.watch(insoleDataSourceProvider(side)),
    };
    final issues = {
      for (final side in FootSide.values)
        side: snap == null
            ? const ['no data yet']
            : precheckIssues(
                snap.of(side),
                hasCalibration: sources[side]!.calibration != null,
              ),
    };
    final precheckOk = issues.values.every((i) => i.isEmpty);
    final code = _subject;
    final codeError = _code.text.isNotEmpty && code == null;
    bool footOk(TextEditingController c) {
      final cm = _num(c);
      return cm == null || footLengthEligible(code, cm);
    }

    final footLOk = footOk(_footL);
    final footROk = footOk(_footR);
    final range =
        '${footLengthInclusionCm.min}–${footLengthInclusionCm.max} cm';
    String? numberError(TextEditingController c, {bool ok = true}) =>
        _badNumber(c) ? 'Not a number' : (ok ? null : range);
    final numbersOk = ![_footL, _footR, _room].any(_badNumber);
    // Before the code is valid the study rule applies (as for foot length).
    final optional = code?.rehearsal ?? false ? ' (optional)' : '';
    final missing = code == null
        ? const <String>[]
        : missingForStudy(_subjectInfo(code), _num(_room));
    final root = _root;
    final sessions = root == null
        ? const <SessionListing>[]
        : listSessions(root);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: const Text('Research capture'),
      ),
      body: PageBody(
        children: [
          const CaptureBanner(
            palette: StatusColors.noData,
            icon: Icons.shield_outlined,
            text:
                'Subject codes only, never a name. Data stays in this '
                "app's private storage until you export it.",
          ),
          _Section(
            title: '1 · Pre-check',
            children: [
              for (final side in FootSide.values)
                if (snap != null)
                  FootLinkRow(view: snap.of(side), issues: issues[side])
                else
                  FootLinkRow(
                    view: FootView(
                      side: side,
                      connection: FootConnection.notConnected,
                    ),
                    issues: issues[side],
                  ),
              Text(
                'Both feet streaming, battery ≥ '
                '${CaptureTimings.minBatteryPct} %, firmware and '
                'calibration read. Connect both insoles first '
                '(Settings → เชื่อมต่อแผ่นรองเท้า).',
                style: AppText.secondary,
              ),
            ],
          ),
          _Section(
            title: '2 · New session',
            children: [
              TextField(
                key: const ValueKey('capture-code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  labelText: 'Subject code',
                  hintText: 'SI-001 (TEST-001 = rehearsal)',
                  errorText: codeError ? 'Use SI-nnn or TEST-nnn' : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              Text('Sex$optional', style: AppText.secondary),
              SegmentedButton<Sex>(
                key: const ValueKey('capture-sex'),
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                segments: [
                  for (final s in Sex.values)
                    ButtonSegment(value: s, label: Text(s.en)),
                ],
                selected: {?_sex},
                onSelectionChanged: (v) =>
                    setState(() => _sex = v.isEmpty ? null : v.first),
              ),
              DropdownButtonFormField<String>(
                key: const ValueKey('capture-age'),
                initialValue: _age,
                decoration: InputDecoration(labelText: 'Age range$optional'),
                items: [
                  for (final a in ageRanges)
                    DropdownMenuItem(value: a, child: Text(a)),
                ],
                onChanged: (v) => setState(() => _age = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      key: const ValueKey('capture-foot-l'),
                      controller: _footL,
                      label: 'Foot L (cm)',
                      errorText: numberError(_footL, ok: footLOk),
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      key: const ValueKey('capture-foot-r'),
                      controller: _footR,
                      label: 'Foot R (cm)',
                      errorText: numberError(_footR, ok: footROk),
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (!footLOk || !footROk)
                Text(
                  'Does not meet the inclusion criteria '
                  '(foot length $range).',
                  key: const ValueKey('capture-foot-ineligible'),
                  style: AppText.secondary.copyWith(
                    color: StatusColors.careful.text,
                  ),
                ),
              _NumberField(
                key: const ValueKey('capture-room'),
                controller: _room,
                label: 'Room temperature (°C)$optional',
                errorText: numberError(_room),
                onChanged: () => setState(() {}),
              ),
              if (code != null) _Plan(code: code, seed: _seed),
              if (missing.isNotEmpty)
                Text(
                  'Required for SI- codes: ${missing.join(', ')}.',
                  key: const ValueKey('capture-missing'),
                  style: AppText.secondary,
                ),
              FilledButton(
                key: const ValueKey('capture-start'),
                onPressed:
                    code != null &&
                        precheckOk &&
                        root != null &&
                        footLOk &&
                        footROk &&
                        numbersOk &&
                        missing.isEmpty
                    ? _start
                    : null,
                child: const Text('Start session'),
              ),
            ],
          ),
          _Section(
            title: '3 · On this phone',
            children: [
              if (sessions.isEmpty)
                Text('No sessions yet.', style: AppText.secondary),
              for (final s in sessions)
                _SessionTile(
                  key: ValueKey('capture-session-${s.sessionId}'),
                  listing: s,
                  onOpen: () => _resume(s),
                ),
            ],
          ),
          _Section(
            title: '4 · App database (test data)',
            children: [
              Text(
                'Before the study: clears the patient screens\' test data. '
                'Capture sessions, their alerts and the export folder '
                'stay.',
                style: AppText.secondary,
              ),
              OutlinedButton(
                key: const ValueKey('clear-test-data'),
                onPressed: ref.watch(activeCaptureProvider) == null
                    ? () => _clearTestData(sessions.length)
                    : null,
                child: const Text('Clear app database (test data)'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppText.cardTitle),
            for (final c in children) ...[const SizedBox(height: 10), c],
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        LengthLimitingTextInputFormatter(5),
      ],
      decoration: InputDecoration(labelText: label, errorText: errorText),
      onChanged: onChanged == null ? null : (_) => onChanged!(),
    );
  }
}

/// The order and pain side this code will get.
class _Plan extends StatelessWidget {
  const _Plan({required this.code, required this.seed});

  final SubjectCode code;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final t = CaptureTimings.of(code);
    final order = trialOrder(seed);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order (random, normal first)', style: AppText.bodyStrong),
          for (var i = 0; i < order.length; i++)
            Text(
              '${i + 1}. ${order[i].en} · ${order[i].th}',
              style: AppText.secondary,
            ),
          const SizedBox(height: 6),
          Text(
            'Antalgic pain side: ${sideName(code.painSide)} '
            '(${code.number.isOdd ? 'odd' : 'even'} code)',
            style: AppText.secondary,
          ),
          if (code.rehearsal)
            Text(
              'Rehearsal timers: calibration ${t.calibration.inSeconds} s, '
              'trials ${t.trial.inSeconds} s, practice '
              '${t.practice.inSeconds} s',
              style: AppText.secondary.copyWith(fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({super.key, required this.listing, required this.onOpen});

  final SessionListing listing;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final status = [
      listing.done ? 'done' : 'open',
      listing.exported ? 'exported' : 'not exported',
    ].join(' · ');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(listing.sessionId, style: AppText.bodyStrong),
              Text(status, style: AppText.secondary),
            ],
          ),
        ),
        OutlinedButton(
          // The theme's buttons are full width; this one sits in a row.
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(96, Dimens.minTouchTarget),
          ),
          onPressed: onOpen,
          child: Text(listing.done ? 'Open' : 'Resume'),
        ),
      ],
    );
  }
}
