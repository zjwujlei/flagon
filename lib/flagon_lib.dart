//copy from pigeon
import 'dart:io';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:flagon/gradle_generator.dart';
import 'package:flagon/java_glue_generator.dart';
import 'package:flagon/java_implement_generator.dart';
import 'package:path/path.dart';

import 'ast.dart';
import 'dart_generator.dart';
import 'generator_tools.dart';
import 'java_generator.dart';
import 'objc_generator.dart';

const List<String> _validTypes = <String>[
  'String',
  'bool',
  'int',
  'double',
  'Uint8List',
  'Int32List',
  'Int64List',
  'Float64List',
  'List',
  'Map',
];

class _Asynchronous{
  const _Asynchronous();
}

const _Asynchronous async = _Asynchronous();

class HostApi{
  const HostApi({this.dartHostTestHandler});

  final String dartHostTestHandler;
}

class FlutterApi{
  const FlutterApi();
}

///标记功能实现的import
class ImplImport{
  const ImplImport({this.statement,this.platform});
  final String statement;
  final String platform;
}

class ApiImplExt{
  const ApiImplExt({this.code,this.platform});
  final String code;
  final String platform;
}

///标记功能API的具体实现
class ApiImpl{
  const ApiImpl({this.code,this.platform});
  final String code;
  final String platform;
}

///标记依赖库配置
class DependenceLibrary{
  const DependenceLibrary();
}
///用于注解API实现胶水层代码。
class ApiGlue{
  const ApiGlue({this.platform,this.fileName});
  final String platform;
  final String fileName;
}

class Error{

  Error({this.message, this.filename, this.lineNumber});

  String message;
  String filename;
  int lineNumber;

  @override
  String toString() {
    return '(Error message:"$message" filename:"$filename" lineNumber:$lineNumber)';
  }

}

ApiImplExt _getApiImplExt(MethodMirror methodMirror){
  for(InstanceMirror instance in methodMirror.metadata){
    if(instance.reflectee is ApiImplExt){
      return instance.reflectee;
    }
  }
  return null;
}

Iterable<ApiImpl> _getApiImpl(MethodMirror methodMirror) sync* {
  print('size:${methodMirror.metadata.length}');
  for(InstanceMirror instance in methodMirror.metadata){
    if(instance.reflectee is ApiImpl){
      yield instance.reflectee;
    }
  }
}

bool _isGlue(VariableMirror variableMirror){
  for(InstanceMirror instance in variableMirror.metadata){
    if(instance.reflectee is ApiGlue){
      return true;
    }
  }
  return false;
}
ApiGlue _getGlue(VariableMirror variableMirror){
  for(InstanceMirror instance in variableMirror.metadata){
    if(instance.reflectee is ApiGlue){
      return instance.reflectee;
    }
  }
  return null;
}


bool _isDependence(ClassMirror classMirror){
  for(InstanceMirror mirror in classMirror.metadata){
    if(mirror.reflectee is DependenceLibrary){
      return true;
    }
  }
  return false;
}

bool _isApi(ClassMirror classMirror){
  return classMirror.isAbstract && (_getHostApi(classMirror) != null || _isFlutterApi(classMirror));
}

HostApi _getHostApi(ClassMirror apiMirror){
  for(InstanceMirror instance in apiMirror.metadata){
    if(instance.reflectee is HostApi){
      return instance.reflectee;
    }
  }
  return null;
}

bool _isFlutterApi(ClassMirror apiMirror){
  return apiMirror.metadata.any((InstanceMirror instance) => instance.reflectee is FlutterApi);
}


class FlagonOptions {

  String input;
  String dartOut;
  String objcHeaderOut;
  String objcSourceOut;
  ObjcOptions objcOptions = ObjcOptions();
  String javaOut;
  JavaOptions javaOptions = JavaOptions();
  DartOptions dartOptions = DartOptions();
  String gradleOut;
  String buildGradle;
  GradleOptions gradleOptions = GradleOptions();

}

class ParseResults{
  ParseResults({this.root, this.errors});
  final Root root;
  final List<Error> errors;
}

class Flagon{
  static Flagon setup(){
    return Flagon();
  }
  ///反射取出所有属性
  Class _parseClassMirror(ClassMirror klassMirror){
    final List<Field> fields = <Field>[];
    for(DeclarationMirror declaration in klassMirror.declarations.values){
      if(declaration is VariableMirror){
        fields.add(Field()
          ..name = MirrorSystem.getName(declaration.simpleName)
          ..dataType = MirrorSystem.getName(declaration.type.simpleName)
        );
      }
    }
    ///创建对应的Class节点。
    final Class klass = Class()
      ..name = MirrorSystem.getName(klassMirror.simpleName)
      ..fields = fields;

    return klass;
  }

  Iterable<Class> _parseClassMirrors(Iterable<ClassMirror> mirrors) sync* {
    for(ClassMirror mirror in mirrors){
      yield _parseClassMirror(mirror);
      ///对于属性是自定义类型的，也需要进行解析。
      final Iterable<ClassMirror> nestMirrors = mirror.declarations.values
          .whereType<VariableMirror>()
          .map((VariableMirror mirror) => mirror.type)
          .whereType<ClassMirror>()
          .where((ClassMirror mirror) => !_validTypes.contains(MirrorSystem.getName(mirror.simpleName)));
      for(ClassMirror nestMirror in nestMirrors){
        yield _parseClassMirror(nestMirror);
      }
    }
  }

  ///根据getKey的结果进行去重
  Iterable<T> _unique<T,U>(Iterable<T> iter, U Function(T val) getKey) sync* {
    final Set<U> seed = <U>{};
    for(T t in iter){
      if(!seed.contains(getKey(t))){
        yield t;
      }
    }
  }

  ParseResults parse(List<Type> types){
    final Root root = Root();
    Set<ClassMirror> classes = <ClassMirror>{};
    List<ClassMirror> apis = <ClassMirror>[];

    for(Type type in types){
      final ClassMirror mirror = reflectClass(type);
      ///理论上都是API
      if(_isApi(mirror)){
        apis.add(mirror);
      }else{
        classes.add(mirror);
      }
    }

    ///将API的返回值和入参加入到classes中
    for(ClassMirror apiMirror in apis){
      for(DeclarationMirror declaration in apiMirror.declarations.values){
        if((declaration is MethodMirror) && !declaration.isConstructor){
          if(!isVoid(declaration.returnType)){
            classes.add(declaration.returnType);
          }
          
          if(declaration.parameters.isNotEmpty){
            ///入参都需要通过类来进行封装，所以只有一个。
            classes.add(declaration.parameters[0].type);
          }
        }
      }
    }

    ///整体逻辑看下来classes都是在API的出参入参中产生的。
    root.classes = _unique(_parseClassMirrors(classes), (Class x)=>x.name).toList();
    root.apis = <Api>[];
    for(ClassMirror apiMirror in  apis){
      final List<Method> functions = <Method>[];
      final List<MethodBody> codes = <MethodBody>[];
      final List<Import> imports = <Import>[];
      print('class:${MirrorSystem.getName(apiMirror.simpleName)}');
      ///处理Import导入代码
      apiMirror.metadata.where((InstanceMirror mirror) {

        return mirror.reflectee is ImplImport;
      } ).forEach((InstanceMirror mirror){
            ImplImport statement = mirror.reflectee as ImplImport;
            print('statement:${statement.statement}, platform:${statement.platform}');
            imports.add(Import(importStatement: statement.statement,platform: statement.platform));
      });
      ///处理API实现类中除了函数实现外其他部分代码
      apiMirror.metadata.where((InstanceMirror mirror) {

        return mirror.reflectee is ApiImplExt;
      } );

      for(DeclarationMirror declaration in apiMirror.declarations.values){
        if(declaration is MethodMirror && !declaration.isConstructor){
          final bool isAsynchronous = declaration.metadata.any((InstanceMirror it) {
            return MirrorSystem.getName(it.type.simpleName) ==
                '${async.runtimeType}';
          });

          if(isAsynchronous){
            print('isAsynchronous method：${MirrorSystem.getName(declaration.simpleName)}');
          }
          functions.add(Method()
            ..name = MirrorSystem.getName(declaration.simpleName)
            ..argType = declaration.parameters.isEmpty
                ? 'void'
                : MirrorSystem.getName(
                declaration.parameters[0].type.simpleName)
            ..returnType =
            MirrorSystem.getName(declaration.returnType.simpleName)
            ..isAsynchronous = isAsynchronous
          );
          print('method:${MirrorSystem.getName(apiMirror.simpleName)}.${MirrorSystem.getName(declaration.simpleName)}');
          Iterable<ApiImpl> impls = _getApiImpl(declaration);
          for(ApiImpl impl in impls){
            print('impl:${impl == null}');
            codes.add(MethodBody(platform: impl.platform,
              method: MirrorSystem.getName(declaration.simpleName),
              code: impl.code
            ));
          }

        }
      }
      final HostApi hostApi = _getHostApi(apiMirror);
      root.apis.add(Api(
          name: MirrorSystem.getName(apiMirror.simpleName),
          location: hostApi != null ? ApiLocation.host : ApiLocation.flutter,
          methods: functions,
          dartHostTestHandler: hostApi?.dartHostTestHandler,
          codes: codes,
          statements: imports));
    }
    final List<Error> validateErrors = _validateAst(root);
    return ParseResults(root: root, errors: validateErrors);
  }
  /// String that describes how the tool is used.
  static String get usage {
    return '''

Pigeon is a tool for generating type-safe communication code between Flutter
and the host platform.

usage: pigeon --input <pigeon path> --dart_out <dart path> [option]*

options:
''' +
        _argParser.usage;
  }

  static final ArgParser _argParser = ArgParser()
    ..addOption('input', help: 'REQUIRED: Path to pigeon file.')
    ..addOption('dart_out',
        help: 'REQUIRED: Path to generated dart source file (.dart).')
    ..addOption('objc_source_out',
        help: 'Path to generated Objective-C source file (.m).')
    ..addOption('java_out', help: 'Path to generated Java file (.java).')
    ..addOption('java_package',
        help: 'The package that generated Java code will be in.')
    ..addFlag('dart_null_safety',
        help: 'Makes generated Dart code have null safety annotations')
    ..addOption('objc_header_out',
        help: 'Path to generated Objective-C header file (.h).')
    ..addOption('objc_prefix',
        help: 'Prefix for generated Objective-C classes and protocols.')
    ..addOption('gradle_out',
        help: 'Path to generated gradle config file (.gradle).');

  /// Convert command-line arugments to [PigeonOptions].
  static FlagonOptions parseArgs(List<String> args) {
    final ArgResults results = _argParser.parse(args);

    final FlagonOptions opts = FlagonOptions();
    opts.input = results['input'];
    opts.dartOut = results['dart_out'];
    opts.objcHeaderOut = results['objc_header_out'];
    opts.objcSourceOut = results['objc_source_out'];
    opts.objcOptions.prefix = results['objc_prefix'];
    opts.javaOut = results['java_out'];
    opts.javaOptions.package = results['java_package'];
    opts.dartOptions.isNullSafe = results['dart_null_safety'];
    opts.gradleOut = results['gradle_out'];
    return opts;
  }

  static Future<void> _runGenerator(
      String output, void Function(IOSink sink) func) async {
    IOSink sink;
    File file;
    if (output == 'stdout') {
      sink = stdout;
    } else {
      file = File(output);
      sink = file.openWrite();
    }
    func(sink);
    await sink.flush();
  }

  List<Error> _validateAst(Root root) {
    final List<Error> result = <Error>[];
    final List<String> customClasses =
    root.classes.map((Class x) => x.name).toList();
    for (Class klass in root.classes) {
      for (Field field in klass.fields) {
        if (!(_validTypes.contains(field.dataType) ||
            customClasses.contains(field.dataType))) {
          result.add(Error(
              message:
              'Unsupported datatype:"${field.dataType}" in class "${klass.name}".'));
        }
      }
    }
    for (Api api in root.apis) {
      for (Method method in api.methods) {
        if (_validTypes.contains(method.argType)) {
          result.add(Error(
              message:
              'Unsupported argument type: "${method.argType}" in API: "${api.name}" method: "${method.name}'));
        }
        if (_validTypes.contains(method.returnType)) {
          result.add(Error(
              message:
              'Unsupported return type: "${method.returnType}" in API: "${api.name}" method: "${method.name}'));
        }
      }
    }

    return result;
  }

  /// Crawls through the reflection system looking for a configurePigeon method and
  /// executing it.
  ///
  /// 在当前的libraries是中查找configurePigeon函数进行调用。可以查阅'dart:mirrors'库了解详细。
  static void _executeConfigurePigeon(FlagonOptions options) {
    for (LibraryMirror library in currentMirrorSystem().libraries.values) {
      for (DeclarationMirror declaration in library.declarations.values) {
        if (declaration is MethodMirror &&
            MirrorSystem.getName(declaration.simpleName) == 'configureFlagon') {
          if (declaration.parameters.length == 1 &&
              declaration.parameters[0].type == reflectClass(FlagonOptions)) {
            library.invoke(declaration.simpleName, <dynamic>[options]);
          } else {
            print('warning: invalid \'configureFlagon\' method defined.');
          }
        }
      }
    }
  }

  /// The 'main' entrypoint used by the command-line tool.  [args] are the
  /// command-line arguments.
  static Future<int> run(List<String> args) async {
    final Flagon pigeon = Flagon.setup();

    ///解析命令行转入参数
    final FlagonOptions options = Flagon.parseArgs(args);
    ///调用配置文件（input指定的dart文件）内的configurePigeon函数设置options。
    _executeConfigurePigeon(options);

    ///如果配置有误输出usage。
    if (options.input == null || options.dartOut == null) {
      print(usage);
      return 0;
    }

    final List<Error> errors = <Error>[];
    ///这个只包含API的类。
    final List<Type> apis = <Type>[];
    final Dependence dep = Dependence();
    final List<GlueClass> glues = <GlueClass>[];

    if (options.objcHeaderOut != null) {
      options.objcOptions.header = basename(options.objcHeaderOut);
    }
    if (options.javaOut != null) {
      options.javaOptions.className = basenameWithoutExtension(options.javaOut);
    }
    if(options.gradleOut != null){
      if(options.buildGradle != null){
        options.gradleOptions.buildGradle = options.buildGradle;
      }else{
        options.gradleOptions.buildGradle = join(dirname(options.gradleOut),GradleOptions.DEFAULT_BUILD);
      }
      options.gradleOptions.configName = basename(options.gradleOut);
    }

    for (LibraryMirror library in currentMirrorSystem().libraries.values) {
      for (DeclarationMirror declaration in library.declarations.values) {
        if (declaration is ClassMirror && _isApi(declaration)) {
          apis.add(declaration.reflectedType);
        }else if(declaration is ClassMirror &&  _isDependence(declaration)){
          dep.androidDependence = declaration.getField(Symbol(Dependence.FIELD_ANDROID)).reflectee.toString();
          dep.iOSDependence = declaration.getField(Symbol(Dependence.FIELD_IOS)).reflectee.toString();
          
        }else if(declaration is VariableMirror && declaration.isConst && declaration.owner is LibraryMirror){
          ApiGlue glue = _getGlue(declaration);
          if(glue != null){
            glues.add(GlueClass(
              platform : glue.platform,
              fileName: glue.fileName,
              code:(declaration.owner as LibraryMirror).getField(declaration.simpleName).reflectee.toString()
            ));
          }
        }
      }

    }

    if (apis.isNotEmpty) {
      ///以有apis未准。数据结构类（Class节点）已API的出参入参未准。
      final ParseResults parseResults = pigeon.parse(apis);
      parseResults.root.dependence = dep;
      parseResults.root.glues = glues;
      for (Error err in parseResults.errors) {
        errors.add(Error(message: err.message, filename: options.input));
      }

      ///后面就是调用 generator生成代码。
      if (options.dartOut != null) {
        await _runGenerator(
            options.dartOut,
                (StringSink sink) =>
                generateDart(options.dartOptions, parseResults.root, sink));
      }
      if (options.objcHeaderOut != null) {
        await _runGenerator(
            options.objcHeaderOut,
                (StringSink sink) => generateObjcHeader(
                options.objcOptions, parseResults.root, sink));
      }
      if (options.objcSourceOut != null) {
        await _runGenerator(
            options.objcSourceOut,
                (StringSink sink) => generateObjcSource(
                options.objcOptions, parseResults.root, sink));
      }
      if (options.javaOut != null) {
        await _runGenerator(
            options.javaOut,
                (StringSink sink) =>
                generateJava(options.javaOptions, parseResults.root, sink));
      }

      ///生成具体实现类

      List<Api> codes = parseResults.root.apis
          .where((Api api) {
            print('api:${api.name} codes:${api.codes != null && api.codes.isNotEmpty}');
            return api.codes != null && api.codes.isNotEmpty;
          }).toList();
      for(Api code in codes){
        switch(code.location){
          case ApiLocation.flutter:
            //TODO: for flutter
            break;

          case ApiLocation.host:
            //TODO: for ios

            String dir = options.javaOut.substring(0,options.javaOut.lastIndexOf('/'));
            String implOut = '${dir}/${code.name}Impl.java';
            print('implOut ${implOut}');
            await _runGenerator(
                implOut,
                    (StringSink sink) =>
                    generateJavaImpl(options.javaOptions, code, sink));
            break;
        }

      }

      ///处理Android库导入
      if(options.gradleOut != null){
        await _runGenerator(
            options.gradleOut,
                (StringSink sink) =>
                    generateGradle(options.gradleOptions, parseResults.root, sink));
      }

      ///处理胶水层代码生成
      for(GlueClass glue in glues){
        if(glue.platform == Platform.PLATFORM_ANDROID){
          String dir = options.javaOut.substring(0,options.javaOut.lastIndexOf('/'));
          String out = '${dir}/${glue.fileName}';
          await _runGenerator(
              out,
                  (StringSink sink) =>
                  generateGlue(glue, sink));
        }else if(glue.platform == Platform.PLATFORM_IOS){
          //TODO:
        }
      }


      glues.where((GlueClass glue)=> (glue.platform == Platform.PLATFORM_ANDROID
          && options.javaOut != null)
          || glue.platform == Platform.PLATFORM_IOS)
          .forEach((GlueClass glue){


      });


    } else {
      errors.add(Error(message: 'No pigeon classes found, nothing generated.'));
    }

    printErrors(errors);

    return errors.isNotEmpty ? 1 : 0;
  }

  /// Print a list of errors to stderr.
  static void printErrors(List<Error> errors) {
    for (Error err in errors) {
      if (err.filename != null) {
        if (err.lineNumber != null) {
          stderr.writeln(
              'Error: ${err.filename}:${err.lineNumber}: ${err.message}');
        } else {
          stderr.writeln('Error: ${err.filename}: ${err.message}');
        }
      } else {
        stderr.writeln('Error: ${err.message}');
      }
    }
  }

}