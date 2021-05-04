//copy from pigeon
import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';

import 'package:flagon/ast.dart';

const String flagonVersion = '0.0.1';

String readStdin(){
  final List<int> bytes = <int>[];
  int byte = stdin.readByteSync();
  while(byte>0){
    bytes.add(byte);
    byte = stdin.readByteSync();
  }

  return utf8.decode(bytes);

}

//用来管理代码缩进
class Indent {
  Indent(this._sink);

  int count = 0;
  final StringSink _sink;

  final String newline = '\n';

  final String tab = '  ';

  void inc(){
    count++;
  }

  void dec(){
    count--;
  }

  String str(){
    String result = '';
    for(int i=0;i<count;i++){
      result += tab;
    }
    return result;
  }

  void format(String input){
    for(String line in input.split('\n')){
      writeln(line.replaceAll('\t', tab));
    }
  }

  void scoped(String begin, String end, Function func){
    if(begin != null){
      _sink.write(begin + newline);
    }
    inc();
    func();
    dec();
    if(end != null){
      _sink.write(str() + end + newline);
    }
  }

  void writeln(String str){
    _sink.write(this.str() + str + newline);
  }

  void write(String str){
    _sink.write(this.str() + str);
  }

  void addln(String str){
    _sink.write(str + newline);
  }

  void add(String str){
    _sink.write(str);
  }
}

String makeChannelName(Api api,Method func){
  return 'com.profound.flagon.${api.name}.${func.name}';
}

class HostDatatype{

  HostDatatype({this.datatype, this.isBuiltin});
  final String datatype;
  final bool isBuiltin;
}

HostDatatype getHostDatatype(Field field, List<Class> classes, String Function(String) builtinResolver,
    {String Function(String) customResolver}){
  final String datatype = builtinResolver(field.dataType);
  if(datatype == null){
    if(classes.map((Class x) => x.name).contains(field.dataType)){
      final String customName = customResolver != null
          ? customResolver(field.dataType)
          : field.dataType;
      return HostDatatype(datatype:customName,isBuiltin:false);
    }else{
      throw Exception('unrecognized datatype for field:"${field.name}" of type:"${field.dataType}"');
    }
  }else{
    return HostDatatype(datatype: datatype,isBuiltin: true);
  }
}

const String generatedCodeWarning = 'Auto generated from flagon (v$flagonVersion), do not edit directly.';

const String seeAlsoWarning = 'See also: https://pub.dev/packages/pigeon';

class Keys{
  static const String result = 'result';
  static const String error = 'error';
  static const String errorCode = 'code';
  static const String errorMessage = 'message';
  static const String errorDetails = 'details';
}

bool isVoid(TypeMirror type){
  return MirrorSystem.getName(type.simpleName) == 'void';
}






