import 'package:flutter/material.dart';

import '../app_store.dart';
import '../models/notification_models.dart';

class NotificationSettingsCard extends StatelessWidget {
  const NotificationSettingsCard({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final settings = store.notificationSettings;
    final time = TimeOfDay(
      hour: settings.dailyHour,
      minute: settings.dailyMinute,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'الإشعارات الذكية',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Card(
          key: const ValueKey('notification-settings-card'),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('notification-expiry-days'),
                  initialValue: settings.expiryReminderDays,
                  decoration: const InputDecoration(
                    labelText: 'تذكير الصلاحية',
                    prefixIcon: Icon(Icons.event_note_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final days
                        in NotificationSettings.supportedExpiryReminderDays)
                      DropdownMenuItem(
                        value: days,
                        child: Text('قبل $days يومًا'),
                      ),
                  ],
                  onChanged: (days) {
                    if (days == null) return;
                    store.setNotificationSettings(
                      settings.copyWith(expiryReminderDays: days),
                    );
                  },
                ),
              ),
              ListTile(
                key: const ValueKey('notification-daily-time'),
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('وقت الإشعار اليومي'),
                subtitle: Text(time.format(context)),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _pickDailyTime(context, settings, time),
              ),
              const Divider(height: 1),
              _NotificationSwitch(
                key: const ValueKey('notification-toggle-low-stock'),
                title: 'مخزون منخفض',
                subtitle: 'تنبيه عند وصول المنتج إلى الحد الأدنى',
                value: settings.lowStockEnabled,
                onChanged: (value) => store.setNotificationSettings(
                  settings.copyWith(lowStockEnabled: value),
                ),
              ),
              _NotificationSwitch(
                key: const ValueKey('notification-toggle-out-of-stock'),
                title: 'نفاد المخزون',
                subtitle: 'تنبيه عند وصول الكمية إلى صفر',
                value: settings.outOfStockEnabled,
                onChanged: (value) => store.setNotificationSettings(
                  settings.copyWith(outOfStockEnabled: value),
                ),
              ),
              _NotificationSwitch(
                key: const ValueKey('notification-toggle-expiring-soon'),
                title: 'قريب الانتهاء',
                subtitle: 'حسب مدة تذكير الصلاحية المحددة',
                value: settings.expiringSoonEnabled,
                onChanged: (value) => store.setNotificationSettings(
                  settings.copyWith(expiringSoonEnabled: value),
                ),
              ),
              _NotificationSwitch(
                key: const ValueKey('notification-toggle-expired'),
                title: 'منتهي الصلاحية',
                subtitle: 'تنبيه للدفعات التي انتهت صلاحيتها',
                value: settings.expiredEnabled,
                onChanged: (value) => store.setNotificationSettings(
                  settings.copyWith(expiredEnabled: value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('notification-request-permission'),
                    onPressed: () => _requestPermission(context),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('السماح بالإشعارات على الجهاز'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDailyTime(
    BuildContext context,
    NotificationSettings settings,
    TimeOfDay initialTime,
  ) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (selected == null) return;
    await store.setNotificationSettings(
      settings.copyWith(
        dailyHour: selected.hour,
        dailyMinute: selected.minute,
      ),
    );
  }

  Future<void> _requestPermission(BuildContext context) async {
    final granted = await store.requestNotificationPermissions();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'تم السماح بالإشعارات'
              : 'تعذر تفعيل الإشعارات. تحقق من إعدادات الجهاز.',
        ),
      ),
    );
  }
}

class _NotificationSwitch extends StatelessWidget {
  const _NotificationSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      );
}
