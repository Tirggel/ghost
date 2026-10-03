// Ghost — PDF Text Extractor Stub for headless Dart CLI environments without dart:ui.

import 'pdf_extractor.dart';

GhostPdfExtractor createPdfExtractor() => StubPdfExtractor();

class StubPdfExtractor implements GhostPdfExtractor {
  @override
  Future<String> extractText(List<int> bytes) async {
    // In headless CLI environment without Flutter/dart:ui,
    // PDF extraction can be gracefully skipped or fall back to basic text parsing.
    return '';
  }
}
