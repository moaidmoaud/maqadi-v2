import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/main.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/notification_models.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/notification_scheduler.dart';

void main() {
  testWidgets('settings configure reminder and notification types', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scheduler = _FakeNotificationScheduler();
    final store = AppStore(notificationScheduler: scheduler);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SettingsScreen(store: store),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('notification-settings-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notification-daily-time')),
      findsOneWidget,
    );
    expect(find.text('قبل 30 يومًا'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('notification-toggle-low-stock')),
    );
    await tester.pumpAndSettle();
    expect(store.notificationSettings.lowStockEnabled, isFalse);
    expect(scheduler.permissionRequests, 1);

    await tester.tap(find.byKey(const ValueKey('notification-expiry-days')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قبل 14 يومًا').last);
    await tester.pumpAndSettle();
    expect(store.notificationSettings.expiryReminderDays, 14);
    expect(scheduler.schedules, isNotEmpty);
    store.dispose();
  });

  testWidgets('dashboard shows the pending notification summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final inventory = InventoryService(
      clock: () => DateTime(2026, 7, 19, 7),
      items: [
        PantryItem(
          id: 'low',
          name: 'أرز',
          category: 'الحبوب',
          minimum: 1,
          unit: 'كجم',
          location: 'المخزن',
          batches: [
            InventoryBatch(
              id: 'rice-batch',
              quantity: 1,
              receivedAt: DateTime(2026, 7, 1),
            ),
          ],
        ),
      ],
    );
    final store = AppStore(
      inventoryService: inventory,
      notificationScheduler: _FakeNotificationScheduler(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(store: store, onToggleTheme: () {}),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('dashboard-notification-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('1 إشعار معلق'), findsOneWidget);
    expect(find.textContaining('منخفض 1'), findsOneWidget);
    store.dispose();
  });
}

class _FakeNotificationScheduler implements NotificationScheduler {
  final schedules = <List<SmartInventoryNotification>>[];
  int permissionRequests = 0;

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> synchronize(
    List<SmartInventoryNotification> notifications,
  ) async {
    schedules.add(List.of(notifications));
  }
}
