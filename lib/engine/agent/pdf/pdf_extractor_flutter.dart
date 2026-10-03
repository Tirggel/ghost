// Ghost — PDF Text Extractor for Flutter environments with dart:ui.

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'pdf_extractor.dart';

GhostPdfExtractor createPdfExtractor() => FlutterPdfExtractor();

class FlutterPdfExtractor implements GhostPdfExtractor {
  @override
  Future<String> extractText(List<int> bytes) async {
    try {
      final document = sf.PdfDocument(inputBytes: bytes);
      final extractor = sf.PdfTextExtractor(document);
      final text = extractor.extractText();
      document.dispose();
      return text;
    } catch (_) {
      return '';
    }
  }
}
