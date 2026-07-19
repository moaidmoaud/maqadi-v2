import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/notification_models.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/notification_scheduler.dart';

void main() {
  group('smart notification decisions', () {
    late InventoryService service;

    setUp(() {
      service = InventoryService(
        clock: () => DateTime(2026, 7, 19, 12),
        items: [
          _item('low', 'أرز', quantity: 1, minimum: 1),
          _item('out', 'حليب', quantity: 0, minimum: 1),
          _item(
            'soon',
            'زبادي',
            quantity: 2,
            minimum: 1,
            expiresAt: DateTime(2026, 7, 26),
          ),
          _item(
            'expired',
            'جبن',
            quantity: 2,
            minimum: 1,
            expiresAt: DateTime(2026, 7, 18),
          ),
        ],
      );
    });

    test('returns enabled low, out, expiring, and expired notifications', () {
      const settings = NotificationSettings(expiryReminderDays: 7);

      final pending = service.pendingNotifications(settings);
      final summary = service.notificationSummary(settings);

      expect(pending, hasLength(4));
      expect(
        pending.map((notification) => notification.type),
        containsAll(SmartNotificationType.values),
      );
      expect(
        pending.map((notification) => notification.scheduledAt).toSet(),
        {DateTime(2026, 7, 20, 9)},
      );
      expect(summary.pendingCount, 4);
      expect(summary.lowStock, 1);
      expect(summary.outOfStock, 1);
      expect(summary.expiringSoon, 1);
      expect(summary.expired, 1);
    });

    test('respects type switches and configurable expiry reminder', () {
      const settings = NotificationSettings(
        expiryReminderDays: 7,
        lowStockEnabled: false,
        outOfStockEnabled: false,
        expiringSoonEnabled: false,
      );

      final pending = service.pendingNotifications(settings);

      expect(pending, hasLength(1));
      expect(pending.single.type, SmartNotificationType.expired);
    });

    test('schedules future expiry transitions at the configured time', () {
      final futureService = InventoryService(
        clock: () => DateTime(2026, 7, 19, 7),
        items: [
          _item(
            'future',
            'قهوة',
            quantity: 2,
            minimum: 1,
            expiresAt: DateTime(2026, 8, 18),
          ),
        ],
      );
      const settings = NotificationSettings(
        expiryReminderDays: 14,
        dailyHour: 8,
        dailyMinute: 30,
        lowStockEnabled: false,
        outOfStockEnabled: false,
      );

      final schedule = futureService.notificationSchedule(settings);

      expect(schedule, hasLength(2));
      expect(
        schedule.first.type,
        SmartNotificationType.expiringSoon,
      );
      expect(schedule.first.scheduledAt, DateTime(2026, 8, 4, 8, 30));
      expect(schedule.last.type, SmartNotificationType.expired);
      expect(schedule.last.scheduledAt, DateTime(2026, 8, 19, 8, 30));
      expect(
          schedule.first.payload, 'maqadi://product/future/batch/batch-future');
      expect(schedule.first.id, isNot(schedule.last.id));
    });
  });

  test('settings safely decode missing and invalid legacy values', () {
    final settings = NotificationSettings.fromJson({
      'expiryReminderDays': 5,
      'dailyHour': 99,
      'dailyMinute': -8,
      'lowStockEnabled': false,
    });

    expect(settings.expiryReminderDays, 30);
    expect(settings.dailyHour, 23);
    expect(settings.dailyMinute, 0);
    expect(settings.lowStockEnabled, isFalse);
    expect(settings.outOfStockEnabled, isTrue);
  });

  test('AppStore sends only InventoryService plans to the scheduler', () async {
    final scheduler = _FakeNotificationScheduler();
    final service = InventoryService(
      clock: () => DateTime(2026, 7, 19, 7),
      items: [_item('low', 'أرز', quantity: 1, minimum: 1)],
    );
    final store = AppStore(
      inventoryService: service,
      notificationScheduler: scheduler,
    );

    final granted = await store.setNotificationSettings(
      const NotificationSettings(
        expiryReminderDays: 14,
        dailyHour: 10,
        lowStockEnabled: true,
        outOfStockEnabled: false,
        expiringSoonEnabled: false,
        expiredEnabled: false,
      ),
    );

    expect(granted, isTrue);
    expect(scheduler.permissionRequests, 1);
    expect(scheduler.schedules, hasLength(1));
    expect(scheduler.schedules.single.single.itemId, 'low');
    expect(
      scheduler.schedules.single.single.type,
      SmartNotificationType.lowStock,
    );
    store.dispose();
  });
}

PantryItem _item(
  String id,
  String name, {
  required double quantity,
  required double minimum,
  DateTime? expiresAt,
}) =>
    PantryItem(
      id: id,
      name: name,
      category: 'اختبار',
      minimum: minimum,
      unit: 'حبة',
      location: 'المخزن',
      batches: quantity <= 0
          ? []
          : [
              InventoryBatch(
                id: 'batch-$id',
                quantity: quantity,
                receivedAt: DateTime(2026, 7, 1),
                expiresAt: expiresAt,
              ),
            ],
    );

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
