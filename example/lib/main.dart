import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';


import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'dart:io';


import 'package:fwhisper/fwhisper.dart' as fwhisper;



Future<void> downloadModel(String model, [String? modelsPath]) async {
  const src = 'https://huggingface.co/ggerganov/whisper.cpp';
  const pfx = 'resolve/main/ggml';

  // 设置模型路径
  modelsPath ??= Directory.current.path;
  // 定义模型列表
  final models = <String>{
    'tiny.en', 'base.en', /* ... 其他模型 ... */
  };
  // 检查模型是否有效
  if (!models.contains(model)) {
    print('Invalid model: $model');
    return;
  }
  // 更新src和pfx，如果模型包含'tdrz'
  final adjustedSrc = model.contains('tdrz')
      ? 'https://huggingface.co/akashmjn/tinydiarize-whisper.cpp'
      : src;

  // 检查文件是否已存在
  final filePath = path.join(modelsPath, 'ggml-$model.bin');
  if (File(filePath).existsSync()) {
    print('Model $model already exists. Skipping download.');
    return;
  }

  // 下载文件
  print('Downloading ggml model $model from $adjustedSrc ...');
  try {
    print(Uri.parse('$adjustedSrc/$pfx-$model.bin'));
    final response = await http.get(Uri.parse('$adjustedSrc/$pfx-$model.bin'));
    if (response.statusCode == 200) {
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      print("Done! Model '$model' saved in '$filePath'");
    } else {
      print('Failed to download ggml model $model');
    }
  } catch (e) {
    print('An error occurred while downloading the model: $e');
  }
}


class MyHttpOverrides extends HttpOverrides {
  final String proxyAddress;

  MyHttpOverrides(this.proxyAddress);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        return 'PROXY $proxyAddress';
      };
      // 如果您的代理服务器或目标URL需要忽略SSL证书验证，可以取消注释下面的代码
      // ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> downloadFile(String model, String proxyAddress, [String? modelsPath]) async {
  // 设置代理
  // HttpOverrides.global = MyHttpOverrides(proxyAddress);

  const src = 'https://huggingface.co/ggerganov/whisper.cpp';
  const pfx = 'resolve/main/ggml';

  // 设置模型路径
  modelsPath ??= Directory.current.path;
  // 定义模型列表
  final models = <String>{
    'tiny.en', 'base.en', /* ... 其他模型 ... */
  };
  // 检查模型是否有效
  if (!models.contains(model)) {
    print('Invalid model: $model');
    return;
  }
  // 更新src和pfx，如果模型包含'tdrz'
  final adjustedSrc = model.contains('tdrz')
      ? 'https://huggingface.co/akashmjn/tinydiarize-whisper.cpp'
      : src;

  // 检查文件是否已存在
  final modelsfilePath = path.join(modelsPath, 'ggml-$model.bin');
  if (File(modelsfilePath).existsSync()) {
    print('Model $model already exists. Skipping download.');
    return;
  }

  // 下载文件
  print('Downloading ggml model $model from $adjustedSrc ...');
  try {
    debugPrint('modelsfilePath: $modelsfilePath');

    print(Uri.parse('$adjustedSrc/$pfx-$model.bin'));
    final response = await http.get(Uri.parse('$adjustedSrc/$pfx-$model.bin'));
    debugPrint('modelsfilePath: $modelsfilePath');
    if (response.statusCode == 200) {
      final file = File(modelsfilePath);
      await file.writeAsBytes(response.bodyBytes);
      print("Done! Model '$model' saved in '$modelsfilePath'");
    } else {
      print('Failed to download ggml model $model');
    }
  } catch (e) {
    print('An error occurred while downloading the model: $e');
  }
}


void main() async {
  //final ddbytes = await readWavFile('assets/wav/jfk.wav');
  //debugPrint('ddbytes: $ddbytes');
  runApp(const MyApp());


}

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

Future<String> saveModelFileToDownloads() async {
  final directory = await getApplicationDocumentsDirectory();
  final path = directory.path;

  await downloadFile('base.en', "192.168.50.98:6152", path );

  final targetFile = File('$path/ggml-base.en.bin');

  return targetFile.path;
}



class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
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

class _MyAppState extends State<MyApp> {
  late int sumResult;
  late Future<int> sumAsyncResult;

  @override
  void initState() {
    super.initState();
    initializeAsyncData();
  }

  Future<void> initializeAsyncData() async {
    // 异步加载数据或执行其他异步操作
    var data = await getTemporaryDirectoryPath();
    debugPrint('data: $data');
    var data2 = await getDocumentsPath();
    debugPrint('data2: $data2');
    //把 jfk.wav 读取并 保存到 Documents 目录下 并返回对应路径 
    String audioPath = await saveFileToDocuments();
    debugPrint('path: $audioPath');
    //把 ggml-base.en.bin 读取并 保存到 Downloads/models 目录下 并返回对应路径
    String modelPath = await saveModelFileToDownloads();

    fwhisper.talkAsync(
      modelFile: modelPath,
      audioFile: audioPath,
      onTokenGenerated: (token) {
        debugPrint('token: $token');
      },
    );

  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Native Packages'),
        ),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                const Text(
                  'This calls a native function through FFI that is shipped as source in the package. '
                  'The native code is built as part of the Flutter Runner build.',
                  style: textStyle,
                  textAlign: TextAlign.center,
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
