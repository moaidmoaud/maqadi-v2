import '../models/purchase_models.dart';

abstract interface class StoreRepository {
  Future<Store> createStore(Store store);

  Future<Store> updateStore(Store store);

  Future<void> deleteStore(String storeId);

  Future<Store?> readStore(String storeId);

  Future<List<Store>> readStores();

  Future<List<Store>> readActiveStores();

  Future<List<Store>> readArchivedStores();
}
