import 'package:flutter/material.dart';

import '../theme/typography.dart';

/// The line under health advice (DESIGN-SPEC §5), 16 `inkMuted`. Draft
/// copy (Appendix A).
class DisclaimerLine extends StatelessWidget {
  const DisclaimerLine({super.key});

  static const text =
      'คำแนะนำนี้ไม่ใช่การวินิจฉัยโรค ถ้าไม่แน่ใจ ให้ปรึกษาแพทย์หรือพยาบาล';

  @override
  Widget build(BuildContext context) {
    return const Text(text, style: AppText.secondary);
  }
}
