import 'ast.dart';
import 'generator_tools.dart';
import 'java_implement_generator.dart';

const Map<String, String> _javaTypeForDartTypeMap = <String, String>{
  'bool':'Boolean',
  'int':'Long',
  'String':'String',
  'double':'Double',
  'Uint8List':'byte[]',
  'Int32List':'int[]',
  'Int64List':'long[]',
  'Float64List':'double[]',
  'List':'ArrayList',
  'Map':'HashMap',
};

class JavaOptions {
  String className;
  String package;
}

void _writeHostApi(Indent indent, Api api){
  assert(api.location == ApiLocation.host);
  ///如果有异步函数，定义响应封装接口。
  if(api.methods.any((Method it) => it.isAsynchronous)){
    indent.write('public interface Result<T> ');
    indent.scoped('{', '}', (){
      indent.writeln('void success(T result);');
    });
    indent.addln('');
  }
  ///对于宿主（原生）提供的能力，pigeon会生成对应的接口定义。宿主需要进行实现并通过静态函数setup()进行中注入。
  indent.writeln(
      '/** Generated interface from Pigeon that represents a handler of messages from Flutter.*/');
  indent.write('public interface ${api.name} ');
  ///将宿主需要提供的能力定义成接口函数
  indent.scoped('{', '}', (){
    for(Method method in api.methods){
      final String returnType = method.isAsynchronous?'void':method.returnType;
      final List<String> argSignature = <String>[];
      if(method.argType != 'void'){
        argSignature.add('${method.argType} arg');
      }
      if(method.isAsynchronous){
        argSignature.add('Result<${method.returnType}> result');
      }
      indent.writeln('$returnType ${method.name}(${argSignature.join(', ')});');
    }
    indent.addln('');
    ///写入setup（）静态函数用户注入实例。
    indent.writeln(
        '/** Sets up an instance of `${api.name}` to handle messages through the `binaryMessenger` */');
    indent.write(
        'static void setup(BinaryMessenger binaryMessenger, ${api.name} api) ');
    indent.scoped('{', '}', (){
      for (Method method in api.methods) {
        final String channelName = makeChannelName(api, method);
        indent.addln('');
        indent.scoped('{', '}', (){
          indent.writeln('BasicMessageChannel<Object> channel =');
          indent.inc();
          indent.inc();
          indent.writeln(
              'new BasicMessageChannel<>(binaryMessenger, "$channelName", new StandardMessageCodec());');
          indent.dec();
          indent.dec();
          indent.write('if (api != null) ');
          indent.scoped('{', '} else {', () {
            indent.write('channel.setMessageHandler((message, reply) -> ');
            indent.scoped('{', '});', ()
            {
              final String argType = method.argType;
              final String returnType = method.returnType;
              indent.writeln(
                  'HashMap<String, HashMap> wrapped = new HashMap<>();');
              indent.write('try ');
              indent.scoped('{', '}', () {
                final List<String> methodArgument = <String>[];
                if (argType != 'void') {
                  indent.writeln('@SuppressWarnings("ConstantConditions")');
                  indent.writeln(
                      '$argType input = $argType.fromMap((HashMap)message);');
                  methodArgument.add('input');
                }
                if (method.isAsynchronous) {
                  methodArgument.add(
                    'result -> { '
                        'wrapped.put("${Keys.result}", result.toMap()); '
                        'reply.reply(wrapped); '
                        '}',
                  );
                }
                final String call =
                    'api.${method.name}(${methodArgument.join(', ')})';
                if (method.isAsynchronous) {
                  indent.writeln('$call;');
                } else if (method.returnType == 'void') {
                  indent.writeln('$call;');
                  indent.writeln('wrapped.put("${Keys.result}", null);');
                } else {
                  indent.writeln('$returnType output = $call;');
                  indent.writeln(
                      'wrapped.put("${Keys.result}", output.toMap());');
                }
              });
              indent.write('catch (Exception exception) ');
              indent.scoped('{', '}', () {
                indent.writeln(
                    'wrapped.put("${Keys.error}", wrapError(exception));');
                if (method.isAsynchronous) {
                  indent.writeln('reply.reply(wrapped);');
                }
              });
              if (!method.isAsynchronous) {
                indent.writeln('reply.reply(wrapped);');
              }
            });
          });
          indent.scoped(null, '}', () {
            indent.writeln('channel.setMessageHandler(null);');
          });
        });

      }
    });
  });

}

void _writeFlutterApi(Indent indent, Api api) {
  assert(api.location == ApiLocation.flutter);
  indent.writeln(
      '/** Generated class from Pigeon that represents Flutter messages that can be called from Java.*/');
  indent.write('public static class ${api.name} ');
  indent.scoped('{', '}', () {
    indent.writeln('private final BinaryMessenger binaryMessenger;');
    indent.write('public ${api.name}(BinaryMessenger argBinaryMessenger)');
    indent.scoped('{', '}', () {
      indent.writeln('this.binaryMessenger = argBinaryMessenger;');
    });
    indent.write('public interface Reply<T> ');
    indent.scoped('{', '}', () {
      indent.writeln('void reply(T reply);');
    });
    for (Method func in api.methods) {
      final String channelName = makeChannelName(api, func);
      final String returnType =
      func.returnType == 'void' ? 'Void' : func.returnType;
      String sendArgument;
      if (func.argType == 'void') {
        indent.write('public void ${func.name}(Reply<$returnType> callback) ');
        sendArgument = 'null';
      } else {
        indent.write(
            'public void ${func.name}(${func.argType} argInput, Reply<$returnType> callback) ');
        sendArgument = 'inputMap';
      }
      indent.scoped('{', '}', () {
        indent.writeln('BasicMessageChannel<Object> channel =');
        indent.inc();
        indent.inc();
        indent.writeln(
            'new BasicMessageChannel<>(binaryMessenger, "$channelName", new StandardMessageCodec());');
        indent.dec();
        indent.dec();
        if (func.argType != 'void') {
          indent.writeln('HashMap inputMap = argInput.toMap();');
        }
        indent.write('channel.send($sendArgument, channelReply -> ');
        indent.scoped('{', '});', () {
          if (func.returnType == 'void') {
            indent.writeln('callback.reply(null);');
          } else {
            indent.writeln('HashMap outputMap = (HashMap)channelReply;');
            indent.writeln('@SuppressWarnings("ConstantConditions")');
            indent.writeln(
                '${func.returnType} output = ${func.returnType}.fromMap(outputMap);');
            indent.writeln('callback.reply(output);');
          }
        });
      });
    }
  });
}

String _makeGetter(Field field) {
  final String uppercased =
      field.name.substring(0, 1).toUpperCase() + field.name.substring(1);
  return 'get$uppercased';
}

String _makeSetter(Field field) {
  final String uppercased =
      field.name.substring(0, 1).toUpperCase() + field.name.substring(1);
  return 'set$uppercased';
}

String _javaTypeForDartType(String datatype) {
  return _javaTypeForDartTypeMap[datatype];
}

String _castObject(Field field, List<Class> classes, String varName) {
  final HostDatatype hostDatatype =
  getHostDatatype(field, classes, _javaTypeForDartType);
  if (field.dataType == 'int') {
    return '($varName == null) ? null : (($varName instanceof Integer) ? (Integer)$varName : (${hostDatatype.datatype})$varName)';
  } else if (!hostDatatype.isBuiltin &&
      classes.map((Class x) => x.name).contains(field.dataType)) {
    return '${hostDatatype.datatype}.fromMap((HashMap)$varName)';
  } else {
    return '(${hostDatatype.datatype})$varName';
  }
}

/// Generates the ".java" file for the AST represented by [root] to [sink] with the
/// provided [options].
void generateJava(JavaOptions options, Root root, StringSink sink) {
  final Set<String> rootClassNameSet =
  root.classes.map((Class x) => x.name).toSet();
  final Indent indent = Indent(sink);
  indent.writeln('// $generatedCodeWarning');
  indent.writeln('// $seeAlsoWarning');
  indent.addln('');
  if (options.package != null) {
    indent.writeln('package ${options.package};');
  }
  indent.addln('');
  indent.writeln('import io.flutter.plugin.common.BasicMessageChannel;');
  indent.writeln('import io.flutter.plugin.common.BinaryMessenger;');
  indent.writeln('import io.flutter.plugin.common.StandardMessageCodec;');
  indent.writeln('import java.util.ArrayList;');
  indent.writeln('import java.util.HashMap;');

  indent.addln('');
  assert(options.className != null);
  indent.writeln('/** Generated class from Pigeon. */');
  indent.writeln('@SuppressWarnings("unused")');
  indent.write('public class ${options.className} ');
  indent.scoped('{', '}', () {
    for (Class klass in root.classes) {
      indent.addln('');
      indent.writeln(
          '/** Generated class from Pigeon that represents data sent in messages. */');
      indent.write('public static class ${klass.name} ');
      indent.scoped('{', '}', () {
        for (Field field in klass.fields) {
          final HostDatatype hostDatatype =
          getHostDatatype(field, root.classes, _javaTypeForDartType);
          indent.writeln('private ${hostDatatype.datatype} ${field.name};');
          indent.writeln(
              'public ${hostDatatype.datatype} ${_makeGetter(field)}() { return ${field.name}; }');
          indent.writeln(
              'public void ${_makeSetter(field)}(${hostDatatype.datatype} setterArg) { this.${field.name} = setterArg; }');
          indent.addln('');
        }
        indent.write('HashMap toMap() ');
        indent.scoped('{', '}', () {
          indent.writeln(
              'HashMap<String, Object> toMapResult = new HashMap<>();');
          for (Field field in klass.fields) {
            final HostDatatype hostDatatype =
            getHostDatatype(field, root.classes, _javaTypeForDartType);
            String toWriteValue = '';
            if (!hostDatatype.isBuiltin &&
                rootClassNameSet.contains(field.dataType)) {
              toWriteValue = '${field.name}.toMap()';
            } else {
              toWriteValue = field.name;
            }
            indent.writeln('toMapResult.put("${field.name}", $toWriteValue);');
          }
          indent.writeln('return toMapResult;');
        });
        indent.write('static ${klass.name} fromMap(HashMap map) ');
        indent.scoped('{', '}', () {
          indent.writeln('${klass.name} fromMapResult = new ${klass.name}();');
          for (Field field in klass.fields) {
            indent.writeln('Object ${field.name} = map.get("${field.name}");');
            indent.writeln(
                'fromMapResult.${field.name} = ${_castObject(field, root.classes, field.name)};');
          }
          indent.writeln('return fromMapResult;');
        });
      });
    }

    for (Api api in root.apis) {
      indent.addln('');
      if (api.location == ApiLocation.host) {
        _writeHostApi(indent, api);
      } else if (api.location == ApiLocation.flutter) {
        _writeFlutterApi(indent, api);
      }
    }

    indent.format('''private static HashMap wrapError(Exception exception) {
\tHashMap<String, Object> errorMap = new HashMap<>();
\terrorMap.put("${Keys.errorMessage}", exception.toString());
\terrorMap.put("${Keys.errorCode}", exception.getClass().getSimpleName());
\terrorMap.put("${Keys.errorDetails}", null);
\treturn errorMap;
}''');
  });
}