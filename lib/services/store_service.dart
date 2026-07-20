import '../models/purchase_models.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/store_repository.dart';
import '../utils/arabic_text.dart';

typedef StoreClock = DateTime Function();

enum StoreStatusFilter { active, archived, all }

class StoreService {
  StoreService({
    required StoreRepository repository,
    required PurchaseRepository purchaseRepository,
    StoreClock? clock,
  })  : _repository = repository,
        _purchaseRepository = purchaseRepository,
        _clock = clock ?? DateTime.now;

  final StoreRepository _repository;
  final PurchaseRepository _purchaseRepository;
  final StoreClock _clock;
  int _idCounter = 0;

  Future<void> initialize() async {
    final stores = await _repository.readStores();
    final knownIds = stores.map((store) => store.id).toSet();
    final purchases = await _purchaseRepository.readPurchaseHistory();
    final firstPurchaseByStore = <String, Purchase>{};
    for (final purchase in purchases) {
      final storeId = purchase.storeId.trim();
      if (storeId.isEmpty || knownIds.contains(storeId)) continue;
      final previous = firstPurchaseByStore[storeId];
      if (previous == null || purchase.createdAt.isBefore(previous.createdAt)) {
        firstPurchaseByStore[storeId] = purchase;
      }
    }
    for (final entry in firstPurchaseByStore.entries) {
      final timestamp = entry.value.createdAt;
      await _repository.createStore(
        Store(
          id: entry.key,
          name: entry.key,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
    }
  }

  Future<Store> createStore({
    required String name,
    String? branch,
    String? notes,
  }) async {
    final cleanName = _requiredName(name);
    await _ensureUniqueActiveName(cleanName);
    final now = _clock();
    return _repository.createStore(
      Store(
        id: _newId(),
        name: cleanName,
        branch: _clean(branch),
        notes: _clean(notes),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<Store> updateStore({
    required String storeId,
    required String name,
    String? branch,
    String? notes,
  }) async {
    final existing = await _requiredStore(storeId);
    final cleanName = _requiredName(name);
    if (existing.isActive) {
      await _ensureUniqueActiveName(cleanName, excludingId: existing.id);
    }
    return _repository.updateStore(
      existing.copyWith(
        name: cleanName,
        branch: _clean(branch),
        clearBranch: _clean(branch) == null,
        notes: _clean(notes),
        clearNotes: _clean(notes) == null,
        updatedAt: _clock(),
      ),
    );
  }

  Future<Store> setArchived(String storeId, {required bool archived}) async {
    final existing = await _requiredStore(storeId);
    if (!archived) {
      await _ensureUniqueActiveName(existing.name, excludingId: existing.id);
    }
    if (existing.isActive == !archived) return existing;
    return _repository.updateStore(
      existing.copyWith(isActive: !archived, updatedAt: _clock()),
    );
  }

  Future<void> deleteStore(String storeId) async {
    await _requiredStore(storeId);
    if ((await _purchaseRepository.readPurchasesByStore(storeId)).isNotEmpty) {
      throw const StoreDeletionException(
        'لا يمكن حذف المتجر لوجود مشتريات مرتبطة به. يمكنك أرشفته بدلًا من ذلك.',
      );
    }
    await _repository.deleteStore(storeId);
  }

  Future<Store?> readStore(String storeId) => _repository.readStore(storeId);

  Future<List<Store>> activeStores() => _repository.readActiveStores();

  Future<List<Store>> archivedStores() => _repository.readArchivedStores();

  Future<List<Store>> searchStores({
    String query = '',
    StoreStatusFilter filter = StoreStatusFilter.active,
  }) async {
    final stores = switch (filter) {
      StoreStatusFilter.active => await _repository.readActiveStores(),
      StoreStatusFilter.archived => await _repository.readArchivedStores(),
      StoreStatusFilter.all => await _repository.readStores(),
    };
    final normalizedQuery = _normalizedName(query);
    if (normalizedQuery.isEmpty) return stores;
    return List.unmodifiable(
      stores.where(
        (store) => _normalizedName(store.name).contains(normalizedQuery),
      ),
    );
  }

  Future<Store> storeForNewPurchase(String storeSelection) async {
    final store = await _resolveStore(storeSelection);
    if (store == null) {
      throw const StoreValidationException('اختر متجرًا صالحًا.');
    }
    if (!store.isActive) {
      throw const StoreValidationException(
        'لا يمكن اختيار متجر مؤرشف لعملية شراء جديدة.',
      );
    }
    return store;
  }

  Future<Store> storeForPurchaseEdit(
    String storeSelection, {
    required String previousStoreId,
  }) async {
    final store = await _resolveStore(storeSelection);
    if (store == null) {
      throw const StoreValidationException('اختر متجرًا صالحًا.');
    }
    if (!store.isActive && store.id != previousStoreId) {
      throw const StoreValidationException(
        'لا يمكن نقل عملية الشراء إلى متجر مؤرشف.',
      );
    }
    return store;
  }

  Future<String> displayName(String storeId) async =>
      (await _repository.readStore(storeId))?.name ?? storeId;

  Future<Store?> _resolveStore(String selection) async {
    final clean = selection.trim();
    if (clean.isEmpty) return null;
    final byId = await _repository.readStore(clean);
    if (byId != null) return byId;
    final normalized = _normalizedName(clean);
    for (final store in await _repository.readStores()) {
      if (_normalizedName(store.name) == normalized) return store;
    }
    return null;
  }

  Future<Store> _requiredStore(String storeId) async {
    final store = await _repository.readStore(storeId);
    if (store == null) {
      throw StoreValidationException('المتجر غير موجود: $storeId');
    }
    return store;
  }

  Future<void> _ensureUniqueActiveName(
    String name, {
    String? excludingId,
  }) async {
    final normalized = _normalizedName(name);
    final duplicate = (await _repository.readActiveStores()).any(
      (store) =>
          store.id != excludingId && _normalizedName(store.name) == normalized,
    );
    if (duplicate) {
      throw const StoreValidationException(
        'يوجد متجر نشط آخر بالاسم نفسه.',
      );
    }
  }

  String _requiredName(String value) {
    final clean = value.trim();
    if (clean.isEmpty) {
      throw const StoreValidationException('اسم المتجر مطلوب.');
    }
    return clean;
  }

  String _normalizedName(String value) =>
      normalizeArabic(value.trim()).toLowerCase();

  String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  String _newId() {
    _idCounter++;
    return 'store-${_clock().microsecondsSinceEpoch}-$_idCounter';
  }
}

class StoreValidationException implements Exception {
  const StoreValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StoreDeletionException implements Exception {
  const StoreDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}
