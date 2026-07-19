import 'dart:convert';

import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/report_models.dart';
import 'package:maqadi_v2/models/shopping_models.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/report_service.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  group('ReportService', () {
    late InventoryService inventory;
    late ReportService reports;
    late PantryItem lowStock;
    late PantryItem expired;
    late List<GroceryItem> shopping;

    setUp(() {
      inventory = InventoryService(
        clock: () => DateTime.utc(2026, 7, 19, 14, 5),
      );
      lowStock = inventory.addStock(
        name: 'Rice',
        category: 'Grains',
        quantity: 0,
        minimum: 1,
        unit: 'kg',
        location: 'Pantry',
      );
      inventory.addBatch(
        lowStock,
        quantity: 1,
        batchId: 'rice-lot',
        expiresAt: DateTime.utc(2026, 7, 25),
      );
      expired = inventory.addStock(
        name: 'Milk',
        category: 'Dairy',
        quantity: 0,
        minimum: 1,
        unit: 'carton',
        location: 'Fridge',
      );
      inventory.addBatch(
        expired,
        quantity: 2,
        batchId: 'milk-lot',
        expiresAt: DateTime.utc(2026, 7, 18),
      );
      shopping = [
        GroceryItem(
          id: 'shopping-rice',
          name: 'Rice',
          category: 'Grains',
          pantryItemId: lowStock.id,
        ),
        GroceryItem(
          id: 'shopping-milk',
          name: 'Milk',
          category: 'Dairy',
          pantryItemId: expired.id,
        ),
      ];
      reports = ReportService(
        inventoryService: inventory,
        clock: () => DateTime.utc(2026, 7, 19, 14, 5),
        regularFontLoader: () async => pw.Font.helvetica(),
        boldFontLoader: () async => pw.Font.helveticaBold(),
        appName: 'Maqadi',
        appVersion: 'test',
      );
    });

    test('filters inventory CSV using InventoryService stock decisions', () {
      final file = reports.generateCsv(
        CsvReportType.inventory,
        filter: const ReportFilter(category: 'Grains', lowStock: true),
      );
      final csv = utf8.decode(file.bytes);

      expect(file.fileName, 'maqadi_inventory_20260719_1405.csv');
      expect(csv, contains('Rice'));
      expect(csv, isNot(contains('Milk')));
      expect(file.bytes.take(3), [0xef, 0xbb, 0xbf]);
    });

    test('creates all required Excel worksheets with exported data', () {
      final file = reports.generateExcel(shoppingItems: shopping);
      final workbook = Excel.decodeBytes(file.bytes);

      expect(
        workbook.tables.keys,
        containsAll([
          'Inventory',
          'Shopping List',
          'Batch Details',
          'Dashboard Summary',
        ]),
      );
      expect(file.mimeType, contains('spreadsheetml'));
      expect(file.bytes, isNotEmpty);
      expect(
        workbook.tables['Batch Details']!.rows
            .expand((row) => row)
            .map((cell) => cell?.value.toString())
            .whereType<String>(),
        contains('rice-lot'),
      );
    });

    test('generates valid PDF bytes for every report type', () async {
      for (final type in PdfReportType.values) {
        final file = await reports.generatePdf(
          type,
          shoppingItems: shopping,
        );
        expect(file.isPdf, isTrue, reason: type.name);
        expect(ascii.decode(file.bytes.take(4).toList()), '%PDF');
        expect(file.bytes.length, greaterThan(500), reason: type.name);
      }
    });

    test('category and expiry filters use an OR across selected statuses', () {
      final file = reports.generateCsv(
        CsvReportType.inventory,
        filter: const ReportFilter(expiringSoon: true, expired: true),
      );
      final csv = utf8.decode(file.bytes);

      expect(csv, contains('Rice'));
      expect(csv, contains('Milk'));
      expect(reports.categories, ['Dairy', 'Grains']);
    });
  });
}
