import '../models/inventory_models.dart';
import '../models/shopping_models.dart';

class AppData {
  AppData({
    List<ShoppingListModel>? lists,
    Set<String>? favorites,
    Map<String, int>? frequency,
    List<PantryItem>? pantry,
    List<PantryMovement>? pantryMovements,
    this.lastListId,
    this.themeMode = 'system',
    this.fontScale = 1,
  }) : lists = lists ?? [],
       favorites = favorites ?? {},
       frequency = frequency ?? {},
       pantry = pantry ?? [],
       pantryMovements = pantryMovements ?? [];

  final List<ShoppingListModel> lists;
  final Set<String> favorites;
  final Map<String, int> frequency;
  final List<PantryItem> pantry;
  final List<PantryMovement> pantryMovements;
  final String? lastListId;
  final String themeMode;
  final double fontScale;
}

abstract interface class AppRepository {
  Future<AppData> load();

  Future<void> save(AppData data);
}
