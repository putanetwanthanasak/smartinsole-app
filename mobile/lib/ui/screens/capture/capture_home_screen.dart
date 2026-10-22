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
  int _seed = newOrderSeed();
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaptureFlowScreen(session: session),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final code = _subject;
    final root = _root;
    if (code == null || root == null) return;
    final deps = await ref.read(captureDepsProvider.future);
    final session = CaptureSession.create(
      deps: deps,
      researchRoot: root,
      subject: SubjectInfo(
        code: code,
        sex: _sex,
        ageRange: _age,
        footLengthCm: {
          FootSide.left: ?_num(_footL),
          FootSide.right: ?_num(_footR),
        },
      ),
      roomTempC: _num(_room),
      seed: _seed,
    );
    setState(() {
      _seed = newOrderSeed();
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
                'calibration read. Connect the insoles from Home first.',
                style: AppText.small,
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
              Text('Sex (optional)', style: AppText.small),
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
                decoration: const InputDecoration(
                  labelText: 'Age range (optional)',
                ),
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
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      key: const ValueKey('capture-foot-r'),
                      controller: _footR,
                      label: 'Foot R (cm)',
                    ),
                  ),
                ],
              ),
              _NumberField(
                key: const ValueKey('capture-room'),
                controller: _room,
                label: 'Room temperature (°C)',
              ),
              if (code != null) _Plan(code: code, seed: _seed),
              FilledButton(
                key: const ValueKey('capture-start'),
                onPressed: code != null && precheckOk && root != null
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
                Text('No sessions yet.', style: AppText.small),
              for (final s in sessions)
                _SessionTile(
                  key: ValueKey('capture-session-${s.sessionId}'),
                  listing: s,
                  onOpen: () => _resume(s),
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
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        LengthLimitingTextInputFormatter(5),
      ],
      decoration: InputDecoration(labelText: label),
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
        color: AppColors.info,
        borderRadius: BorderRadius.circular(Dimens.radiusTip),
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
              Text(status, style: AppText.small),
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
