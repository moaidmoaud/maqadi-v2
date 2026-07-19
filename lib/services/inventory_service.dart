import 'dart:collection';

import '../models/inventory_models.dart';
import '../utils/arabic_text.dart';

typedef InventoryClock = DateTime Function();
typedef InventoryIdFactory = String Function();

class InventoryService {
  InventoryService({
    List<PantryItem>? items,
    List<PantryMovement>? movements,
    InventoryClock? clock,
    InventoryIdFactory? idFactory,
  }) : _items = items ?? [],
       _movements = movements ?? [],
       _clock = clock ?? DateTime.now,
       _idFactory = idFactory;

  final List<PantryItem> _items;
  final List<PantryMovement> _movements;
  final InventoryClock _clock;
  final InventoryIdFactory? _idFactory;
  int _idCounter = 0;

  UnmodifiableListView<PantryItem> get items => UnmodifiableListView(_items);

  UnmodifiableListView<PantryMovement> get movements =>
      UnmodifiableListView(_movements);

  void replaceState({
    required Iterable<PantryItem> items,
    required Iterable<PantryMovement> movements,
  }) {
    _items
      ..clear()
      ..addAll(items);
    _movements
      ..clear()
      ..addAll(movements);
  }

  List<PantryItem> get lowStockItems {
    final result = _items
        .where((item) => item.quantity <= item.minimum && item.quantity > 0)
        .toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<PantryItem> get emptyItems {
    final result = _items.where((item) => item.quantity <= 0).toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<PantryItem> get healthyItems {
    final result = _items
        .where((item) => item.quantity > item.minimum)
        .toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<PantryMovement> movementsFor(PantryItem item) {
    final result = _movements
        .where((movement) => movement.pantryItemId == item.id)
        .toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  List<InventoryBatch> batchesFor(PantryItem item) {
    _requireItem(item);
    final result = item.batches.where((batch) => batch.quantity > 0).toList()
      ..sort(_compareBatches);
    return List.unmodifiable(result);
  }

  PantryItem addStock({
    required String name,
    required String category,
    required double quantity,
    required double minimum,
    required String unit,
    required String location,
    String movementType = 'إضافة',
    String? note,
    DateTime? receivedAt,
    DateTime? expiresAt,
    bool updateExistingDetails = true,
  }) {
    final cleanQuantity = quantity.clamp(0, 999999).toDouble();
    final item =
        findByName(name) ??
        PantryItem(
          id: _newId(),
          name: name,
          category: category,
          minimum: minimum,
          unit: unit,
          location: location,
        );

    if (!_items.contains(item)) _items.add(item);
    if (updateExistingDetails) {
      item
        ..category = category
        ..minimum = minimum
        ..unit = unit
        ..location = location;
    }

    final allocations = <String, double>{};
    if (cleanQuantity > 0) {
      final batch = _appendBatch(
        item,
        cleanQuantity,
        receivedAt: receivedAt,
        expiresAt: expiresAt,
        note: note,
      );
      allocations[batch.id] = cleanQuantity;
    }
    _recordMovement(
      item,
      movementType,
      cleanQuantity,
      note: note,
      batchAllocations: allocations,
    );
    return item;
  }

  InventoryBatch addBatch(
    PantryItem item, {
    required double quantity,
    DateTime? receivedAt,
    DateTime? expiresAt,
    String? batchId,
    String? note,
    String movementType = 'إضافة',
  }) {
    final cleanQuantity = quantity.clamp(0, 999999).toDouble();
    if (cleanQuantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'يجب أن تكون الكمية أكبر من صفر',
      );
    }
    _requireItem(item);
    final batch = _appendBatch(
      item,
      cleanQuantity,
      id: _resolveBatchId(item, batchId),
      receivedAt: receivedAt,
      expiresAt: expiresAt,
      note: note,
    );
    _recordMovement(
      item,
      movementType,
      cleanQuantity,
      note: note,
      batchAllocations: {batch.id: cleanQuantity},
    );
    return batch;
  }

  void updateBatch(
    PantryItem item,
    InventoryBatch batch, {
    required double quantity,
    required DateTime receivedAt,
    DateTime? expiresAt,
    String? batchId,
    String? note,
  }) {
    _requireBatch(item, batch);
    final cleanQuantity = quantity.clamp(0, 999999).toDouble();
    if (cleanQuantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'يجب أن تكون الكمية أكبر من صفر',
      );
    }
    final previousQuantity = batch.quantity;
    final resolvedId = _resolveBatchId(item, batchId, currentBatch: batch);

    batch
      ..id = resolvedId
      ..quantity = cleanQuantity
      ..receivedAt = receivedAt
      ..expiresAt = expiresAt
      ..note = _cleanOptionalText(note);

    final delta = cleanQuantity - previousQuantity;
    if (delta != 0) {
      _recordMovement(
        item,
        'تعديل دفعة',
        delta,
        note: batch.note,
        batchAllocations: {resolvedId: delta},
      );
    }
  }

  void deleteBatch(PantryItem item, InventoryBatch batch) {
    _requireBatch(item, batch);
    final removedQuantity = batch.quantity;
    final batchId = batch.id;
    final note = batch.note;
    item.batches.remove(batch);
    if (removedQuantity > 0) {
      _recordMovement(
        item,
        'حذف دفعة',
        -removedQuantity,
        note: note,
        batchAllocations: {batchId: -removedQuantity},
      );
    }
  }

  double consume(
    PantryItem item,
    double quantity, {
    String movementType = 'استهلاك',
    String? note,
  }) {
    final requested = quantity.clamp(0, 999999).toDouble();
    final allocations = _consumeFifo(item, requested);
    final consumed = allocations.values.fold<double>(0, (sum, value) {
      return sum + value.abs();
    });
    if (consumed > 0) {
      _recordMovement(
        item,
        movementType,
        -consumed,
        note: note,
        batchAllocations: allocations,
      );
    }
    return consumed;
  }

  double changeQuantity(PantryItem item, double delta) {
    if (delta == 0) return 0;
    if (delta < 0) return -consume(item, -delta);

    final batch = _appendBatch(item, delta);
    _recordMovement(
      item,
      'إضافة',
      batch.quantity,
      batchAllocations: {batch.id: batch.quantity},
    );
    return batch.quantity;
  }

  void updateItem(
    PantryItem item, {
    required String name,
    required String category,
    required double quantity,
    required double minimum,
    required String unit,
    required String location,
  }) {
    item
      ..name = name
      ..category = category
      ..minimum = minimum.clamp(0, 999999).toDouble()
      ..unit = unit
      ..location = location;

    final targetQuantity = quantity.clamp(0, 999999).toDouble();
    final delta = targetQuantity - item.quantity;
    if (delta > 0) {
      final batch = _appendBatch(item, delta, note: 'تعديل الرصيد');
      _recordMovement(
        item,
        'تعديل',
        delta,
        batchAllocations: {batch.id: delta},
      );
    } else if (delta < 0) {
      final allocations = _consumeFifo(item, -delta);
      final actual = allocations.values.fold<double>(0, (sum, value) {
        return sum + value.abs();
      });
      if (actual > 0) {
        _recordMovement(item, 'تعديل', -actual, batchAllocations: allocations);
      }
    }
  }

  PantryItem? findByName(String name) {
    final normalized = normalizeArabic(name);
    for (final item in _items) {
      if (normalizeArabic(item.name) == normalized) return item;
    }
    return null;
  }

  void deleteItem(PantryItem item) {
    _items.remove(item);
    _movements.removeWhere((movement) => movement.pantryItemId == item.id);
  }

  InventoryBatch _appendBatch(
    PantryItem item,
    double quantity, {
    String? id,
    DateTime? receivedAt,
    DateTime? expiresAt,
    String? note,
  }) {
    final batch = InventoryBatch(
      id: id ?? _resolveBatchId(item, null),
      quantity: quantity.clamp(0, 999999).toDouble(),
      receivedAt: receivedAt ?? _clock(),
      expiresAt: expiresAt,
      note: _cleanOptionalText(note),
    );
    item.batches.add(batch);
    return batch;
  }

  Map<String, double> _consumeFifo(PantryItem item, double quantity) {
    var remaining = quantity;
    final allocations = <String, double>{};
    final ordered = item.batches.where((batch) => batch.quantity > 0).toList()
      ..sort(_compareBatches);

    for (final batch in ordered) {
      if (remaining <= 0) break;
      final consumed = remaining < batch.quantity ? remaining : batch.quantity;
      batch.quantity -= consumed;
      remaining -= consumed;
      allocations[batch.id] = -consumed;
    }
    item.batches.removeWhere((batch) => batch.quantity <= 0);
    return allocations;
  }

  int _compareBatches(InventoryBatch a, InventoryBatch b) {
    final byDate = a.receivedAt.compareTo(b.receivedAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }

  String _resolveBatchId(
    PantryItem item,
    String? requestedId, {
    InventoryBatch? currentBatch,
  }) {
    final requested = requestedId?.trim() ?? '';
    if (requested.isNotEmpty) {
      final duplicate = item.batches.any(
        (batch) => !identical(batch, currentBatch) && batch.id == requested,
      );
      if (duplicate) {
        throw ArgumentError.value(
          requestedId,
          'batchId',
          'معرّف الدفعة مستخدم لهذا المنتج',
        );
      }
      return requested;
    }

    String generated;
    do {
      generated = _newId();
    } while (item.batches.any((batch) => batch.id == generated));
    return generated;
  }

  void _requireItem(PantryItem item) {
    if (!_items.contains(item)) {
      throw ArgumentError.value(item, 'item', 'المنتج غير موجود في المخزون');
    }
  }

  void _requireBatch(PantryItem item, InventoryBatch batch) {
    _requireItem(item);
    if (!item.batches.contains(batch)) {
      throw ArgumentError.value(
        batch,
        'batch',
        'الدفعة غير مرتبطة بهذا المنتج',
      );
    }
  }

  String? _cleanOptionalText(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }

  void _recordMovement(
    PantryItem item,
    String type,
    double amount, {
    String? note,
    Map<String, double> batchAllocations = const {},
  }) {
    _movements.add(
      PantryMovement(
        id: _newId(),
        pantryItemId: item.id,
        productName: item.name,
        type: type,
        amount: amount,
        unit: item.unit,
        createdAt: _clock(),
        note: note,
        batchAllocations: batchAllocations,
      ),
    );
  }

  String _newId() {
    final idFactory = _idFactory;
    if (idFactory != null) return idFactory();
    _idCounter++;
    return '${_clock().microsecondsSinceEpoch}_$_idCounter';
  }
}
