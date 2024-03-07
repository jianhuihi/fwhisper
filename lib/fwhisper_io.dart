
export 'fns/fwhisper_io_transcription.dart';
export 'fns/fwhisper_io_inference.dart';

import 'dart:ffi';
import 'dart:io';

import 'package:fwhisper/fwhisper_bindings_generated.dart';

typedef FwhisperInferenceCallback = void Function(int nsegments, int t0, int t1, String response, bool done);

const String fwhisperLibName = 'fwhisper';

/// The dynamic library in which the symbols for [FWhisperBindings] can be found.
final DynamicLibrary fwhisperDylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$fwhisperLibName.framework/$fwhisperLibName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$fwhisperLibName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$fwhisperLibName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();


final FWhisperBindings _bindings = FWhisperBindings(fwhisperDylib);

FWhisperBindings get whisperBindings => _bindings;
