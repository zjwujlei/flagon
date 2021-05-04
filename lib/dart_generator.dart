

import 'ast.dart';
import 'generator_tools.dart';

class DartOptions{
  /// Determines if the generated code has null safety annotations (Dart >2.10 required).
  bool isNullSafe = false;
}

void _writeHostApi(DartOptions opt, Indent indent, Api api){
  assert(api.location == ApiLocation.host);
  final String nullTag = opt.isNullSafe?'?':'';
  indent.write('class ${api.name}');
  indent.scoped('{', '}', (){
    for(Method func in api.methods){
      String argSignature = '';
      String sendArgument = 'null';
      String requestMapDeclaration;
      if(func.argType != 'void'){
        argSignature = '${func.argType} arg';
        sendArgument = 'requestMap';
        requestMapDeclaration = 'final Map<dynamic, dynamic> requestMap = arg._toMap();';
      }
      ///声明函数
      indent.write('Future<${func.returnType}> ${func.name}(${argSignature}) async');
      ///添加函数体
      indent.scoped('{', '}', (){
        ///定义返回值
        if(requestMapDeclaration != null){
          indent.writeln(requestMapDeclaration);
        }
        final channelName = makeChannelName(api, func);
        //创建channel
        indent.writeln('const BasicMessageChannel<dynamic> channel =');
        indent.inc();
        indent.inc();
        indent.writeln('BasicMessageChannel<dynamic>(\'$channelName\', StandardMessageCodec());');
        indent.dec();
        indent.dec();
        indent.writeln('');
        final String returnStatement = func.returnType == 'void'
            ?'// noop'
            :'return ${func.returnType}._fromMap(replyMap[\'${Keys.result}\']);';
        ///用'''定义多行字符串。调用channel获取replyMap。根据replyMap里面的结果做不同处理。
        indent.format(
            '''final Map<dynamic, dynamic>$nullTag replyMap = await channel.send($sendArgument);
if (replyMap == null) {
\tthrow PlatformException(
\t\tcode: 'channel-error',
\t\tmessage: 'Unable to establish connection on channel.',
\t\tdetails: null);
} else if (replyMap['error'] != null) {
\tfinal Map<dynamic, dynamic> error = replyMap['${Keys.error}'];
\tthrow PlatformException(
\t\t\tcode: error['${Keys.errorCode}'],
\t\t\tmessage: error['${Keys.errorMessage}'],
\t\t\tdetails: error['${Keys.errorDetails}']);
} else {
\t$returnStatement
}
            '''
        );
      });
    }
  });

}

void _writeFlutterApi(DartOptions opt, Indent indent, Api api, {String Function(Method) channelNameFunc, bool isMockHandler = false}){
  assert(api.location == ApiLocation.flutter);
  final String nullTag = opt.isNullSafe?'?':'';
  indent.write('abstract class ${api.name} ');
  indent.scoped('{', '}', (){
    for(Method func in api.methods){
      final bool isAsync = func.isAsynchronous;
      final String returnType = isAsync?'Future<${func.returnType}>':'${func.returnType}';
      final String argSignature = func.argType == 'void'? '':'${func.argType} arg';
      indent.writeln('$returnType ${func.name}($argSignature);');
    }
    indent.write('static void setup(${api.name}$nullTag api) ');
    indent.scoped('{', '}', (){
      for(Method func in api.methods){
        indent.writeln('');
        indent.scoped('{', '}', (){
          indent.writeln('const BasicMessageChannel<dynamic> channel =');
          indent.inc();
          indent.inc();
          final String channelName = channelNameFunc == null
              ? makeChannelName(api, func)
              : channelNameFunc(func);
          indent.writeln(
              'BasicMessageChannel<dynamic>(\'$channelName\', StandardMessageCodec());');
          indent.dec();
          indent.dec();
          final String messageHandlerSetter =
          isMockHandler ? 'setMockMessageHandler' : 'setMessageHandler';
          indent.write('if (api == null) ');
          indent.scoped('{', '} else {', () {
            indent.writeln('channel.$messageHandlerSetter(null);');
          });
          indent.scoped('', '}', () {
            indent.write(
                'channel.$messageHandlerSetter((dynamic message) async ');
            indent.scoped('{', '});', () {
              final String argType = func.argType;
              final String returnType = func.returnType;
              final bool isAsync = func.isAsynchronous;
              String call;
              if (argType == 'void') {
                call = 'api.${func.name}()';
              } else {
                indent.writeln(
                    'final Map<dynamic, dynamic> mapMessage = message as Map<dynamic, dynamic>;');
                indent.writeln(
                    'final $argType input = $argType._fromMap(mapMessage);');
                call = 'api.${func.name}(input)';
              }
              if (returnType == 'void') {
                indent.writeln('$call;');
                if (isMockHandler) {
                  indent.writeln('return <dynamic, dynamic>{};');
                }
              } else {
                if (isAsync) {
                  indent.writeln('final $returnType output = await $call;');
                } else {
                  indent.writeln('final $returnType output = $call;');
                }
                const String returnExpresion = 'output._toMap()';
                final String returnStatement = isMockHandler
                    ? 'return <dynamic, dynamic>{\'${Keys.result}\': $returnExpresion};'
                    : 'return $returnExpresion;';
                indent.writeln(returnStatement);
              }
            });
          });
        });
      }
    });
  });
}

void generateDart(DartOptions opt,Root root,StringSink sink){
  final List<String> customClassNames = root.classes.map((Class x) => x.name).toList();
  final Indent indent = Indent(sink);
  ///写入注释
  indent.writeln('// $generatedCodeWarning');
  indent.writeln('// $seeAlsoWarning');
  indent.writeln(
      '// ignore_for_file: public_member_api_docs, non_constant_identifier_names, avoid_as, unused_import');
  indent.writeln('// @dart = ${opt.isNullSafe ? '2.10' : '2.8'}');

  /// 写入导包
  indent.writeln('import \'dart:async\';');
  indent.writeln('import \'package:flutter/services.dart\';');
  indent.writeln(
      'import \'dart:typed_data\' show Uint8List, Int32List, Int64List, Float64List;');
  indent.writeln('');

  final String nullBang = opt.isNullSafe ? '!' : '';
  /// 写入自定义数据结构类
  for(Class klass in root.classes){
    indent.write('class ${klass.name} ');

    ///写入所有属性
    indent.scoped('{', '}', (){
      for(Field field in klass.fields){
        final String datatype = opt.isNullSafe?'${field.dataType}?':'${field.dataType}';
        indent.writeln('${datatype} ${field.name};');
      }
      indent.writeln('// ignore: unused_element');
      ///写入Map转化函数 _toMap
      indent.write('Map<dynamic, dynamic> _toMap() ');
      indent.scoped('{', '}', (){
        indent.writeln(
            'final Map<dynamic, dynamic> pigeonMap = <dynamic, dynamic>{};');
        for(Field field in klass.fields){
          indent.write('pigeonMap[\'${field.name}\'] = ');
          if (customClassNames.contains(field.dataType)) {
            indent.addln(
                '${field.name} == null ? null : ${field.name}$nullBang._toMap();');
          } else {
            indent.addln('${field.name};');
          }
        }
        indent.writeln('return pigeonMap;');
      });

      indent.writeln('// ignore: unused_element');
      ///写入从Map创建对象的静态函数 _fromMap
      indent.write(
          'static ${klass.name} _fromMap(Map<dynamic, dynamic> pigeonMap) ');
      indent.scoped('{', '}', () {
        indent.writeln('final ${klass.name} result = ${klass.name}();');
        for (Field field in klass.fields) {
          indent.write('result.${field.name} = ');
          if (customClassNames.contains(field.dataType)) {
            indent.addln(
                'pigeonMap[\'${field.name}\'] != null ? ${field.dataType}._fromMap(pigeonMap[\'${field.name}\']) : null;');
          } else {
            indent.addln('pigeonMap[\'${field.name}\'];');
          }
        }
        indent.writeln('return result;');
      });
    });
  }

  ///写入定义的API

  for(Api api in root.apis){
    if(api.location == ApiLocation.host){
      ///写入宿主（原生）提供的API
      _writeHostApi(opt, indent, api);
      ///如果设置了dartHostTestHandler，则在Flutter侧创建对应函数
      if(api.dartHostTestHandler != null){
        final Api mockApi = Api(
            name: api.dartHostTestHandler,
            methods: api.methods,
            location: ApiLocation.flutter);
        _writeFlutterApi(opt, indent, mockApi,
            channelNameFunc: (Method func) => makeChannelName(api, func),
            isMockHandler: true);
      }

    }else if (api.location == ApiLocation.flutter) {
      ///写入Flutter提供的API
      _writeFlutterApi(opt, indent, api);
    }
  }


}