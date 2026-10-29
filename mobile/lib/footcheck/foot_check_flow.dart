import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/models.dart';
import '../storage/storage_providers.dart';
import '../ui/clock.dart';
import 'history.dart';
import 'photo_processor.dart';
import 'photo_session.dart';

/// Turns a camera JPEG into the stored photo; tests swap in a direct call
/// (no isolate under fake time).
typedef PhotoProcessor = Future<Uint8List> Function(
  Uint8List jpeg, {
  required double aspect,
});

final photoProcessorProvider = Provider<PhotoProcessor>(
  (ref) => processFootPhotoInBackground,
);

/// One foot check in progress, from Start to "บันทึก": its photos (in a
/// [FootPhotoSession]) and answers. Nothing is stored in the database
/// until [save]; [discard] deletes the photos.
class FootCheckRun {
  FootCheckRun({required this.answerOnly, this.session});

  final bool answerOnly;
  final FootPhotoSession? session;
  final answers = <FootCheckQuestion, FootCheckAnswer>{};

  Map<FootView, String> get photos => session?.photos ?? const {};

  bool get complete => answers.length == FootCheckQuestion.values.length;
}

final footCheckFlowProvider = NotifierProvider<FootCheckFlow, FootCheckRun?>(
  FootCheckFlow.new,
);

class FootCheckFlow extends Notifier<FootCheckRun?> {
  @override
  FootCheckRun? build() => null;

  /// Starts a check; an unsaved earlier run is discarded first.
  Future<FootCheckRun> begin({required bool answerOnly}) async {
    await discard();
    FootPhotoSession? session;
    if (!answerOnly) {
      final root = await ref.read(footPhotoDirProvider)();
      session = FootPhotoSession(
        root: root,
        stamp: photoStampOf(ref.read(clockProvider)()),
      );
    }
    final run = FootCheckRun(answerOnly: answerOnly, session: session);
    state = run;
    return run;
  }

  /// Processes and stores [jpeg] as [view]'s photo; returns its relative
  /// path.
  Future<String> putPhoto(
    FootView view,
    Uint8List jpeg, {
    required double aspect,
  }) async {
    final session = state?.session;
    if (session == null) throw StateError('no photo check in progress');
    final photo = await ref.read(photoProcessorProvider)(jpeg, aspect: aspect);
    final rel = await session.put(view, photo);
    _changed();
    return rel;
  }

  void answer(FootCheckQuestion q, FootCheckAnswer a) {
    state?.answers[q] = a;
    _changed();
  }

  /// Saves through the repository (which decides the result, rule 14) and
  /// ends the run. Throws while an answer is missing.
  Future<FootCheck> save() async {
    final run = state;
    if (run == null) throw StateError('no foot check in progress');
    final check = await ref
        .read(footCheckRepositoryProvider)
        .save(
          FootCheckDraft(
            atMs: ref.read(clockProvider)().millisecondsSinceEpoch,
            redness: run.answers[FootCheckQuestion.redness],
            wound: run.answers[FootCheckQuestion.wound],
            swelling: run.answers[FootCheckQuestion.swelling],
            answerOnly: run.photos.isEmpty,
            photos: run.photos,
          ),
        );
    state = null;
    return check;
  }

  /// Ends the run without saving and deletes its photos.
  Future<void> discard() async {
    final run = state;
    state = null;
    await run?.session?.discard();
  }

  // The run is mutable; a new state object is not needed, only a notify.
  void _changed() => ref.notifyListeners();
}
