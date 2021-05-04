import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as path;
import 'package:flagon/flagon_lib.dart';


String _posixRelative(String input,{String from}){
  final path.Context context = path.Context(style: path.Style.posix);
  final String rawInputPath = input;
  final String absInputPath = File(rawInputPath).absolute.path;

  final Uri inputUri = path.toUri(absInputPath);
  final String posixAbsInputPath = context.fromUri(inputUri);
  final Uri tempUri = path.toUri(from);
  final String posixTempPath = context.fromUri(tempUri);

  return context.relative(posixAbsInputPath,from: posixTempPath);
}

///main函数，会在temp目录下创建一个新的dart文件。用于实现多线程（worker）操作。如果在当前Isolate里执行会阻塞。
Future<void> main(List<String> args) async {
  ///解析命令行参数
  final FlagonOptions opts = Flagon.parseArgs(args);
  ///获取temp路径
  final Directory tempDir = Directory.systemTemp.createTempSync();

  String importLine = '';
  if(opts.input != null){
    final String relInputPath = _posixRelative(opts.input, from: tempDir.path);
    importLine = 'import \'${relInputPath}\';\n';
  }

  ///创建一个dart文件提供main函数，用于单独开一个Isolate进行运行。
  final String code = '''// @dart = 2.2
$importLine
import 'dart:io';
import 'dart:isolate';
import 'package:flagon/flagon_lib.dart';

void main(List<String> args, SendPort sendPort) async {
  sendPort.send(await Flagon.run(args));
}
''';
  final File tempFile = File(path.join(tempDir.path,'_pigeon_temp_.dart'));
  await tempFile.writeAsString(code);
  final ReceivePort receivePort = ReceivePort();
  Isolate.spawnUri(Uri.file(tempFile.path), args, receivePort.sendPort);

  final Completer<int> completer = Completer<int>();
  receivePort.listen((dynamic message){
    try{
      completer.complete(message as int);
    }catch(exception){
      completer.completeError(exception);
    }
  });
  final int exitCode = await completer.future;
  tempDir.deleteSync(recursive : true);
  exit(exitCode);
}