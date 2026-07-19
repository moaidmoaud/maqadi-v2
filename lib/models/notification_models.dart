enum SmartNotificationType { lowStock, outOfStock, expiringSoon, expired }

class NotificationSettings {
  const NotificationSettings({
    this.expiryReminderDays = 30,
    this.dailyHour = 9,
    this.dailyMinute = 0,
    this.lowStockEnabled = true,
    this.outOfStockEnabled = true,
    this.expiringSoonEnabled = true,
    this.expiredEnabled = true,
  });

  static const supportedExpiryReminderDays = [7, 14, 30];

  final int expiryReminderDays;
  final int dailyHour;
  final int dailyMinute;
  final bool lowStockEnabled;
  final bool outOfStockEnabled;
  final bool expiringSoonEnabled;
  final bool expiredEnabled;

  bool get anyEnabled =>
      lowStockEnabled ||
      outOfStockEnabled ||
      expiringSoonEnabled ||
      expiredEnabled;

  NotificationSettings copyWith({
    int? expiryReminderDays,
    int? dailyHour,
    int? dailyMinute,
    bool? lowStockEnabled,
    bool? outOfStockEnabled,
    bool? expiringSoonEnabled,
    bool? expiredEnabled,
  }) =>
      NotificationSettings(
        expiryReminderDays: expiryReminderDays ?? this.expiryReminderDays,
        dailyHour: dailyHour ?? this.dailyHour,
        dailyMinute: dailyMinute ?? this.dailyMinute,
        lowStockEnabled: lowStockEnabled ?? this.lowStockEnabled,
        outOfStockEnabled: outOfStockEnabled ?? this.outOfStockEnabled,
        expiringSoonEnabled: expiringSoonEnabled ?? this.expiringSoonEnabled,
        expiredEnabled: expiredEnabled ?? this.expiredEnabled,
      );

  Map<String, dynamic> toJson() => {
        'expiryReminderDays': expiryReminderDays,
        'dailyHour': dailyHour,
        'dailyMinute': dailyMinute,
        'lowStockEnabled': lowStockEnabled,
        'outOfStockEnabled': outOfStockEnabled,
        'expiringSoonEnabled': expiringSoonEnabled,
        'expiredEnabled': expiredEnabled,
      };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    final reminder = (json['expiryReminderDays'] as num?)?.toInt() ?? 30;
    return NotificationSettings(
      expiryReminderDays:
          supportedExpiryReminderDays.contains(reminder) ? reminder : 30,
      dailyHour: ((json['dailyHour'] as num?)?.toInt() ?? 9).clamp(0, 23),
      dailyMinute: ((json['dailyMinute'] as num?)?.toInt() ?? 0).clamp(0, 59),
      lowStockEnabled: json['lowStockEnabled'] as bool? ?? true,
      outOfStockEnabled: json['outOfStockEnabled'] as bool? ?? true,
      expiringSoonEnabled: json['expiringSoonEnabled'] as bool? ?? true,
      expiredEnabled: json['expiredEnabled'] as bool? ?? true,
    );
  }
}

class SmartInventoryNotification {
  const SmartInventoryNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    required this.scheduledAt,
    required this.itemId,
    this.batchId,
  });

  final int id;
  final SmartNotificationType type;
  final String title;
  final String body;
  final String payload;
  final DateTime scheduledAt;
  final String itemId;
  final String? batchId;
}

class NotificationSummary {
  const NotificationSummary({
    required this.pendingCount,
    required this.lowStock,
    required this.outOfStock,
    required this.expiringSoon,
    required this.expired,
  });

  const NotificationSummary.empty()
      : pendingCount = 0,
        lowStock = 0,
        outOfStock = 0,
        expiringSoon = 0,
        expired = 0;

  final int pendingCount;
  final int lowStock;
  final int outOfStock;
  final int expiringSoon;
  final int expired;
}
