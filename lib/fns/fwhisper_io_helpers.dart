import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

Pointer<Char> stringToPointerChar(String string) {
  final units = utf8.encode(string);
  final Pointer<Uint8> result = calloc<Uint8>(units.length + 1);
  final Uint8List nativeString = result.asTypedList(units.length + 1);
  nativeString.setAll(0, units);
  nativeString[units.length] = 0; // Null-terminate
  return result.cast<Char>();
}

String pointerCharToString(Pointer<Char> pointerChar) {
  return pointerChar.cast<Utf8>().toDartString();
}

String toTimestamp(int t, {bool comma = false}) {
  t = t * 10;
  Duration duration = Duration(milliseconds: t);
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  String threeDigits(int n) => n.toString().padLeft(3, '0');

  String hours = twoDigits(duration.inHours.remainder(60));
  String minutes = twoDigits(duration.inMinutes.remainder(60));
  String seconds = twoDigits(duration.inSeconds.remainder(60));
  String millis = threeDigits(duration.inMilliseconds.remainder(1000));
  return "$hours:$minutes:$seconds${comma ? ',' : '.'}$millis";
}