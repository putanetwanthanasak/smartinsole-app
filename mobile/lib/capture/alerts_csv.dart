import 'dart:convert';

import '../storage/models.dart';
import 'capture_files.dart';

/// The alerts raised while a research capture's session screen was open
/// (BACKLOG 40), as one CSV in that session's export, covered by its
/// `manifest.json`. Export only: the private session folder never holds
/// it; the rows stay in the app's database until "Delete from phone".
const alertsCsvName = 'alerts.csv';

const alertsCsvColumns = [
  'at_ms', // wall-clock unix ms when the alert was raised
  'code', // contract §8.3 code
  'level', // internal level 1–5
  'patient_status', // what Home showed then: noData / safe / careful / rest
  'side', // L / R
  'zone', // pressure zone id (hallux, meta1, …)
  'site', // temperature site (forefoot / heel)
  'measured_value', // in the code's unit
  'threshold', // the thresholds.json value it crossed
  'gait_class',
  'gait_confidence',
  'read_at_ms', // when the patient opened it, if they did
  'details', // JSON object: the detail-row numbers
];

/// The CSV for [alerts] (oldest first), header included; header only when
/// there are none.
String alertsCsv(List<StoredAlert> alerts) {
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final lines = [
    alertsCsvColumns.join(','),
    for (final a in alerts)
      [
        '${a.atMs}',
        a.kind.wireName,
        '${a.level}',
        a.patientLevel.name,
        a.side == null ? '' : sideCode(a.side!),
        a.zone ?? '',
        a.site?.name ?? '',
        a.measuredValue?.toString() ?? '',
        a.threshold?.toString() ?? '',
        a.gaitClass ?? '',
        a.gaitConfidence?.toString() ?? '',
        a.readAtMs?.toString() ?? '',
        a.details == null ? '' : q(jsonEncode(a.details)),
      ].join(','),
  ];
  return '${lines.join('\n')}\n';
}
