import 'package:flutter/foundation.dart';

void printOnDebug(Object? obj) {
  if (kDebugMode) debugPrint(obj.toString());
}
