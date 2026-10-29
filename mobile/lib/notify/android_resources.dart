/// Android resources looked up by name at runtime (the notification
/// plugin's icons and sounds). The release build's resource shrinker
/// removes any resource no code references by R id, so each name here is
/// also listed in `android/app/src/main/res/raw/keep.xml`. Without it the
/// release APK lacks the resource while debug builds still work (S8C: the
/// Note 10 reminder failed with "invalid_icon").
///
/// Checked by `test/notify/android_resources_test.dart` (names in lib/
/// come from here and are all in keep.xml) and
/// `tool/check_release_resources.sh` (each kept name is in the release
/// APK). S9 alert notifications add their icons and sounds here.
abstract final class AndroidResources {
  static const reminderIcon = 'ic_stat_foot_check';

  /// `res/drawable` names, for keep.xml's `@drawable/…`.
  static const drawables = [reminderIcon];

  /// `res/raw` names (notification sounds), for keep.xml's `@raw/…`.
  static const raws = <String>[];
}
