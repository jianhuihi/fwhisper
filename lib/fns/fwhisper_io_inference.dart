import 'dart:async';
import 'dart:io';

import 'dart:ffi';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

import 'package:ffi/ffi.dart';
import 'package:fwhisper/fwhisper_io.dart';
import 'package:fwhisper/fwhisper_bindings_generated.dart';
import 'package:fwhisper/fwhisper_inference_request.dart';

import 'package:fwhisper/fns/fwhisper_io_helpers.dart';

Pointer<whisper_context>? whisperCtxPtr;

Stream<_IsolateInferenceResponse> _generateResponse({
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
  debugPrint('[Whisper.AI] start pcmf32: ${pcmf32.value}, stereo: $stereo');
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
  debugPrint('[Whisper.AI] whisperCtxPtr: $whisperCtxPtr');
  final Pointer<Char> audioPath = audioFile.toNativeUtf8().cast<Char>();
  debugPrint('[Whisper.AI] audioPath: $audioPath');
  final whisper_full_params params =
      whisperCpp.whisper_full_default_params(whisper_sampling_strategy.WHISPER_SAMPLING_GREEDY);
  params.language = "zh".toNativeUtf8().cast<Char>();
  debugPrint('[Whisper.AI] whisper_full_default_params(...)');
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

    bool done = false;
    done = (i == nsegments - 1);
    _IsolateInferenceResponse response = _IsolateInferenceResponse(i, text, done);
    yield response; // 将识别到的文本发送出去
  }

  debugPrint('[Whisper.AI] whisper_full end');
  whisperCpp.whisper_print_timings(whisperCtxPtr);
  debugPrint('[Whisper.AI] whisper_print_timings end');

  whisperCpp.whisper_free(whisperCtxPtr);
  calloc.free(pcmf32); // Freeing the pointer after using it
  calloc.free(pcmf32Length);
  calloc.free(pcmf32s);
  calloc.free(pcmf32sLength);
}

// This callback type will be used in Dart to receive incremental results
Future<String> fwhisperInferenceAsync(FwhisperInferenceRequest request, FwhisperInferenceCallback callback) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextInferenceRequestId++;
  final _IsolateInferenceRequest isolateRequest = _IsolateInferenceRequest(requestId, request);
  final Completer<String> completer = Completer<String>();
  _isolateInferenceRequests[requestId] = completer;
  _isolateInferenceCallbacks[requestId] = callback;
  try {
    helperIsolateSendPort.send(isolateRequest);
  } catch (e) {
    // ignore: avoid_print
    print('[fwhisper] ERROR sending request to helper isolate: $e');
  }
  return completer.future;
}

/// A request to compute `sum`.
///
/// Typically sent from one isolate to another.
class _IsolateInferenceRequest {
  final int id;
  final FwhisperInferenceRequest request;

  const _IsolateInferenceRequest(this.id, this.request);
}

/// Typically sent from one isolate to another.
class _IsolateInferenceResponse {
  final int id;
  final String response;
  final bool done;

  const _IsolateInferenceResponse(this.id, this.response, this.done);
}

/// Counter to identify [_IsolateInferenceRequest]s and [_IsolateInferenceResponse]s.
int _nextInferenceRequestId = 0;

/// Mapping from [_IsolateInferenceRequest] `id`s to the completers
/// corresponding to the correct future of the pending request.
final Map<int, Completer<String>> _isolateInferenceRequests = <int, Completer<String>>{};
final Map<int, FwhisperInferenceCallback> _isolateInferenceCallbacks = <int, FwhisperInferenceCallback>{};

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
      if (data is _IsolateInferenceResponse) {
        final callback = _isolateInferenceCallbacks[data.id];
        if (callback != null) {
          callback(data.response, data.done);
        }
        if (data.done) {
          _isolateInferenceCallbacks.remove(data.id);
          final Completer<String> completer =
              _isolateInferenceRequests[data.id]!;
          completer.complete(data.response);
          _isolateInferenceRequests.remove(data.id);
          return;
        } else {
          return;
        }
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  // Start the helper isolate.
  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        try {
          // On the helper isolate listen to requests and respond to them.
          if (data is! _IsolateInferenceRequest) {
            throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
          }

          /// 请求数据
          _generateResponse(
            modelFile: data.request.modelFile,
            audioFile: data.request.audioFile,
          ).listen((_IsolateInferenceResponse wshisperResponse) {
            // Because we're using streams, we can't send the last token of the
            // response back to the main isolate directly. Instead, we send it
            final _IsolateInferenceResponse replyByAssistant = _IsolateInferenceResponse(
              data.id,
              wshisperResponse.response,
              wshisperResponse.done,
            );
            debugPrint('replyByAssistant: ${replyByAssistant.response}, done: ${replyByAssistant.done}');
            sendPort.send(replyByAssistant);
          });
          return;
        } catch (e, s) {
          // ignore: avoid_print
          print('[fwhisper inference isolate] ERROR: $e. STACK: $s');
        }
      });

    // Send the port to the main isolate on which we can receive requests.
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return completer.future;
}();
