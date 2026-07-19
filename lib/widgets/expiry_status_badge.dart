import 'package:flutter/material.dart';

import '../models/expiry_models.dart';

class ExpiryStatusBadge extends StatelessWidget {
  const ExpiryStatusBadge({super.key, required this.info});

  static const freshBackground = Color(0xFFE8F5E9);
  static const freshForeground = Color(0xFF1B5E20);
  static const expiringSoonBackground = Color(0xFFFFF8E1);
  static const expiringSoonForeground = Color(0xFF8D6E00);
  static const expiredBackground = Color(0xFFFFEBEE);
  static const expiredForeground = Color(0xFFB71C1C);

  final BatchExpiryInfo info;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon, text) = switch (info.status) {
      BatchExpiryStatus.fresh => (
        freshBackground,
        freshForeground,
        Icons.check_circle_outline,
        _freshText(info.daysRemaining),
      ),
      BatchExpiryStatus.expiringSoon => (
        expiringSoonBackground,
        expiringSoonForeground,
        Icons.schedule,
        _expiringSoonText(info.daysRemaining!),
      ),
      BatchExpiryStatus.expired => (
        expiredBackground,
        expiredForeground,
        Icons.error_outline,
        _expiredText(info.daysRemaining!),
      ),
    };

    return Container(
      key: const ValueKey('expiry-status-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _freshText(int? daysRemaining) =>
      daysRemaining == null ? 'طازج' : 'طازج • متبقي $daysRemaining يوم';

  static String _expiringSoonText(int daysRemaining) => daysRemaining == 0
      ? 'قريب الانتهاء • ينتهي اليوم'
      : 'قريب الانتهاء • متبقي $daysRemaining يوم';

  static String _expiredText(int daysRemaining) =>
      'منتهي • منذ ${daysRemaining.abs()} يوم';
}
