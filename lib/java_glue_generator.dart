import 'ast.dart';
import 'generator_tools.dart';

void generateGlue(GlueClass glue, StringSink sink) {
  final Indent indent = Indent(sink);
  ///写入Gradle配置
  indent.writeln('');
  indent.format(glue.code);
  indent.addln('');
}