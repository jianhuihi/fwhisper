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
final FWhisperBindings whisperCpp = whisperBindings;

// 原生函数类型定义
typedef WhisperPrintSegmentCallbackNative = Void Function(
  Pointer<whisper_context>,
  Pointer<whisper_state>,
  Int,
  Pointer<Int>,
);

// Dart回调函数类型
typedef WhisperPrintSegmentCallbackDart = void Function(
  Pointer<whisper_context>,
  Pointer<whisper_state>,
  int,
  Pointer<Int>,
);

// Dart侧的回调函数实现
void myWhisperPrintSegmentCallback(
  Pointer<whisper_context> whisperCtxPtr,
  Pointer<whisper_state> state,
  int nNew,
  Pointer<Int> userData,
) {
  int dataID = userData.value;
  debugPrint('[Whisper.AI] myWhisperPrintSegmentCallback, nNew: $nNew, dataID: $dataID');
  int nsegments = whisperCpp.whisper_full_n_segments(whisperCtxPtr);
  int t0 = 0;
  int t1 = 0;
  int s0 = nsegments - nNew;
  if (s0 == 0) {
    debugPrint("[Whisper.AI] s0 == 0 \n");
  }
  // 在这里处理回调逻辑
  debugPrint('[Whisper.AI] nsegments: $nsegments');
  for (int i = s0; i < nsegments; ++i) {
    t0 = whisperCpp.whisper_full_get_segment_t0(whisperCtxPtr, i);
    t1 = whisperCpp.whisper_full_get_segment_t1(whisperCtxPtr, i);
    // 获取文本
    Pointer<Utf8> textPtr = whisperCpp.whisper_full_get_segment_text(whisperCtxPtr, i).cast<Utf8>();
    String text = textPtr.toDartString();
    String t0Str = toTimestamp(t0, comma: true);
    String t1Str = toTimestamp(t1, comma: true);
    debugPrint('[Whisper.AI] n_segments text: $text');
    debugPrint('[Whisper.AI] t0: $t0Str');
    debugPrint('[Whisper.AI] t1: $t1Str');
    bool done = false;
    WhisperResponse response = WhisperResponse(nsegments: i, t0: t0, t1: t1, response: text, done: done);
    try {
      final _IsolateInferenceResponse isolateResponse = _IsolateInferenceResponse(
        dataID,
        response.nsegments,
        response.t0,
        response.t1,
        response.response,
        response.done,
      );
      _isolateSendPort.send(isolateResponse); // 将 WhisperResponse 对象直接发送到主isolate
    } catch (e) {
      debugPrint('Error sending response: $e');
    }
  }
}

late Pointer<NativeFunction<WhisperPrintSegmentCallbackNative>> callbackPointer;

Future<void> _generateResponse({
  required String modelFile,
  required String audioFile,
  required Duration videoDuration,
  required int dataID,
}) async {
  final Pointer<Int> userData = calloc<Int>();
  userData.value = dataID; // 假设 dataID 是你想传递给回调的数据
  // 启动时先加载模型文件
  Pointer<Char> fname = audioFile.toNativeUtf8().cast<Char>();
  debugPrint('[Whisper.AI] fname: $fname');
  // 这里获取文件的长度 然后再申请内存
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
  int t = whisperCpp.c_read_wav(fname, pcmf32, pcmf32Length, pcmf32s, pcmf32sLength, stereo);
  // whisperCpp.whisper_full(whisperCtxPtr, params);
  debugPrint('[Whisper.AI] read_wav(...), t: $t');
  debugPrint("[Whisper.AI] AI model file path loading from: $modelFile");
  final File file = File(modelFile);
  if (!file.existsSync()) {
    throw Exception('File does not exist: $modelFile');
  }
  final Pointer<Char> modelPath = modelFile.toNativeUtf8().cast<Char>();
  // 记录加载的时间
  final Stopwatch stopwatch = Stopwatch()..start();

  final whisper_context_params cparams = whisperCpp.whisper_context_default_params();

  cparams.use_gpu = true;
  // Load the model
  final Pointer<whisper_context> whisperCtxPtr = whisperCpp.whisper_init_from_file_with_params(modelPath, cparams);
  // initialize openvino encoder. this has no effect on whisper.cpp builds that don't have OpenVINO configured
  whisperCpp.whisper_ctx_init_openvino_encoder(whisperCtxPtr, nullptr, "CPU".toNativeUtf8().cast<Char>(), nullptr);
  debugPrint(whisperCpp.whisper_print_system_info().cast<Utf8>().toDartString());
  // 执行时间
  debugPrint('[Whisper.AI] whisper_init_from_file_with_params(...), elapsed: ${stopwatch.elapsedMilliseconds} ms');

  // wparams.new_segment_callback = Pointer.fromFunction<whisper_new_segment_callback>(whisperPrintSegmentCallback);
  {
    callbackPointer = Pointer.fromFunction<WhisperPrintSegmentCallbackNative>(
      myWhisperPrintSegmentCallback,
    );
    final whisper_full_params wparams =
        whisperCpp.whisper_full_default_params(whisper_sampling_strategy.WHISPER_SAMPLING_GREEDY);
    // wparams.max_len = 1; // 目前还不起作用呢
    wparams.language = "en".toNativeUtf8().cast<Char>();
    // wparams.strategy = whisper_sampling_strategy.WHISPER_SAMPLING_BEAM_SEARCH;
    // wparams.n_threads = 4;
    wparams.print_realtime = false;
    wparams.debug_mode = true;

    if (!wparams.print_realtime) {
      wparams.new_segment_callback = callbackPointer;
      wparams.new_segment_callback_user_data = userData;
    }
    debugPrint('[Whisper.AI] whisper_full_params, elapsed: ${stopwatch.elapsedMilliseconds} ms');
    if (whisperCpp.whisper_full_parallel(whisperCtxPtr, wparams, pcmf32, pcmf32Length.value, 1) != 0) {
      debugPrint('[Whisper.AI] failed to process audio');
    }
  }

  debugPrint('[Whisper.AI] whisper_full_parallel,  end elapsed: ${stopwatch.elapsedMilliseconds} ms');
  whisperCpp.whisper_print_timings(whisperCtxPtr);
  whisperCpp.whisper_free(whisperCtxPtr);
  calloc.free(pcmf32); // Freeing the pointer after using it
  calloc.free(pcmf32Length);
  calloc.free(pcmf32s);
  calloc.free(pcmf32sLength);
  calloc.free(userData);
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
  final int nsegments;
  final int t0;
  final int t1;
  final String response;
  final bool done;

  const _IsolateInferenceResponse(this.id, this.nsegments, this.t0, this.t1, this.response, this.done);
}

/// Counter to identify [_IsolateInferenceRequest]s and [_IsolateInferenceResponse]s.
int _nextInferenceRequestId = 0;

/// Mapping from [_IsolateInferenceRequest] `id`s to the completers
/// corresponding to the correct future of the pending request.
final Map<int, Completer<String>> _isolateInferenceRequests = <int, Completer<String>>{};
final Map<int, FwhisperInferenceCallback> _isolateInferenceCallbacks = <int, FwhisperInferenceCallback>{};

// The SendPort belonging to the helper isolate.
late SendPort _isolateSendPort;

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
        debugPrint('[fwhisper] Received SendPort from helper isolate');
        completer.complete(data);
        return;
      }

      debugPrint('[fwhisper] Received message from helper isolate: $data');
      if (data is _IsolateInferenceResponse) {
        final callback = _isolateInferenceCallbacks[data.id];
        if (callback != null) {
          debugPrint('[fwhisper] Received response for request ${data.done}');
          callback(data.nsegments, data.t0, data.t1, data.response, data.done);
        }
        if (data.done) {
          _isolateInferenceCallbacks.remove(data.id);
          final Completer<String> completer = _isolateInferenceRequests[data.id]!;
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
    final ReceivePort helperReceivePort = ReceivePort();
    sendPort.send(helperReceivePort.sendPort);
    helperReceivePort.listen((dynamic data) async {
      if (data is _IsolateInferenceRequest) {
        _isolateSendPort = sendPort;
        await _generateResponse(
          modelFile: data.request.modelFile,
          audioFile: data.request.audioFile,
          videoDuration: data.request.videoDuration,
          dataID: data.id,
        );
      }
    });

    // Send the port to the main isolate on which we can receive requests.
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return completer.future;
}();
