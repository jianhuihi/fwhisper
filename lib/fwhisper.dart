import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';


import 'package:flutter/foundation.dart';

import 'fwhisper_bindings_generated.dart';


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


Pointer<whisper_context>? whisperCtxPtr;

Stream<String> _generateResponse({
  required String modelFile,
  required String audioFile,
}) async* {
  final FWhisperBindings whisperCpp = whisperBindings;

  Pointer<Char> fname = audioFile.toNativeUtf8().cast<Char>();
  debugPrint('[Whisper.AI] fname: $fname');
  final Pointer<Float> pcmf32 = calloc<Float>(MAX_PCMF32_LENGTH);
  final Pointer<Size> pcmf32Length = calloc<Size>(1); // 分配内存

  const int rows = 1;
  const int cols = MAX_PCMF32_LENGTH; // 每行的元素数量

  // 分配指向浮点数组的指针数组
  final Pointer<Pointer<Float>> pcmf32s = calloc<Pointer<Float>>(rows);

  // 为每一行分配浮点数组
  for (int i = 0; i < rows; i++) {
    pcmf32s[i] = calloc<Float>(cols);
  }

  final Pointer<Size> pcmf32sLength = nullptr;

  int stereo = 0;

  debugPrint('[Whisper.AI] start pcmf32: ${pcmf32.value}, pcmf32Length: ${pcmf32Length}, stereo: $stereo');

  //Float32List pcmf32List = pcmf32.asTypedList(MAX_PCMF32_LENGTH);
  // debugPrint("pcmf32 before calling C/C++: $pcmf32List");

  int t = whisperCpp.c_read_wav(fname, pcmf32, pcmf32Length, pcmf32s, pcmf32sLength, stereo);

  // whisperCpp.whisper_full(whisperCtxPtr, params);

  debugPrint('[Whisper.AI] read_wav(...), t: $t');

  // // // 调用C/C++函数之后，检查pcmf32的内容
  // Float32List pcmf32List = pcmf32.asTypedList(1000);
  // debugPrint("pcmf32 after calling C/C++: $pcmf32List");

  // Check if the file exists
  debugPrint("[Whisper.AI] AI model file path loading from: $modelFile");
  final File file = File(modelFile);
  if (!file.existsSync()) {
    throw Exception('File does not exist: $modelFile');
  }

  final Pointer<Char> modelPath = modelFile.toNativeUtf8().cast<Char>();

  final Pointer<whisper_context> whisperCtxPtr = whisperCpp.whisper_init_from_file(modelPath);
  debugPrint('[Whisper.AI] whisper_init_from_file(...)');
  debugPrint('[Whisper.AI] whisperCtxPtr: $whisperCtxPtr');

  final Pointer<Char> audioPath = audioFile.toNativeUtf8().cast<Char>();
  debugPrint('[Whisper.AI] audioPath: $audioPath');

  final whisper_full_params params = whisperCpp.whisper_full_default_params(whisper_sampling_strategy.WHISPER_SAMPLING_GREEDY);
  params.language = "en".toNativeUtf8().cast<Char>();


  debugPrint('[Whisper.AI] whisper_full_default_params(...)');

  //whisperCpp.whisper_print_system_info();


  //whisperCpp.whisper_print_timings(whisperCtxPtr);

  if (whisperCpp.whisper_full(whisperCtxPtr, params, pcmf32, pcmf32Length.value) != 0) {
    debugPrint('[Whisper.AI] whisper_full(...)');
  }
  int nsegments = whisperCpp.whisper_full_n_segments(whisperCtxPtr);
  debugPrint('[Whisper.AI] whisper_full_n_segments(), nsegments: $nsegments');
  for (int i = 0; i < nsegments; ++i) {
    Pointer<Utf8> textPtr = whisperCpp.whisper_full_get_segment_text(whisperCtxPtr, i).cast<Utf8>();
    int t0 = whisperCpp.whisper_full_get_segment_t0(whisperCtxPtr, i);
    int t1 = whisperCpp.whisper_full_get_segment_t1(whisperCtxPtr, i);
    String text = textPtr.toDartString();
    String t0Str = toTimestamp(t0, comma: true);
    String t1Str = toTimestamp(t1, comma: true);
    debugPrint('[Whisper.AI] whisper_full_get_segment_text(...)');
    debugPrint('[Whisper.AI] text: $text');
    debugPrint('[Whisper.AI] t0: $t0Str');
    debugPrint('[Whisper.AI] t1: $t1Str');
  }

  //final Pointer<whisper_result> whisperResultPtr = whisperCpp.whisper_run(whisperCtxPtr, audioPath);
  debugPrint('[Whisper.AI] whisper_run(...)');

  whisperCpp.whisper_print_timings(whisperCtxPtr);


  calloc.free(pcmf32); // Freeing the pointer after using it
  calloc.free(pcmf32Length);
  calloc.free(pcmf32s);
  calloc.free(pcmf32sLength);
  whisperCpp.whisper_free(whisperCtxPtr);
}

typedef OnTokenGeneratedCallback = void Function(String token);

OnTokenGeneratedCallback? _onTokenGenerated;

Future<void> talkAsync({
  required String modelFile,
  required String audioFile,
  required OnTokenGeneratedCallback onTokenGenerated,
}) async {
  // This is used to send requests to the helper isolate.
  // By using isolates, we can run the AI model in a separate thread and thus
  // prevent the main isolate from blocking while the AI model is running.
  // Otherwise, the UI would freeze while the AI model is running.
  _onTokenGenerated = onTokenGenerated;
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextWhisperRequestId++;
  final _WhisperRequest request = _WhisperRequest(
    requestId,
    modelFile,
    audioFile,
  );
  final Completer<void> completer = Completer<void>();

  // Completer that is a stream. We listen to the stream to get the last token
  // of the response.
  _whisperRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

/// The dynamic library in which the symbols for [FlutterWhisperCppBindings] can be found.
final DynamicLibrary _dylib = () {
  /// [libName] is basically the base name of the compiled file name that
  /// contains the native functions. The file name is platform dependent.
  const String libName = 'fwhisper';

  // macOS (x86_64, ARM64)
  if (Platform.isMacOS) {
    debugPrint('Current working directory: ${Directory.current.path}');

    return DynamicLibrary.open('$libName.framework/$libName');
  }

  // iOS (ARM64)
  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }

  // Android (ARM64) and Linux (x86_64)
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$libName.so');
  }

  // Windows (x86_64)
  if (Platform.isWindows) {
    return DynamicLibrary.open('$libName.dll');
  }

  // Unsupported platform
  throw UnsupportedError('Sorry, your platform/OS is not supported. '
      'You are running: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final FWhisperBindings _bindings = FWhisperBindings(_dylib);

FWhisperBindings get whisperBindings => _bindings;

// Assuming the Whisper library has a function like: const char* whisper_version();

/// A request to compute `sum`.
///
/// Typically sent from one isolate to another.
class _WhisperRequest {
  final int id;
  final String modelFile;
  final String audioFile;
  const _WhisperRequest(this.id, this.modelFile, this.audioFile);
}

/// A response with the result of `sum`.
///
/// Typically sent from one isolate to another.
class _WhisperResponse {
  final int id;
  final String result;

  const _WhisperResponse(this.id, this.result);
}

int _nextWhisperRequestId = 0;

/// Mapping from [_whisperRequest] `id`s to the completers corresponding to the correct future of the pending request.
final Map<int, Completer<void>> _whisperRequests = <int, Completer<void>>{};

/// The SendPort belonging to the helper isolate.
Future<SendPort> _helperIsolateSendPort = () async {
  // The helper isolate is going to send us back a SendPort, which we want to
  // wait for.
  final Completer<SendPort> completer = Completer<SendPort>();

  // Receive port on the main isolate to receive messages from the helper.
  // We receive two types of messages:
  // 1. A port to send messages on.
  // 2. Responses to requests we sent.
  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        // The helper isolate sent us the port on which we can sent it requests.
        completer.complete(data);
        return;
      }
      if (data is _WhisperResponse) {
        // The helper isolate sent us a response to a request we sent.
        final Completer<void> completer = _whisperRequests[data.id]!;
        _whisperRequests.remove(data.id);
        completer.complete();
        return;
      }

      if (_onTokenGenerated == null) {
        throw Exception('onTokenGeneratedGlobal is null');
      }

      _onTokenGenerated!(data.result);

      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  // Start the helper isolate.
  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        // On the helper isolate listen to requests and respond to them.
        if (data is _WhisperRequest) {
          _generateResponse(
            modelFile: data.modelFile,
            audioFile: data.audioFile,
          ).listen((String lastToken) {
            // Because we're using streams, we can't send the last token of the
            // response back to the main isolate directly. Instead, we send it
            // back in a _PromptBatchOutput object.
            final _WhisperResponse replyByAssistant = _WhisperResponse(
              data.id,
              lastToken,
            );

            // Send the _PromptBatchOutput back to the main isolate.
            sendPort.send(replyByAssistant);
          });
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

    // Send the port to the main isolate on which we can receive requests.
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return completer.future;
}();
