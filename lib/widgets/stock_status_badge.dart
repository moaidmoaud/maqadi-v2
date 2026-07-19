import 'package:flutter/material.dart';

import '../models/stock_models.dart';

class StockStatusBadge extends StatelessWidget {
  const StockStatusBadge({super.key, required this.info});

  static const normalBackground = Color(0xFFE8F5E9);
  static const normalForeground = Color(0xFF1B5E20);
  static const lowBackground = Color(0xFFFFF8E1);
  static const lowForeground = Color(0xFF8D6E00);
  static const outBackground = Color(0xFFFFEBEE);
  static const outForeground = Color(0xFFB71C1C);

  final StockInfo info;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon, label) = switch (info.status) {
      StockStatus.normalStock => (
          normalBackground,
          normalForeground,
          Icons.check_circle_outline,
          'مخزون طبيعي',
        ),
      StockStatus.lowStock => (
          lowBackground,
          lowForeground,
          Icons.warning_amber_rounded,
          'مخزون منخفض',
        ),
      StockStatus.outOfStock => (
          outBackground,
          outForeground,
          Icons.remove_shopping_cart_outlined,
          'نفد المخزون',
        ),
    };
    return Container(
      key: const ValueKey('stock-status-badge'),
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
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
