import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../footcheck/footcheck_providers.dart';
import '../../storage/models.dart';
import '../theme/dimens.dart';
import 'foot_check/saved_view.dart';
import 'foot_check/start_view.dart';

/// "ตรวจเท้าประจำวัน" again from Saved (user decision 4): the tab shows
/// Start until a check is saved or its back link is tapped.
final footCheckRepeatProvider = NotifierProvider<FootCheckRepeat, bool>(
  FootCheckRepeat.new,
);

class FootCheckRepeat extends Notifier<bool> {
  @override
  bool build() {
    // A new saved check (or a new day) ends a repeat.
    ref.watch(todayCheckProvider.select((c) => c.value?.id));
    return false;
  }

  void set(bool v) => state = v;
}

/// The "ตรวจเท้า" tab (DESIGN-SPEC §11): Start until today's check is
/// saved, then Saved (decision 8), or the found-today view when today's
/// latest check found something (user decision 4).
class FootCheckScreen extends ConsumerWidget {
  const FootCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayCheckProvider);
    final repeat = ref.watch(footCheckRepeatProvider);
    final check = today.value;
    final Widget body;
    if (!today.hasValue) {
      body = const SizedBox.shrink();
    } else if (check == null || repeat) {
      body = StartView(
        key: const ValueKey('foot-check-start'),
        repeat: check != null,
      );
    } else {
      body = SavedView(
        key: ValueKey(
          check.result == FootCheckResult.found
              ? 'foot-check-found-today'
              : 'foot-check-saved',
        ),
        check: check,
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        // A new scroll view per view: Saved (after a check) or Start (after
        // "ตรวจอีกครั้ง") opens at the top, not at the other's offset.
        child: SingleChildScrollView(
          key: ValueKey(('foot-check-scroll', body.key)),
          padding: EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            repeat ? Dimens.pageTopPushed : Dimens.pagePadding,
            Dimens.pagePadding,
            Dimens.pageBottom,
          ),
          child: body,
        ),
      ),
    );
  }
}
