import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/notification_models.dart';
import 'package:maqadi_v2/repositories/app_repository.dart';
import 'package:maqadi_v2/repositories/shared_preferences_app_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy saved data receives safe notification defaults', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesAppRepository.pantryKey: jsonEncode([]),
    });

    final data = await SharedPreferencesAppRepository().load();

    expect(data.notificationSettings.expiryReminderDays, 30);
    expect(data.notificationSettings.dailyHour, 9);
    expect(data.notificationSettings.anyEnabled, isTrue);
  });

  test('notification settings round-trip through their additive key', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesAppRepository();
    const settings = NotificationSettings(
      expiryReminderDays: 14,
      dailyHour: 18,
      dailyMinute: 45,
      lowStockEnabled: false,
      expiredEnabled: false,
    );

    await repository.save(AppData(notificationSettings: settings));
    final loaded = await repository.load();

    expect(loaded.notificationSettings.expiryReminderDays, 14);
    expect(loaded.notificationSettings.dailyHour, 18);
    expect(loaded.notificationSettings.dailyMinute, 45);
    expect(loaded.notificationSettings.lowStockEnabled, isFalse);
    expect(loaded.notificationSettings.outOfStockEnabled, isTrue);
    expect(loaded.notificationSettings.expiredEnabled, isFalse);
  });
}
