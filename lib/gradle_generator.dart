import 'dart:io';

import 'ast.dart';
import 'generator_tools.dart';

class GradleOptions{
  String buildGradle;
  String configName;
  static final String DEFAULT_BUILD = 'build.gradle';
}

void generateGradle(GradleOptions options, Root root, StringSink sink) {
  final Indent indent = Indent(sink);
  ///写入Gradle配置
  indent.writeln('');
  indent.format(root.dependence.androidDependence);
  indent.addln('');

  File build = File(options.buildGradle);
  build.writeAsString('\napply from:\'./${options.configName}\'',mode: FileMode.append);
}