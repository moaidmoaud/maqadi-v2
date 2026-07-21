import '../../models/purchase_models.dart';
import '../domain/purchase_creation_command.dart';

abstract interface class PurchaseCreationGateway {
  List<PurchaseProductOption> purchaseCreationProducts();

  Future<List<Store>> purchaseCreationStores();

  Future<PurchaseCreationResult> createFromCommand(
    PurchaseCreationCommand command,
  );
}
