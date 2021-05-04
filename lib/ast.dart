//copy from pigeon

import 'package:flagon/flagon_lib.dart';

enum ApiLocation{
  host,
  flutter,
}

class Platform{
  static final String PLATFORM_ANDROID = 'Android';
  static final String PLATFORM_IOS = 'iOS';
  static final String PLATFORM_FLUTTER = 'Flutter';
}

class Node{}

class Method extends Node{

  Method({this.name, this.returnType, this.argType, this.isAsynchronous}) {

  }

  String name;

  String returnType;

  String argType;

  bool isAsynchronous;

}

//API接口实现类需要额外的导入。
class Import extends Node{
  Import({this.importStatement,this.platform});
  String importStatement;
  String platform;
}
//API接口实现类函数体。
class MethodBody extends Node{
  MethodBody({this.platform,this.method,this.code});

  String method;

  String platform;

  String code;
}
//胶水层类。原生库和API实现类中间可能需要的胶水实现。
class GlueClass extends Node{
  GlueClass({this.platform,this.fileName,this.code});

  String platform;

  String fileName;

  String code;
}

class Api extends Node{
  String name;
  ApiLocation location;
  List<Method> methods;
  String dartHostTestHandler;
  List<MethodBody> codes;
  List<Import> statements;

  Api({this.name ,this.location, this.methods, this.dartHostTestHandler, this.codes, this.statements}){}

}

class Field extends Node{
  String name;
  String dataType;
  Field({this.name, this.dataType}){

  }

  @override
  String toString() {
    return '(Field name:$name)';
  }
}

class Class extends Node{
  String name;
  List<Field> fields;
  Class({this.name, this.fields}){}

  @override
  String toString() {
    // TODO: implement toString
    return '(Class name:$name fields:$fields)';
  }

}

class Dependence extends Node{
  static final String FIELD_ANDROID = 'androidDependencies';
  static final String FIELD_IOS = 'iOSDependencies';

  String androidDependence;
  String iOSDependence;

  Dependence({this.androidDependence,this.iOSDependence});

  @override
  String toString() {
    // TODO: implement toString
    return '(Dependence androidDependence:$androidDependence iOSDependence:$iOSDependence)';
  }
}

class Root extends Node{
  List<Api> apis;
  List<Class> classes;
  Dependence dependence;
  List<GlueClass> glues;

  Root({this.apis, this.classes, this.dependence, this.glues});

  @override
  String toString() {
    return '(Root classes:$classes apis:$apis)';
  }
}