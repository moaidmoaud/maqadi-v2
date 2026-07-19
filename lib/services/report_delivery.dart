import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/report_models.dart';

abstract interface class ReportDelivery {
  Future<void> share(GeneratedReportFile file);

  Future<void> printPdf(GeneratedReportFile file);
}

class PlatformReportDelivery implements ReportDelivery {
  const PlatformReportDelivery();

  @override
  Future<void> share(GeneratedReportFile file) async {
    await SharePlus.instance.share(
      ShareParams(
        title: 'مقاضي',
        text: 'ملف مُنشأ من تطبيق مقاضي',
        files: [
          XFile.fromData(
            file.bytes,
            mimeType: file.mimeType,
          ),
        ],
        fileNameOverrides: [file.fileName],
      ),
    );
  }

  @override
  Future<void> printPdf(GeneratedReportFile file) async {
    if (!file.isPdf) {
      throw ArgumentError.value(file.mimeType, 'file', 'الطباعة تدعم PDF فقط');
    }
    await Printing.layoutPdf(
      name: file.fileName,
      onLayout: (_) async => file.bytes,
    );
  }
}
