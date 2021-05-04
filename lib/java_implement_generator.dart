
import 'package:flagon/java_generator.dart';

import 'ast.dart';
import 'generator_tools.dart';


void generateJavaImpl(JavaOptions options, Api api, StringSink sink) {
  assert(api.location == ApiLocation.host);
  final Indent indent = Indent(sink);
  ///对于宿主（原生）提供的能力，pigeon会生成对应的接口定义。宿主需要进行实现并通过静态函数setup()进行中注入。
  if (options.package != null) {
    indent.writeln('package ${options.package};');
  }
  indent.writeln('');
  api.statements
      .where((Import statement)=>statement.platform == Platform.PLATFORM_ANDROID)
      .forEach((Import statement) => indent.writeln(statement.importStatement));
  indent.writeln('');
  indent.write('public class ${api.name}Impl implements ${options.className}.${api.name}');
  ///将宿主需要提供的能力定义成接口函数
  indent.scoped('{', '}', (){
    for(Method method in api.methods){
      final String returnType = method.isAsynchronous?'void':'${options.className}.${method.returnType}';
      final List<String> argSignature = <String>[];
      if(method.argType != 'void'){
        argSignature.add('${options.className}.${method.argType} arg');
      }
      if(method.isAsynchronous){
        argSignature.add('${options.className}.Result<${options.className}.${method.returnType}> result');
      }
      indent.writeln('@Override');
      indent.writeln('public $returnType ${method.name}(${argSignature.join(', ')})');
      indent.scoped('{', '}', (){
        List<MethodBody> bodies = api.codes.where((MethodBody body)=> body.platform == Platform.PLATFORM_ANDROID && body.method == method.name).toList();
        if(bodies.isNotEmpty){
          indent.format(bodies.first.code);
        }else{
          indent.writeln('//TODO ');
        }
      });
    }
    indent.addln('');
  });

}
