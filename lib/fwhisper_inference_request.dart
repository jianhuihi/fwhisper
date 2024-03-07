class FwhisperInferenceRequest {
  String modelFile;
  String audioFile;

  FwhisperInferenceRequest({
    required this.modelFile,
    required this.audioFile,
  });
   
}

class WhisperResponse {
  int nsegments;
  int t0;
  int t1;
  String response;
  bool done;

  WhisperResponse({
    required this.nsegments,
    required this.t0,
    required this.t1,
    required this.response,
    required this.done,
  });
   
}
