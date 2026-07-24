import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/inventory_update/application/inventory_update_service.dart';
import 'package:maqadi_v2/inventory_update/presentation/inventory_update_debug_screen.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

import 'inventory_update_test_support.dart';

void main() {
  testWidgets('renders inventory quantities, actions, reasons, and summary',
      (tester) async {
    final inventory = InventoryService(items: [
      PantryItem(
        id: 'inventory-garlic',
        name: 'ثوم',
        category: 'الخضار',
        minimum: 1,
        unit: 'حبة',
        location: 'المخزن',
        quantity: 3,
      ),
    ]);
    final input = updateInput([
      receiptProduct(
        finalMatch(
          lineId: 'line-garlic',
          productId: 'catalog-garlic',
          displayName: 'ثوم',
        ),
        quantity: 2,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: InventoryUpdateDebugScreen(
        service: InventoryUpdateService(inventoryService: inventory),
        input: input,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inventory-update-debug-results')),
      findsOneWidget,
    );
    expect(find.text('Products Added: 0'), findsOneWidget);
    expect(find.text('Products Updated: 1'), findsOneWidget);
    expect(find.text('ثوم'), findsOneWidget);
    expect(find.text('Previous Quantity: 3'), findsOneWidget);
    expect(find.text('Receipt Quantity: 2'), findsOneWidget);
    expect(find.text('New Quantity: 5'), findsOneWidget);
    expect(find.text('Action: Increase Quantity'), findsOneWidget);
    expect(
      find.text('Update Reason: matchedExistingProduct'),
      findsOneWidget,
    );
    expect(inventory.items.single.quantity, 3);
  });
}
