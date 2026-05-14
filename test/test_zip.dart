import 'dart:io';
import 'package:archive/archive_io.dart';

void main() {
  final encoder = ZipFileEncoder();
  encoder.create('/tmp/test.zip');
  final f = File('/tmp/vault.json')..writeAsStringSync('{}');
  encoder.addFile(f);
  encoder.close();
  
  final bytes = File('/tmp/test.zip').readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive) {
    print('File in zip: ${file.name}');
  }
}
