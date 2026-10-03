// Ghost — Conditional PDF text extraction interface.

import 'pdf_extractor_stub.dart'
    if (dart.library.ui) 'pdf_extractor_flutter.dart';

abstract class GhostPdfExtractor {
  Future<String> extractText(List<int> bytes);

  static final GhostPdfExtractor instance = createPdfExtractor();
}
