import 'application/product_matching_service.dart';
import 'engine/matching_engine.dart';
import 'infrastructure/catalog_product_matching_repository.dart';

ProductMatchingService createProductMatchingService() => ProductMatchingService(
      engine: MatchingEngine(
        repository: const CatalogProductMatchingRepository(),
      ),
    );
