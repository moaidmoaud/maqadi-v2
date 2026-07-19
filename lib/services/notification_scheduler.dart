import '../models/notification_models.dart';

abstract interface class NotificationScheduler {
  Future<void> synchronize(
    List<SmartInventoryNotification> notifications,
  );

  Future<bool> requestPermissions();
}
