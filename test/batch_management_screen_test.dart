import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/screens/batch_management_screen.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

void main() {
  testWidgets('shows totals and batches in FIFO purchase order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final inventory = InventoryService();
    final item = inventory.addStock(
      name: 'أرز',
      category: 'الحبوب',
      quantity: 0,
      minimum: 1,
      unit: 'كجم',
      location: 'المخزن',
    );
    inventory.addBatch(
      item,
      quantity: 3,
      receivedAt: DateTime.utc(2026, 2, 1),
      batchId: 'february',
    );
    inventory.addBatch(
      item,
      quantity: 2,
      receivedAt: DateTime.utc(2026, 1, 1),
      batchId: 'january',
    );
    final store = AppStore(inventoryService: inventory);

    await tester.pumpWidget(
      MaterialApp(
        home: BatchManagementScreen(store: store, item: item),
      ),
    );

    expect(find.text('دفعات أرز'), findsOneWidget);
    expect(find.text('5 كجم'), findsOneWidget);
    expect(
      find.text('ترتيب FIFO: تُستهلك الدفعات الأقدم شراءً أولاً.'),
      findsOneWidget,
    );

    final january = find.text('معرّف الدفعة: january');
    final february = find.text('معرّف الدفعة: february');
    expect(january, findsOneWidget);
    expect(february, findsOneWidget);
    expect(
      tester.getTopLeft(january).dy,
      lessThan(tester.getTopLeft(february).dy),
    );
  });
}
