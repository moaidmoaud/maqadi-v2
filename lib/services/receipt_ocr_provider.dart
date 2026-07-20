import '../models/receipt_capture_models.dart';

abstract interface class ReceiptOcrProvider<TResult> {
  Future<TResult> recognize(ReceiptImage image);
}
