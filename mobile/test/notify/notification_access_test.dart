import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/notify/notification_access.dart';

/// A phone: [grantOnPrompt] is what the user answers in the Android 13+
/// prompt.
class FakeNotificationPlatform implements NotificationPlatform {
  FakeNotificationPlatform({
    required this.sdk,
    this.enabled = true,
    bool? permission,
    this.appOpAllowed = true,
    this.grantOnPrompt = false,
  }) : permission = permission ?? sdk < 33;

  final int sdk;
  bool enabled;
  bool permission;
  bool appOpAllowed;
  bool grantOnPrompt;
  var prompts = 0;
  var settingsOpened = 0;

  @override
  Future<NotificationStatus> status() async => NotificationStatus(
    sdk: sdk,
    // On 13+ the app switch follows the permission.
    enabled: enabled && (sdk < 33 || permission),
    permissionGranted: sdk < 33 || permission,
    appOpAllowed: appOpAllowed,
  );

  @override
  Future<void> requestPermission() async {
    prompts++;
    if (grantOnPrompt) permission = true;
  }

  @override
  Future<void> openNotificationSettings() async => settingsOpened++;
}

void main() {
  group('API 31 (Note 10: no runtime permission)', () {
    test('enabled: allowed, nothing asked', () async {
      final p = FakeNotificationPlatform(sdk: 31);
      final a = NotificationAccess(p);
      expect(await a.allowed(), isTrue);
      expect(await a.request(), isTrue);
      expect(p.prompts, 0);
    });

    test('blocked by the app switch: blocked; no prompt exists', () async {
      final p = FakeNotificationPlatform(sdk: 31, enabled: false);
      final a = NotificationAccess(p);
      expect(await a.allowed(), isFalse);
      expect(await a.request(), isFalse);
      expect(p.prompts, 0);
    });

    test('blocked by the app-op alone: blocked (S8C Note 10)', () async {
      final p = FakeNotificationPlatform(sdk: 31, appOpAllowed: false);
      final a = NotificationAccess(p);
      expect(await a.allowed(), isFalse);
      expect(await a.request(), isFalse);
      expect(p.prompts, 0);
    });

    test(
      'turned on in the phone settings: allowed on the next check',
      () async {
        final p = FakeNotificationPlatform(sdk: 31, enabled: false);
        final a = NotificationAccess(p);
        expect(await a.allowed(), isFalse);
        await a.openSettings();
        expect(p.settingsOpened, 1);
        p.enabled = true;
        expect(await a.allowed(), isTrue);
      },
    );
  });

  group('API 33+ (runtime permission)', () {
    test('granted: allowed, nothing asked', () async {
      final p = FakeNotificationPlatform(sdk: 33, permission: true);
      final a = NotificationAccess(p);
      expect(await a.allowed(), isTrue);
      expect(await a.request(), isTrue);
      expect(p.prompts, 0);
    });

    test('denied, then granted in the prompt: allowed', () async {
      final p = FakeNotificationPlatform(sdk: 34, grantOnPrompt: true);
      final a = NotificationAccess(p);
      expect(await a.allowed(), isFalse);
      expect(await a.request(), isTrue);
      expect(p.prompts, 1);
    });

    test('denied in the prompt: still blocked', () async {
      final p = FakeNotificationPlatform(sdk: 37);
      final a = NotificationAccess(p);
      expect(await a.request(), isFalse);
      expect(p.prompts, 1);
    });

    test('granted but the app switch is off: blocked; the prompt cannot '
        'help', () async {
      final p = FakeNotificationPlatform(
        sdk: 33,
        permission: true,
        enabled: false,
      );
      final a = NotificationAccess(p);
      expect(await a.allowed(), isFalse);
      expect(await a.request(), isFalse);
      expect(p.prompts, 0);
    });
  });
}
