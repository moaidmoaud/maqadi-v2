import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/shopping_models.dart';
import 'package:maqadi_v2/repositories/app_repository.dart';

void main() {
  test('load migrates low stock into the active shopping list', () async {
    final list = ShoppingListModel(
      id: 'list-1',
      name: 'قائمتي',
      createdAt: DateTime.utc(2026, 7, 19),
      updatedAt: DateTime.utc(2026, 7, 19),
    );
    final pantryItem = PantryItem(
      id: 'pantry-1',
      name: 'حليب',
      category: 'الألبان',
      minimum: 1,
      unit: 'علبة',
      location: 'الثلاجة',
    );
    final repository = _MemoryRepository(
      AppData(lists: [list], pantry: [pantryItem], lastListId: list.id),
    );
    final store = AppStore(repository: repository);

    await store.load();

    expect(list.items, hasLength(1));
    expect(list.items.single.pantryItemId, pantryItem.id);
    expect(repository.saveCount, 1);

    list.items.single.done = true;
    store.clearCompleted(list);
    expect(list.items, hasLength(1));
    expect(list.items.single.done, isFalse);

    store.changePantryQuantity(pantryItem, 2);

    expect(pantryItem.quantity, 2);
    expect(list.items, isEmpty);
    store.dispose();
  });

  test(
    'changing the active list moves only automatic shopping items',
    () async {
      final first = ShoppingListModel(
        id: 'list-1',
        name: 'الأولى',
        createdAt: DateTime.utc(2026, 7, 19),
        updatedAt: DateTime.utc(2026, 7, 19),
      );
      final second = ShoppingListModel(
        id: 'list-2',
        name: 'الثانية',
        createdAt: DateTime.utc(2026, 7, 18),
        updatedAt: DateTime.utc(2026, 7, 18),
        items: [GroceryItem(id: 'manual', name: 'خبز', category: 'المخبوزات')],
      );
      final pantryItem = PantryItem(
        id: 'pantry-1',
        name: 'حليب',
        category: 'الألبان',
        minimum: 1,
        unit: 'علبة',
        location: 'الثلاجة',
      );
      final store = AppStore(
        repository: _MemoryRepository(
          AppData(
            lists: [first, second],
            pantry: [pantryItem],
            lastListId: first.id,
          ),
        ),
      );
      await store.load();

      store.openList(second);

      expect(first.items, isEmpty);
      expect(
        second.items.where((item) => item.pantryItemId != null),
        hasLength(1),
      );
      expect(
        second.items.where((item) => item.pantryItemId == null).single.name,
        'خبز',
      );
      store.dispose();
    },
  );

  test('duplicated lists keep automatic items managed by inventory', () async {
    final list = ShoppingListModel(
      id: 'list-1',
      name: 'الأصل',
      createdAt: DateTime.utc(2026, 7, 19),
      updatedAt: DateTime.utc(2026, 7, 19),
    );
    final pantryItem = PantryItem(
      id: 'pantry-1',
      name: 'حليب',
      category: 'الألبان',
      minimum: 1,
      unit: 'علبة',
      location: 'الثلاجة',
    );
    final store = AppStore(
      repository: _MemoryRepository(
        AppData(lists: [list], pantry: [pantryItem], lastListId: list.id),
      ),
    );
    await store.load();

    final copy = store.duplicateList(list);

    expect(list.items, isEmpty);
    expect(copy.items.single.pantryItemId, pantryItem.id);
    store.changePantryQuantity(pantryItem, 2);
    expect(copy.items, isEmpty);
    store.dispose();
  });
}

class _MemoryRepository implements AppRepository {
  _MemoryRepository(this.data);

  final AppData data;
  int saveCount = 0;

  @override
  Future<AppData> load() async => data;

  @override
  Future<void> save(AppData data) async {
    saveCount++;
  }
}
