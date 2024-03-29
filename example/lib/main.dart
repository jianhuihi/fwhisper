import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;
import 'package:fwhisper/fwhisper.dart' as fwhisper;

import 'package:video_player/video_player.dart';


Future<String> getTemporaryDirectoryPath() async {
  final directory = await getTemporaryDirectory();
  return directory.path;
}

Future<String> saveFileToDocuments() async {
  final directory = await getApplicationDocumentsDirectory();
  final path = directory.path;
  final file = File('$path/jfk.wav');

  final Directory? downloadsDir = await getDownloadsDirectory();

  debugPrint('downloadsDir: $downloadsDir');

  final byteData = await rootBundle.load('assets/wav/jfk.wav');
  final buffer = byteData.buffer;
  await file.writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
  return file.path;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // 确保Flutter绑定初始化
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  double downloadProgress = 0.0;
  String? modelPath;
  String latestResult = '';
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  // 异步方法，获取视频时长
Future<Duration> getVideoDuration(String videoFile) async {
  final VideoPlayerController controller = VideoPlayerController.file(File(videoFile));
  await controller.initialize();
  final Duration duration = controller.value.duration;
  controller.dispose(); // 使用完毕后释放控制器资源
  return duration;
}

  Future<void> downloadFile(String model, [String? modelsPath]) async {
    // 设置代理
    const src = 'https://huggingface.co/ggerganov/whisper.cpp';
    const pfx = 'resolve/main/ggml';

    // 设置模型路径
    modelsPath ??= Directory.current.path;

    // 定义模型列表
    final models = <String>{
      'tiny.en',
      'base.en',
    };

    // 检查模型是否有效
    if (!models.contains(model)) {
      debugPrint('Invalid model: $model');
      return;
    }

    // 更新src和pfx，如果模型包含'tdrz'
    final adjustedSrc = model.contains('tdrz') ? 'https://huggingface.co/akashmjn/tinydiarize-whisper.cpp' : src;

    // 检查文件是否已存在
    final modelsFilePath = path.join(modelsPath, 'ggml-$model.bin');
    if (File(modelsFilePath).existsSync()) {
      debugPrint('Model $model already exists. Skipping download.');
      return;
    }

    // 使用dio下载文件
    debugPrint('Downloading ggml model $model from $adjustedSrc ...');
    Dio dio = Dio();

    try {
      await dio.download(
        '$adjustedSrc/$pfx-$model.bin',
        modelsFilePath,
        onReceiveProgress: (int received, int total) {
          if (total != -1) {
            setState(() {
              downloadProgress = received / total;
            });
            // 输出下载进度
            debugPrint("Downloading: ${((received / total) * 100).toStringAsFixed(0)}%");
          }
        },
      );
      debugPrint("Done! Model '$model' saved in '$modelsFilePath'");
    } catch (e) {
      debugPrint('An error occurred while downloading the model: $e');
    }
  }

  Future<String> saveModelFileToDownloads() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = directory.path;

    await downloadFile('base.en', path);

    final targetFile = File('$path/ggml-base.en.bin');
    debugPrint('targetFile: $targetFile');
    return targetFile.path;
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 14);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Whisper Demo'),
        ),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ElevatedButton.icon(
                //   onPressed: saveModelFileToDownloads,
                //   icon: const Icon(Icons.download_sharp),
                //   label: const Text('down  .bin'),
                // ),
                // spacerSmall,
                // LinearProgressIndicator(
                //   value: downloadProgress,
                //   backgroundColor: Colors.grey[300],
                //   valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                // ),
                // spacerSmall,
                ElevatedButton.icon(
                  onPressed: _openGgufPressed,
                  icon: const Icon(Icons.file_open),
                  label: const Text('Open .bin'),
                ),
                if (modelPath != null)
                  SelectableText(
                    'Model path: $modelPath',
                    style: textStyle,
                  ),
                spacerSmall,
                if (modelPath != null)
                  TextField(
                    controller: _controller,
                  ),
                const SizedBox(
                  height: 8,
                ),
                ElevatedButton(
                  onPressed: () async {
                    debugPrint('modelPath: $modelPath');

                    String audioPath = await saveFileToDocuments();
                    debugPrint('path: $audioPath');
                    //把 ggml-base.en.bin 读取并 保存到 Downloads/models 目录下 并返回对应路径
                    //String modelPath = await saveModelFileToDownloads();
                    // 获取视频时长
                    final videoDuration = await getVideoDuration(audioPath);

                    await fwhisper.fWhisperTranscriptionAsync(
                      fwhisper.FwhisperInferenceRequest(
                        modelFile: modelPath!,
                        audioFile: audioPath,
                        videoDuration: videoDuration,
                      ),
                      (t, t0, t1, result, done ) {
                        debugPrint('result: $t0, $t1, $result, $done');
                        setState(() {
                          latestResult = result;
                        });
                      } as fwhisper.FwhisperInferenceCallback,
                    );
            
                  },
                  child: const Text('Run inference'),
                ),
                SelectableText(
                  latestResult,
                  style: textStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openGgufPressed() async {
    XTypeGroup ggufTypeGroup = const XTypeGroup(
      label: '.bin',
      extensions: ['bin'],
      // UTIs are required for iOS, which does not support local LLMs.
      uniformTypeIdentifiers: [],
    );
    debugPrint('kIsWeb: $kIsWeb');
    if (!kIsWeb && Platform.isAndroid) {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      final file = result?.files.first;
      if (file == null) {
        return;
      }
      final filePath = file.path;
      setState(() {
        modelPath = filePath;
      });
    } else {
      debugPrint('openFile');
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[
        if (!Platform.isIOS) ggufTypeGroup,
      ]);

      debugPrint('file: $file');

      if (file == null) {
        return;
      }
      final filePath = file.path;
      setState(() {
        modelPath = filePath;
      });
    }
  }
}

Future<String> getDocumentsPath() async {
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
}

Future<List<String>> listFiles(String path) async {
  final directory = Directory(path);
  final List<String> files = [];

  await for (var entity in directory.list()) {
    files.add(entity.path);
  }

  return files;
}

Future<List<int>> readWavFile(String path) async {
  final file = File(path);

  if (await file.exists()) {
    return await file.readAsBytes();
  } else {
    throw Exception("File not found");
  }
}
