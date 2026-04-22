import 'dart:io';
import 'package:path/path.dart' as p;
import 'lib/engine/infra/env.dart';

void main() {
  try {
    print('Scripts Dir: ${Env.scriptsDir}');
  } catch (e) {
    print('Error: $e');
  }
}
