class GroceryItem {
  GroceryItem({
    required this.id,
    required this.name,
    required this.category,
    this.done = false,
    this.quantity = 1,
    this.pantryItemId,
  });

  final String id;
  String name;
  String category;
  bool done;
  int quantity;
  final String? pantryItemId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'done': done,
        'quantity': quantity,
        if (pantryItemId != null) 'pantryItemId': pantryItemId,
      };

  factory GroceryItem.fromJson(Map<String, dynamic> json) => GroceryItem(
        id: json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'أخرى',
        done: json['done'] as bool? ?? false,
        quantity: json['quantity'] as int? ?? json['qty'] as int? ?? 1,
        pantryItemId: json['pantryItemId'] as String?,
      );
}

class ShoppingListModel {
  ShoppingListModel({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    List<GroceryItem>? items,
    this.archived = false,
  }) : items = items ?? [];

  final String id;
  String name;
  DateTime createdAt;
  DateTime updatedAt;
  List<GroceryItem> items;
  bool archived;

  int get completedCount => items.where((item) => item.done).length;
  int get remainingCount => items.length - completedCount;
  double get progress => items.isEmpty ? 0 : completedCount / items.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'archived': archived,
      };

  factory ShoppingListModel.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ShoppingListModel(
      id: json['id'] as String? ?? now.microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'قائمة جديدة',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => GroceryItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      archived: json['archived'] as bool? ?? false,
    );
  }
}
