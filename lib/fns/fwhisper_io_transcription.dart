import 'package:fwhisper/fwhisper_io.dart';
import 'package:fwhisper/fwhisper_inference_request.dart';

Future<String> fWhisperTranscriptionAsync(FwhisperInferenceRequest request, FwhisperInferenceCallback callback) async {
  //
  return fwhisperInferenceAsync(request, callback);
}
