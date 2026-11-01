// android 桥生成器：把注解过的 Kotlin / Dart 方法翻成两个生成类。
//
// 输入（源码里的注解，方向不同）：
//   - Kotlin @DartCall / @DartAsyncCall：Dart → Android，生成 AndroidCall
//   - Kotlin @DartData：过通道的结构体，Dart 侧生成镜像
//   - Dart @KotlinEvent：Android → Dart 事件，生成 AndroidEvent（直接调用该静态方法）
//
// 输出（随源码提交；构建前由 Gradle 调这个脚本重生成，保证与注解一致）：
//   lib/generated/android_call.g.dart
//   lib/generated/android_event.g.dart
//   android/app/src/main/kotlin/io/github/copper/launcher/generated/AndroidCall.g.kt
//   android/app/src/main/kotlin/io/github/copper/launcher/generated/AndroidEvent.g.kt
//
// 跨边界契约写在注解的注释里，这里只是执行方（不重复维护第二份）：
//   调用方向 Dart → Kotlin：
//     channel/DartCall.kt（类型表 / 静态方法 / 参数注入）
//     channel/DartAsyncCall.kt（阻塞语义，类型规则同上）
//     channel/DartData.kt（结构体，定义在 Kotlin）
//   事件方向 Kotlin → Dart：
//     lib/util/host_annotations.dart 的 KotlinEvent（载荷类型表）与 KotlinData（结构体，
//     定义在 Dart，Kotlin 镜像由本脚本生成）
//
// 本脚本负责把那些约束落成代码，并让违规在生成阶段失败（文件:行 + 一句为什么）。
//
// 用法：dart run tool/android_bridge/generate.dart（工作目录 = launcher 根）
import 'dart:io';

/// Dart → Android 通道名（Kotlin 生成物用同一个常量）
const _hostChannel = 'io.github.copper.launcher/android';

/// Android → Dart 事件通道名
const _eventChannel = 'io.github.copper.launcher/flutter';

/// 参数名决定注入：Activity 本身 / 它的应用上下文
const _activityParam = 'activityContext';
const _applicationParam = 'applicationContext';

const _kotlinRoot = 'android/app/src/main/kotlin';
const _kotlinGeneratedDir =
    'android/app/src/main/kotlin/io/github/copper/launcher/generated';
const _dartRoot = 'lib';
const _dartGeneratedDir = 'lib/generated';

void main(List<String> arguments) {
  try {
    final root = _projectRoot();
    final packageName = _packageName(root);
    final dartRoot = Directory('${root.path}/$_dartRoot');
    final calls = <_CallMethod>[];
    final datas = <String, _DataClass>{};
    final events = <_EventMethod>[];
    final dartDatas = <String, _DartDataClass>{};

    for (final file in _filesOf(Directory('${root.path}/$_kotlinRoot'), '.kt')) {
      if (_isGenerated(file.path)) continue;
      _scanKotlin(_KtFile.read(file), calls, datas);
    }
    for (final file in _filesOf(dartRoot, '.dart')) {
      if (_isGenerated(file.path) || file.path.endsWith('.g.dart')) continue;
      _scanDart(file, dartRoot.path, packageName, events, dartDatas);
    }

    _validate(calls, datas, events, dartDatas);

    final outputs = <String, String>{
      '$_dartGeneratedDir/android_call.g.dart': _dartCallFile(calls, datas),
      '$_dartGeneratedDir/android_event.g.dart':
          _dartEventFile(events, dartDatas, packageName),
      '$_kotlinGeneratedDir/AndroidCall.g.kt': _kotlinCallFile(calls, datas),
      '$_kotlinGeneratedDir/AndroidEvent.g.kt':
          _kotlinEventFile(events, dartDatas),
    };
    outputs.forEach((path, content) {
      final file = File('${root.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });

    stdout.writeln(
      'android 桥生成完成：${calls.length} 个调用、${datas.length} 个调用数据类、'
      '${dartDatas.length} 个事件数据类、${events.length} 个事件',
    );
    outputs.keys.forEach(stdout.writeln);
  } on _GenError catch (error) {
    stderr.writeln('android 桥生成失败：${error.message}');
    exitCode = 1;
  }
}

// ── 定位工程 ───────────────────────────────────────────────────

Directory _projectRoot() {
  final candidates = <Directory>[Directory.current];
  if (Platform.script.scheme == 'file') {
    // tool/android_bridge/generate.dart → launcher/
    candidates.add(File.fromUri(Platform.script).parent.parent.parent);
  }
  for (final dir in candidates) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/$_kotlinRoot').existsSync()) {
      return dir;
    }
  }
  throw _GenError(
    '找不到工程根目录（需要含 pubspec.yaml 与 $_kotlinRoot）：${Directory.current.path}',
  );
}

/// pubspec 里的包名：事件生成物要靠它 import 事件所属的库
String _packageName(Directory root) {
  final file = File('${root.path}/pubspec.yaml');
  if (!file.existsSync()) throw _GenError('缺少 pubspec.yaml：${file.path}');
  for (final line in file.readAsLinesSync()) {
    final match = RegExp(r'^name:\s*(\S+)').firstMatch(line);
    if (match != null) return match.group(1)!;
  }
  throw _GenError('pubspec.yaml 里没有 name：${file.path}');
}

bool _isGenerated(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.contains('/generated/');
}

Iterable<File> _filesOf(Directory directory, String extension) sync* {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith(extension)) yield entity;
  }
}

// ── 数据结构 ───────────────────────────────────────────────────

class _GenError implements Exception {
  _GenError(this.message);
  final String message;

  @override
  String toString() => message;
}

enum _CallKind { sync, async }

class _Param {
  _Param(this.name, this.type);

  /// Kotlin 侧是参数名，Dart 事件侧是参数名
  final String name;

  /// Kotlin 类型 / Dart 类型
  final String type;
}

class _CallMethod {
  _CallMethod({
    required this.name,
    required this.kind,
    required this.receiver,
    required this.receiverPackage,
    required this.params,
    required this.returnType,
    required this.location,
  });

  final String name;
  final _CallKind kind;

  /// 静态宿主（object 名）；null = 顶层函数
  final String? receiver;
  final String? receiverPackage;
  final List<_Param> params;
  final String returnType;
  final String location;
}

class _DataClass {
  _DataClass({
    required this.name,
    required this.packageName,
    required this.fields,
    required this.location,
  });

  final String name;
  final String packageName;
  final List<_Param> fields;
  final String location;
}

class _EventMethod {
  _EventMethod({
    required this.name,
    required this.owner,
    required this.library,
    required this.params,
    required this.location,
  });

  final String name;

  /// 静态方法所在的 Dart 类名：生成器直接写 `Owner.name(...)`
  final String owner;

  /// 事件方法所属的库（`package:copper_launcher/...`）
  final String library;
  final List<_Param> params;
  final String location;

  String get target => '$owner.$name';
}

/// Dart 侧声明的事件载荷结构体（@KotlinData）：Kotlin 镜像由生成器产出
class _DartDataClass {
  _DartDataClass({
    required this.name,
    required this.library,
    required this.fields,
    required this.location,
  });

  final String name;

  /// 声明所在的库（android_event.g.dart 要 import 它）
  final String library;
  final List<_Param> fields;
  final String location;
}

class _Container {
  _Container(this.kind, this.name, this.start, this.end);
  final String kind;
  final String name;
  final int start;
  final int end;
}

class _KtFile {
  _KtFile({
    required this.path,
    required this.packageName,
    required this.source,
    required this.code,
    required this.lineStarts,
  });

  factory _KtFile.read(File file) {
    final source = file.readAsStringSync();
    final packageMatch =
        RegExp(r'^\s*package\s+([\w.]+)', multiLine: true).firstMatch(source);
    return _KtFile(
      path: file.path,
      packageName: packageMatch?.group(1) ?? '',
      source: source,
      code: _stripCode(source),
      lineStarts: _lineStarts(source),
    );
  }

  final String path;
  final String packageName;
  final String source;

  /// 注释 / 字符串已换成空格（换行保留），偏移与 [source] 对齐
  final String code;
  final List<int> lineStarts;

  String locationOf(int offset) => '$path:${_lineOf(lineStarts, offset)}';
}

// ── Kotlin 扫描 ──────────────────────────────────────────────

void _scanKotlin(
  _KtFile file,
  List<_CallMethod> calls,
  Map<String, _DataClass> datas,
) {
  final code = file.code;
  final containers = _containersOf(code);

  for (final match in RegExp(r'\bfun\b').allMatches(code)) {
    final annotations = _annotationsBefore(code, match.start);
    final isSync = annotations.contains('DartCall');
    final isAsync = annotations.contains('DartAsyncCall');
    if (!isSync && !isAsync) continue;
    if (isSync && isAsync) {
      throw _GenError(
        '${file.locationOf(match.start)}：@DartCall 与 @DartAsyncCall 不能同时标在同一个方法上',
      );
    }

    final signature = _parseFunction(file, match.start);
    if (signature.receiver != null) {
      throw _GenError(
        '${file.locationOf(match.start)}：被调用方必须是静态方法（object / companion object / 顶层），'
        '扩展函数 ${signature.receiver}.${signature.name} 不支持',
      );
    }

    final container = _innermostContainer(containers, match.start);
    if (container != null &&
        container.kind != 'object' &&
        container.kind != 'companion') {
      throw _GenError(
        '${file.locationOf(match.start)}：被调用方必须是静态方法（object / companion object / 顶层），'
        '${signature.name} 在 ${container.kind} ${container.name} 的实例作用域里',
      );
    }
    if (container != null) {
      final outer = _innermostContainer(containers, container.start);
      if (outer != null) {
        throw _GenError(
          '${file.locationOf(match.start)}：不支持嵌套 object（${outer.name}.${container.name}），'
          '把被调用方法放到顶层 object 里',
        );
      }
    }

    calls.add(
      _CallMethod(
        name: signature.name,
        kind: isAsync ? _CallKind.async : _CallKind.sync,
        receiver: container?.name,
        receiverPackage: container == null ? null : file.packageName,
        params: signature.params,
        returnType: signature.returnType,
        location: file.locationOf(match.start),
      ),
    );
  }

  for (final match in RegExp(r'@DartData\b').allMatches(code)) {
    final classMatch =
        RegExp(r'\bclass\s+([A-Za-z_]\w*)').firstMatch(code.substring(match.end));
    if (classMatch == null) {
      throw _GenError(
        '${file.locationOf(match.start)}：@DartData 下面没有紧跟 class 声明',
      );
    }
    final name = classMatch.group(1)!;
    if (_innermostContainer(containers, match.start) != null) {
      throw _GenError(
        '${file.locationOf(match.start)}：@DartData $name 必须是顶层 class（镜像要生成到顶层）',
      );
    }
    final classStart = match.end + classMatch.end;
    final open = _nextSignificant(code, classStart);
    if (open >= code.length || code[open] != '(') {
      throw _GenError(
        '${file.locationOf(match.start)}：@DartData $name 需要主构造参数（字段名就是 Dart 字段名）',
      );
    }
    final close = _matchPair(code, open, '(', ')');
    final fields = _splitTopLevel(code.substring(open + 1, close))
        .where((it) => it.trim().isNotEmpty)
        .map(_parseParam)
        .toList();
    if (fields.isEmpty) {
      throw _GenError(
        '${file.locationOf(match.start)}：@DartData $name 至少需要一个字段',
      );
    }
    for (final field in fields) {
      if (!_isFieldType(field.type)) {
        throw _GenError(
          '${file.locationOf(match.start)}：@DartData $name.${field.name} 的类型 '
          '${field.type} 不支持（字段只能是基础类型 / List<String>，不能嵌套结构体）',
        );
      }
    }
    if (datas.containsKey(name)) {
      throw _GenError(
        '${file.locationOf(match.start)}：@DartData $name 重复定义'
        '（另一处在 ${datas[name]!.location}）',
      );
    }
    datas[name] = _DataClass(
      name: name,
      packageName: file.packageName,
      fields: fields,
      location: file.locationOf(match.start),
    );
  }
}

/// 可以跨通道的值类型（调用参数 / 返回值 / 结构体字段）
const _valueTypes = {
  'String',
  'String?',
  'Boolean',
  'Boolean?',
  'Int',
  'Int?',
  'Long',
  'Long?',
  'Double',
  'Double?',
  'List<String>',
  'List<String>?',
  'Array<String>',
  'Unit',
};

/// 结构体字段：不能嵌套结构体
bool _isFieldType(String type) => _valueTypes.contains(type) && type != 'Unit';

bool _isValueType(String type, Map<String, _DataClass> datas) =>
    _valueTypes.contains(type) || _dataOf(type, datas) != null;

class _FnSignature {
  _FnSignature({
    required this.name,
    required this.receiver,
    required this.params,
    required this.returnType,
  });

  final String name;
  final String? receiver;
  final List<_Param> params;
  final String returnType;
}

_FnSignature _parseFunction(_KtFile file, int funStart) {
  final code = file.code;
  var cursor = funStart + 3; // 跳过 fun
  cursor = _skipWhitespace(code, cursor);

  // 泛型形参 fun <T> name(...)
  if (cursor < code.length && code[cursor] == '<') {
    cursor = _skipWhitespace(code, _matchPair(code, cursor, '<', '>') + 1);
  }

  // 名字（可能带接收者：Type.name）
  final parts = <String>[];
  while (true) {
    final match = RegExp(r'[A-Za-z_]\w*|`[^`]*`').matchAsPrefix(code, cursor);
    if (match == null) {
      throw _GenError('${file.locationOf(funStart)}：解析不了函数声明');
    }
    parts.add(match.group(0)!.replaceAll('`', ''));
    cursor = _skipWhitespace(code, match.end);
    if (cursor < code.length && code[cursor] == '.') {
      cursor = _skipWhitespace(code, cursor + 1);
      continue;
    }
    break;
  }
  if (cursor >= code.length || code[cursor] != '(') {
    throw _GenError(
      '${file.locationOf(funStart)}：${parts.last} 的声明里找不到参数列表',
    );
  }

  final close = _matchPair(code, cursor, '(', ')');
  final params = _splitTopLevel(code.substring(cursor + 1, close))
      .where((it) => it.trim().isNotEmpty)
      .map(_parseParam)
      .toList();

  var returnType = 'Unit';
  final afterParams = _skipWhitespace(code, close + 1);
  if (afterParams < code.length && code[afterParams] == ':') {
    final start = _skipWhitespace(code, afterParams + 1);
    final end = _returnTypeEnd(code, start);
    returnType = _normalizeType(code.substring(start, end));
  }

  return _FnSignature(
    name: parts.last,
    receiver: parts.length > 1 ? parts[parts.length - 2] : null,
    params: params,
    returnType: returnType,
  );
}

/// 返回类型写到 `{` / `=` / 行尾为止（类型里可能有 `<...>`）
int _returnTypeEnd(String code, int start) {
  var i = start;
  var angle = 0;
  var paren = 0;
  while (i < code.length) {
    final c = code[i];
    if (c == '\n' && angle == 0 && paren == 0) return i;
    if (c == '<') angle++;
    if (c == '>' && angle > 0) angle--;
    if (c == '(') paren++;
    if (c == ')' && paren > 0) paren--;
    if ((c == '{' || c == '=') && angle == 0 && paren == 0) return i;
    i++;
  }
  return i;
}

_Param _parseParam(String raw) {
  final text = raw.trim();
  final colon = _topLevelIndexOf(text, ':');
  if (colon < 0) {
    throw _GenError('参数缺少类型标注：$text');
  }
  final namePart = text.substring(0, colon).trim();
  final declaration = text.substring(colon + 1);
  final equals = _topLevelIndexOf(declaration, '=');
  final type = _normalizeType(
    equals < 0 ? declaration : declaration.substring(0, equals),
  );
  final nameTokens = namePart.split(RegExp(r'\s+'));
  final name = nameTokens.last.replaceAll('`', '');
  return _Param(name, type);
}

String _normalizeType(String raw) => raw
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'\s*([<>?,])\s*'), (match) => match.group(1)!)
    .trim();

int _topLevelIndexOf(String text, String target) {
  var angle = 0;
  var paren = 0;
  var bracket = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '<') angle++;
    if (c == '>' && angle > 0) angle--;
    if (c == '(') paren++;
    if (c == ')' && paren > 0) paren--;
    if (c == '[') bracket++;
    if (c == ']' && bracket > 0) bracket--;
    if (c == target && angle == 0 && paren == 0 && bracket == 0) return i;
  }
  return -1;
}

List<String> _splitTopLevel(String text) {
  final parts = <String>[];
  var angle = 0;
  var paren = 0;
  var bracket = 0;
  var brace = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '<') angle++;
    if (c == '>' && angle > 0) angle--;
    if (c == '(') paren++;
    if (c == ')' && paren > 0) paren--;
    if (c == '[') bracket++;
    if (c == ']' && bracket > 0) bracket--;
    if (c == '{') brace++;
    if (c == '}' && brace > 0) brace--;
    if (c == ',' && angle == 0 && paren == 0 && bracket == 0 && brace == 0) {
      parts.add(text.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(text.substring(start));
  return parts;
}

/// 声明（object / companion object / class / interface）的 body 范围
List<_Container> _containersOf(String code) {
  final result = <_Container>[];
  final pattern = RegExp(r'\b(companion\s+object|object|class|interface)\b');
  for (final match in pattern.allMatches(code)) {
    final kind =
        match.group(1)!.startsWith('companion') ? 'companion' : match.group(1)!;
    var name = '';
    if (kind != 'companion') {
      final nameMatch =
          RegExp(r'^\s*([A-Za-z_]\w*)').firstMatch(code.substring(match.end));
      if (nameMatch == null) continue;
      name = nameMatch.group(1)!;
    }
    final brace = _bodyBrace(code, match.end);
    if (brace == null) continue;
    final end = _matchPair(code, brace, '{', '}');
    result.add(_Container(kind, name, brace, end));
  }
  return result;
}

/// 花括号 body 的位置；没有 body 的声明（data class、`x::class`）返回 null
int? _bodyBrace(String code, int from) {
  var i = from;
  var paren = 0;
  var angle = 0;
  var bracket = 0;
  while (i < code.length) {
    final c = code[i];
    if (c == '\n' && paren == 0 && angle == 0 && bracket == 0) {
      final previous = _lastSignificant(code, i - 1, from);
      if (previous == null || !':,(<'.contains(previous)) return null;
    }
    if (c == '{' && paren == 0 && angle == 0 && bracket == 0) return i;
    if (c == '}' || c == ';') return null;
    if (c == '(') paren++;
    if (c == ')' && paren > 0) paren--;
    if (c == '<') angle++;
    if (c == '>' && angle > 0) angle--;
    if (c == '[') bracket++;
    if (c == ']' && bracket > 0) bracket--;
    i++;
  }
  return null;
}

_Container? _innermostContainer(List<_Container> containers, int offset) {
  _Container? best;
  for (final container in containers) {
    if (offset > container.start && offset < container.end) {
      if (best == null || container.start > best.start) best = container;
    }
  }
  return best;
}

/// 方法上面的注解名（只往回看紧邻的注解 / 修饰符行）
Set<String> _annotationsBefore(String code, int funStart) {
  final names = <String>{};
  void collect(String segment) {
    for (final match in RegExp(r'@([A-Za-z_][\w.]*)').allMatches(segment)) {
      names.add(match.group(1)!.split('.').last);
    }
  }

  final lineStart = code.lastIndexOf('\n', funStart - 1) + 1;
  collect(code.substring(lineStart, funStart));

  var cursor = lineStart;
  final modifierOnly = RegExp(
    r'^(?:public|private|internal|protected|open|abstract|override|inline|'
    r'operator|infix|tailrec|external|actual|expect|final)\s*$',
  );
  while (cursor > 0) {
    final previousEnd = cursor - 1; // 指向 '\n'
    final previousStart = code.lastIndexOf('\n', previousEnd - 1) + 1;
    final line = code.substring(previousStart, previousEnd).trim();
    if (line.startsWith('@')) {
      collect(line);
      cursor = previousStart;
      continue;
    }
    if (modifierOnly.hasMatch(line)) {
      cursor = previousStart;
      continue;
    }
    break;
  }
  return names;
}

// ── Dart 扫描 ────────────────────────────────────────────────

/// 事件参数允许的 Dart 类型 → Kotlin 类型
const _eventScalarTypes = {
  'String': 'String',
  'String?': 'String?',
  'bool': 'Boolean',
  'bool?': 'Boolean?',
  'int': 'Int',
  'int?': 'Int?',
  'double': 'Double',
  'double?': 'Double?',
  'List<String>': 'List<String>',
  'List<String>?': 'List<String>?',
};

void _scanDart(
  File file,
  String libRoot,
  String packageName,
  List<_EventMethod> events,
  Map<String, _DartDataClass> dartDatas,
) {
  final source = file.readAsStringSync();
  final code = _stripCode(source);
  final lineStarts = _lineStarts(source);
  final relative =
      file.absolute.path.substring(libRoot.length + 1).replaceAll('\\', '/');
  final library = 'package:$packageName/$relative';
  final classes = _dartClasses(code);
  String locationOf(int offset) => '${file.path}:${_lineOf(lineStarts, offset)}';

  for (final match in RegExp(r'@KotlinEvent\b').allMatches(code)) {
    // 注解可以带空参数列表（@KotlinEvent()）也可以不带
    var afterAnnotation = _skipWhitespace(code, match.end);
    if (afterAnnotation < code.length && code[afterAnnotation] == '(') {
      afterAnnotation = _matchPair(code, afterAnnotation, '(', ')') + 1;
    }
    final signatureStart = afterAnnotation;
    final signature = RegExp(
      r'^\s*static\s+void\s+([A-Za-z_]\w*)\s*\(',
    ).firstMatch(code.substring(signatureStart));
    if (signature == null) {
      throw _GenError(
        '${locationOf(match.start)}：@KotlinEvent 只能标在 static void 方法上'
        '（生成器直接 static 调用；实例方法没有可调用的入口）',
      );
    }
    final name = signature.group(1)!;
    final open = signatureStart + signature.end - 1;
    final close = _matchPair(code, open, '(', ')');
    final params = _splitTopLevel(code.substring(open + 1, close))
        .where((it) => it.trim().isNotEmpty)
        .map((raw) {
          final tokens = raw.trim().split(RegExp(r'\s+'));
          if (tokens.length != 2) {
            throw _GenError(
              '${locationOf(match.start)}：事件参数要写成「类型 名字」：${raw.trim()}',
            );
          }
          return _Param(tokens[1], tokens[0]);
        })
        .toList();

    final owner = _innermostContainer(classes, match.start);
    if (owner == null) {
      throw _GenError(
        '${locationOf(match.start)}：@KotlinEvent 要放在类里（生成器写 类名.方法名(...)）',
      );
    }
    if (owner.name.startsWith('_')) {
      throw _GenError(
        '${locationOf(match.start)}：事件所在类 ${owner.name} 不能以下划线开头：'
        '生成器在另一个库里调用它，Dart 的 `_` 名称是库私有的',
      );
    }
    if (events.any((it) => it.name == name)) {
      throw _GenError('${locationOf(match.start)}：事件 $name 重复定义');
    }
    events.add(
      _EventMethod(
        name: name,
        owner: owner.name,
        library: library,
        params: params,
        location: locationOf(match.start),
      ),
    );
  }

  _scanDartDataClasses(
    code,
    library,
    classes,
    dartDatas,
    locationOf,
  );
}

/// 事件载荷的结构体：声明在 Dart（被调方），Kotlin 镜像由生成器产出
void _scanDartDataClasses(
  String code,
  String library,
  List<_Container> classes,
  Map<String, _DartDataClass> dartDatas,
  String Function(int offset) locationOf,
) {
  for (final match in RegExp(r'@KotlinData\b').allMatches(code)) {
    var cursor = _skipWhitespace(code, match.end);
    if (cursor < code.length && code[cursor] == '(') {
      cursor = _matchPair(code, cursor, '(', ')') + 1;
    }
    final classMatch =
        RegExp(r'^\s*class\s+([A-Za-z_]\w*)').firstMatch(code.substring(cursor));
    if (classMatch == null) {
      throw _GenError(
        '${locationOf(match.start)}：@KotlinData 下面没有紧跟 class 声明',
      );
    }
    final name = classMatch.group(1)!;
    if (name.startsWith('_')) {
      throw _GenError(
        '${locationOf(match.start)}：@KotlinData $name 不能以下划线开头：'
        '生成的事件代码在另一个库里构造它，Dart 的 `_` 名称是库私有的',
      );
    }
    if (_innermostContainer(classes, match.start) != null) {
      throw _GenError(
        '${locationOf(match.start)}：@KotlinData $name 必须是顶层 class（镜像要生成到顶层）',
      );
    }
    final open = code.indexOf('{', cursor + classMatch.end);
    if (open < 0) {
      throw _GenError(
        '${locationOf(match.start)}：@KotlinData $name 找不到类体',
      );
    }
    final body = code.substring(open + 1, _matchPair(code, open, '{', '}'));

    // 字段：final Type name;
    final fields = <_Param>[];
    for (final fieldMatch in RegExp(r'\bfinal\s+([A-Za-z_][\w<>?,]*)\s+([A-Za-z_]\w*)\s*;')
        .allMatches(body)) {
      fields.add(_Param(fieldMatch.group(2)!, fieldMatch.group(1)!));
    }
    if (fields.isEmpty) {
      throw _GenError(
        '${locationOf(match.start)}：@KotlinData $name 至少需要一个 `final 类型 字段;`',
      );
    }
    for (final field in fields) {
      if (field.name.startsWith('_')) {
        throw _GenError(
          '${locationOf(match.start)}：@KotlinData $name 的字段 ${field.name} '
          '不能以下划线开头（构造参数在另一个库里用不了）',
        );
      }
      if (!_dartEventFieldTypes.contains(field.type)) {
        throw _GenError(
          '${locationOf(match.start)}：@KotlinData $name.${field.name} 的类型 '
          '${field.type} 不支持（字段只能是基础类型 / List<String>，不能嵌套结构体）',
        );
      }
    }

    // 构造：const X({required this.field, ...})
    final constructor = RegExp(
      r'\bconst\s+' + RegExp.escape(name) + r'\s*\(\s*\{([^}]*)\}\s*\)',
    ).firstMatch(body);
    if (constructor == null) {
      throw _GenError(
        '${locationOf(match.start)}：@KotlinData $name 需要 '
        '`const $name({required this.字段, ...})` 形式的构造',
      );
    }
    final named = <String>{};
    for (final part in _splitTopLevel(constructor.group(1)!)) {
      final required =
          RegExp(r'required\s+this\.([A-Za-z_]\w*)').firstMatch(part);
      if (required != null) named.add(required.group(1)!);
    }
    for (final field in fields) {
      if (!named.contains(field.name)) {
        throw _GenError(
          '${locationOf(match.start)}：@KotlinData $name 的构造参数缺 '
          '`required this.${field.name}`',
        );
      }
    }

    if (dartDatas.containsKey(name)) {
      throw _GenError(
        '${locationOf(match.start)}：@KotlinData $name 重复定义'
        '（另一处在 ${dartDatas[name]!.location}）',
      );
    }
    dartDatas[name] = _DartDataClass(
      name: name,
      library: library,
      fields: fields,
      location: locationOf(match.start),
    );
  }
}

/// 事件载荷结构体允许的 Dart 字段类型
const _dartEventFieldTypes = {
  'String',
  'String?',
  'bool',
  'bool?',
  'int',
  'int?',
  'double',
  'double?',
  'List<String>',
  'List<String>?',
};

List<_Container> _dartClasses(String code) {
  final result = <_Container>[];
  for (final match in RegExp(r'\bclass\s+([A-Za-z_]\w*)').allMatches(code)) {
    final open = code.indexOf('{', match.end);
    if (open < 0) continue;
    final end = _matchPair(code, open, '{', '}');
    result.add(_Container('class', match.group(1)!, open, end));
  }
  return result;
}

// ── 校验 ─────────────────────────────────────────────────────

void _validate(
  List<_CallMethod> calls,
  Map<String, _DataClass> datas,
  List<_EventMethod> events,
  Map<String, _DartDataClass> dartDatas,
) {
  final seen = <String, _CallMethod>{};
  for (final call in calls) {
    final previous = seen[call.name];
    if (previous != null) {
      throw _GenError(
        '${call.location}：调用名 ${call.name} 与 ${previous.location} 重复',
      );
    }
    seen[call.name] = call;

    for (final param in call.params) {
      if (_isInjected(param.name)) {
        if (param.type != 'Activity' && param.type != 'Context') {
          throw _GenError(
            '${call.location}：注入参数 ${param.name} 的必须是 Activity / Context，'
            '实际是 ${param.type}',
          );
        }
        continue;
      }
      if (!_isValueType(param.type, datas)) {
        throw _GenError(
          '${call.location}：${call.name} 的参数 ${param.name} 类型 ${param.type} 不支持'
          '（类型表见 channel/DartCall.kt 的注解注释）',
        );
      }
    }
    if (!_isValueType(call.returnType, datas)) {
      throw _GenError(
        '${call.location}：${call.name} 的返回类型 ${call.returnType} 不支持'
        '（类型表见 channel/DartCall.kt 的注解注释）',
      );
    }
  }

  for (final event in events) {
    if (!event.name.startsWith('on')) {
      throw _GenError('${event.location}：事件方法名要以 on 开头（如 onSharedFiles）');
    }
    for (final param in event.params) {
      if (_eventScalarTypes.containsKey(param.type)) continue;
      if (dartDatas.containsKey(_bareType(param.type))) continue;
      // 事件方向的被调方是 Dart：结构体必须定义在 Dart（@KotlinData），
      // Kotlin 的 @DartData 在这里没有可构造的类型，不能用。
      if (datas.containsKey(_bareType(param.type))) {
        throw _GenError(
          '${event.location}：事件 ${event.name} 的载荷 ${param.name} 用了 Kotlin '
          '@DartData（${_bareType(param.type)}）；事件的结构体要定义在 Dart 侧并标 '
          '@KotlinData，由生成器产出 Kotlin 镜像',
        );
      }
      throw _GenError(
        '${event.location}：事件 ${event.name} 的参数 ${param.name} 类型 '
        '${param.type} 不支持（载荷类型表见 lib/util/host_annotations.dart 的 KotlinEvent 注释）',
      );
    }
  }

  // 生成物同属 io.github.copper.launcher.generated：事件载荷镜像与调用数据类不能重名，
  // 否则 AndroidCall.g.kt 里会同时出现 import 的 host.X 与同包镜像 X。
  for (final name in dartDatas.keys) {
    if (datas.containsKey(name)) {
      throw _GenError(
        '${dartDatas[name]!.location}：@KotlinData $name 与 Kotlin @DartData '
        '${datas[name]!.location} 重名（生成物会撞）',
      );
    }
    if (name == 'AndroidCall' || name == 'AndroidEvent') {
      throw _GenError(
        '${dartDatas[name]!.location}：@KotlinData 不能用保留名 $name',
      );
    }
  }
}

bool _isInjected(String name) =>
    name == _activityParam || name == _applicationParam;

_DataClass? _dataOf(String type, Map<String, _DataClass> datas) =>
    datas[_bareType(type)];

String _bareType(String type) =>
    type.endsWith('?') ? type.substring(0, type.length - 1) : type;

bool _isNullable(String type) => type.endsWith('?');

// ── Dart 生成 ────────────────────────────────────────────────

String _dartCallFile(
  List<_CallMethod> calls,
  Map<String, _DataClass> datas,
) {
  final buffer = StringBuffer()
    ..writeln('// AUTO GENERATED FILE - DO NOT EDIT.')
    ..writeln(
      '// 由 tool/android_bridge/generate.dart 依据 @DartCall / @DartAsyncCall / @DartData 生成。',
    )
    ..writeln('// 生成物随源码提交：构建前 Gradle 会重新生成，保持与注解一致。')
    ..writeln()
    ..writeln("import 'package:flutter/foundation.dart';")
    ..writeln("import 'package:flutter/services.dart';")
    ..writeln()
    ..writeln('/// 非安卓平台没有宿主通道：这里统一短路，调用点不用各自判断平台。')
    ..writeln('///')
    ..writeln('/// 用 defaultTargetPlatform 而不是 dart:io 的 Platform：生成物不碰 dart:io。')
    ..writeln('bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;')
    ..writeln()
    ..writeln('/// Dart → Android 的调用通道')
    ..writeln('///')
    ..writeln('/// 每个方法对应 Kotlin 侧一个 @DartCall / @DartAsyncCall 静态方法；')
    ..writeln('/// Activity 与其应用上下文由宿主注入，这里只传业务参数。')
    ..writeln('/// 结构体（@DartData）过通道就是 Map：Dart 侧传 `toMap()`，收 `fromMap()`。')
    ..writeln('class AndroidCall {')
    ..writeln('  AndroidCall._();')
    ..writeln()
    ..writeln('  static const _channel = MethodChannel(')
    ..writeln("    '$_hostChannel',")
    ..writeln('    StandardMethodCodec(),')
    ..writeln('  );');

  final methods = <String, String>{
    for (final call in calls) call.name: _dartCallMethod(call, datas),
  };
  final names = methods.keys.toList()..sort();
  for (final name in names) {
    buffer
      ..writeln()
      ..writeln(methods[name]!);
  }
  buffer.writeln('}');

  final sortedData = datas.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  for (final data in sortedData) {
    buffer
      ..writeln()
      ..writeln(_dartDataClass(data));
  }
  return buffer.toString();
}

String _dartCallMethod(_CallMethod call, Map<String, _DataClass> datas) {
  final dartParams =
      call.params.where((param) => !_isInjected(param.name)).toList();
  final signature = dartParams
      .map((param) => '${_dartType(param.type, datas)} ${param.name}')
      .join(', ');
  final arguments = dartParams.isEmpty
      ? ''
      : ', <Object?>[${dartParams.map((param) => _dartArgument(param, datas)).join(', ')}]';
  final invocation = "'${call.name}'$arguments";
  final type = _dartType(call.returnType, datas);
  final data = _dataOf(call.returnType, datas);

  // 非安卓平台没有宿主：void 直接返回，能表达「没有值」的类型返回空值，
  // 只有「非空结构体」无处可返，才抛（当前 API 里没有这种，见 SystemInfo）。
  if (type == 'void') {
    return '''  static Future<void> ${call.name}($signature) async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>($invocation);
  }''';
  }

  if (data != null) {
    if (_isNullable(call.returnType)) {
      return '''  static Future<$type> ${call.name}($signature) async {
    if (!_isAndroid) return null;
    final map = await _channel.invokeMethod<Map<Object?, Object?>>($invocation);
    return map == null ? null : ${data.name}.fromMap(map);
  }''';
    }
    return '''  static Future<$type> ${call.name}($signature) async {
    if (!_isAndroid) {
      throw UnsupportedError('${call.name} 只在 Android 上有宿主通道');
    }
    final map = await _channel.invokeMethod<Map<Object?, Object?>>($invocation);
    return ${data.name}.fromMap(map!);
  }''';
  }

  if (type == 'List<String>') {
    return '''  static Future<List<String>> ${call.name}($signature) async {
    if (!_isAndroid) return const <String>[];
    return (await _channel.invokeMethod<List<Object?>>($invocation))?.cast<String>() ??
        const <String>[];
  }''';
  }
  if (type == 'List<String>?') {
    return '''  static Future<List<String>?> ${call.name}($signature) async {
    if (!_isAndroid) return null;
    return (await _channel.invokeMethod<List<Object?>>($invocation))?.cast<String>();
  }''';
  }

  final box = _dartBoxTypes[type];
  if (box != null) {
    final fallback = _dartDefault(type);
    if (_isNullable(type)) {
      return '''  static Future<$type> ${call.name}($signature) async {
    if (!_isAndroid) return null;
    return await _channel.invokeMethod<$box>($invocation);
  }''';
    }
    return '''  static Future<$type> ${call.name}($signature) async {
    if (!_isAndroid) return $fallback;
    return await _channel.invokeMethod<$box>($invocation) ?? $fallback;
  }''';
  }

  throw _GenError('${call.location}：${call.name} 的返回类型 $type 生成不了');
}

/// Dart 返回类型 → invokeMethod 的泛型参数
const _dartBoxTypes = {
  'String': 'String',
  'String?': 'String',
  'bool': 'bool',
  'bool?': 'bool',
  'int': 'int',
  'int?': 'int',
  'double': 'double',
  'double?': 'double',
};

String _dartDefault(String type) => switch (_bareType(type)) {
      'String' => "''",
      'bool' => 'false',
      'int' => '0',
      'double' => '0',
      _ => 'null',
    };

/// 调用参数：结构体先转 Map（通道只认基础值）
String _dartArgument(_Param param, Map<String, _DataClass> datas) {
  if (_dataOf(param.type, datas) != null) {
    return _isNullable(param.type)
        ? '${param.name}?.toMap()'
        : '${param.name}.toMap()';
  }
  return param.name;
}

String _dartType(String kotlinType, Map<String, _DataClass> datas) {
  switch (kotlinType) {
    case 'Unit':
      return 'void';
    case 'String':
    case 'String?':
      return kotlinType;
    case 'Boolean':
      return 'bool';
    case 'Boolean?':
      return 'bool?';
    case 'Int':
    case 'Long':
      return 'int';
    case 'Int?':
    case 'Long?':
      return 'int?';
    case 'Double':
      return 'double';
    case 'Double?':
      return 'double?';
    case 'List<String>':
    case 'List<String>?':
    case 'Array<String>':
      return kotlinType == 'Array<String>' ? 'List<String>' : kotlinType;
  }
  if (_dataOf(kotlinType, datas) != null) return kotlinType;
  throw _GenError('暂不支持的类型：$kotlinType');
}

String _dartDataClass(_DataClass data) {
  final buffer = StringBuffer()
    ..writeln(
      '/// Kotlin data class ${data.name} 的 Dart 镜像（${data.packageName}）',
    )
    ..writeln('///')
    ..writeln('/// 定义只在 Kotlin 的 @DartData 那一处；这里不要手改。')
    ..writeln('class ${data.name} {')
    ..writeln('  const ${data.name}({');
  for (final field in data.fields) {
    buffer.writeln('    required this.${field.name},');
  }
  buffer
    ..writeln('  });')
    ..writeln()
    ..writeln(
      '  factory ${data.name}.fromMap(Map<Object?, Object?> map) => ${data.name}(',
    );
  for (final field in data.fields) {
    buffer.writeln(
      "    ${field.name}: map['${field.name}'] as ${_dartFieldType(field.type)},",
    );
  }
  buffer
    ..writeln('  );')
    ..writeln()
    ..writeln('  Map<String, Object?> toMap() => <String, Object?>{');
  for (final field in data.fields) {
    buffer.writeln("    '${field.name}': ${field.name},");
  }
  buffer.writeln('  };');
  final declarations = [
    for (final field in data.fields)
      '  final ${_dartFieldType(field.type)} ${field.name};',
  ];
  buffer
    ..writeln()
    ..writeln(declarations.join('\n'))
    ..writeln('}');
  return buffer.toString();
}

String _dartFieldType(String kotlinType) {
  switch (kotlinType) {
    case 'String':
    case 'String?':
      return kotlinType;
    case 'Boolean':
      return 'bool';
    case 'Boolean?':
      return 'bool?';
    case 'Int':
    case 'Long':
      return 'int';
    case 'Int?':
    case 'Long?':
      return 'int?';
    case 'Double':
      return 'double';
    case 'Double?':
      return 'double?';
    case 'List<String>':
    case 'List<String>?':
      return kotlinType;
  }
  throw _GenError('数据类字段类型暂不支持：$kotlinType');
}

String _dartEventFile(
  List<_EventMethod> events,
  Map<String, _DartDataClass> dartDatas,
  String packageName,
) {
  final sorted = [...events]..sort((a, b) => a.name.compareTo(b.name));
  final payloadDatas = _eventPayloadDatas(sorted, dartDatas);
  final imports = <String>{
    'package:flutter/foundation.dart',
    'package:flutter/services.dart',
    for (final event in sorted) event.library,
    for (final data in payloadDatas) data.library,
  }.toList()
    ..sort();

  final buffer = StringBuffer()
    ..writeln('// AUTO GENERATED FILE - DO NOT EDIT.')
    ..writeln('// 由 tool/android_bridge/generate.dart 依据 Dart @KotlinEvent 静态方法生成。')
    ..writeln('// 生成物随源码提交：构建前 Gradle 会重新生成，保持与注解一致。')
    ..writeln();
  for (final import in imports) {
    buffer.writeln("import '$import';");
  }
  buffer
    ..writeln()
    ..writeln('/// 非安卓平台没有宿主通道：这里统一短路，调用点不用各自判断平台。')
    ..writeln('bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;')
    ..writeln()
    ..writeln('/// Android → Dart 的事件通道')
    ..writeln('///')
    ..writeln('/// 事件方法都是静态的，没东西好「注册」：这里只装一次 handler，')
    ..writeln('/// 收到就按方法名直接调用 @KotlinEvent 标注的那个静态方法。')
    ..writeln('/// 载荷是位置参数列表；结构体（Dart 侧 @KotlinData）过通道是 Map，')
    ..writeln('/// 用下面生成的 _xxxFromMap 构造函数还原成 Dart 对象。')
    ..writeln('class AndroidEvent {')
    ..writeln('  AndroidEvent._();')
    ..writeln()
    ..writeln('  static const _channel = MethodChannel(')
    ..writeln("    '$_eventChannel',")
    ..writeln('    StandardMethodCodec(),')
    ..writeln('  );')
    ..writeln()
    ..writeln('  static bool _started = false;')
    ..writeln()
    ..writeln('  /// 装一次宿主事件通道（启动时调一次即可；非安卓平台什么也不做）')
    ..writeln('  ///')
    ..writeln('  /// 装之前就发出去的事件会丢：冷启动那次的数据由各功能自己的')
    ..writeln('  /// `take*` 补取，这里不缓存。')
    ..writeln('  static void start() {')
    ..writeln('    if (!_isAndroid || _started) return;')
    ..writeln('    _started = true;')
    ..writeln('    _channel.setMethodCallHandler((call) async {')
    ..writeln('      switch (call.method) {');
  for (final event in sorted) {
    buffer
      ..writeln("        case '${event.name}':")
      ..writeln(_dartEventDispatch(event, dartDatas));
  }
  buffer
    ..writeln('      }')
    ..writeln('      return null;')
    ..writeln('    });')
    ..writeln('  }')
    ..writeln('}');

  for (final data in payloadDatas) {
    buffer
      ..writeln()
      ..writeln(_dartEventDataFromMap(data));
  }
  return buffer.toString();
}

/// 事件载荷里用到的 Dart 结构体（去重、按名字排序）
List<_DartDataClass> _eventPayloadDatas(
  List<_EventMethod> events,
  Map<String, _DartDataClass> dartDatas,
) {
  final names = <String>{
    for (final event in events)
      for (final param in event.params)
        if (dartDatas.containsKey(_bareType(param.type))) _bareType(param.type),
  }.toList()
    ..sort();
  return [for (final name in names) dartDatas[name]!];
}

String _dartEventFromMapName(String className) {
  final bare = className.startsWith('_') ? className.substring(1) : className;
  if (bare.isEmpty) return '_payloadFromMap';
  final lower = bare[0].toLowerCase() + bare.substring(1);
  return '_${lower}FromMap';
}

String _dartEventDataFromMap(_DartDataClass data) {
  final buffer = StringBuffer()
    ..writeln('/// ${data.name} 的通道还原（字段顺序按 Dart 声明）')
    ..writeln(
      '${data.name} ${_dartEventFromMapName(data.name)}(Map<Object?, Object?> map) =>',
    )
    ..writeln('    ${data.name}(');
  for (final field in data.fields) {
    buffer.writeln(
      "      ${field.name}: ${_dartEventFieldDecode(field.type, "map['${field.name}']")},",
    );
  }
  buffer.writeln('    );');
  return buffer.toString();
}

String _dartEventFieldDecode(String dartType, String value) {
  switch (dartType) {
    case 'String':
    case 'String?':
    case 'bool':
    case 'bool?':
    case 'int':
    case 'int?':
    case 'double':
    case 'double?':
      return '$value as $dartType';
    case 'List<String>':
      return '($value as List<Object?>).cast<String>()';
    case 'List<String>?':
      return '($value as List<Object?>?)?.cast<String>()';
  }
  throw _GenError('事件结构体字段类型暂不支持：$dartType');
}

String _dartEventDispatch(
  _EventMethod event,
  Map<String, _DartDataClass> dartDatas,
) {
  final arguments = event.params.indexed
      .map((entry) => _dartEventValue(entry.$2, 'args[${entry.$1}]', dartDatas))
      .join(', ');
  if (event.params.isEmpty) {
    return '          ${event.target}();';
  }
  return '          final args = call.arguments as List<Object?>;\n'
      '          ${event.target}($arguments);';
}

String _dartEventValue(
  _Param param,
  String expression,
  Map<String, _DartDataClass> dartDatas,
) {
  switch (param.type) {
    case 'String':
    case 'String?':
    case 'bool':
    case 'bool?':
    case 'int':
    case 'int?':
    case 'double':
    case 'double?':
      return '$expression as ${param.type}';
    case 'List<String>':
      return '($expression as List<Object?>).cast<String>()';
    case 'List<String>?':
      return '($expression as List<Object?>?)?.cast<String>()';
  }
  final data = dartDatas[_bareType(param.type)];
  if (data != null) {
    final decode =
        '${_dartEventFromMapName(data.name)}($expression as Map<Object?, Object?>)';
    return _isNullable(param.type)
        ? '($expression == null ? null : $decode)'
        : decode;
  }
  throw _GenError('事件参数类型暂不支持：${param.type}');
}

// ── Kotlin 生成 ──────────────────────────────────────────────

String _kotlinCallFile(
  List<_CallMethod> calls,
  Map<String, _DataClass> datas,
) {
  final sorted = [...calls]..sort((a, b) => a.name.compareTo(b.name));

  final returnDatas = <String>{};
  final paramDatas = <String>{};
  for (final call in sorted) {
    final returned = _dataOf(call.returnType, datas);
    if (returned != null) returnDatas.add(returned.name);
    for (final param in call.params) {
      if (_isInjected(param.name)) continue;
      final passed = _dataOf(param.type, datas);
      if (passed != null) paramDatas.add(passed.name);
    }
  }
  final usedDatas = <String>{...returnDatas, ...paramDatas};

  final imports = <String>{
    'android.app.Activity',
    'io.flutter.plugin.common.BinaryMessenger',
    'io.flutter.plugin.common.MethodChannel',
    if (sorted.any((call) => call.kind == _CallKind.async)) ...{
      'android.os.Handler',
      'android.os.Looper',
    },
    for (final call in sorted)
      if (call.receiver != null) '${call.receiverPackage}.${call.receiver}',
    for (final name in usedDatas) '${datas[name]!.packageName}.$name',
  }.toList()
    ..sort();

  final buffer = StringBuffer()
    ..writeln('// AUTO GENERATED FILE - DO NOT EDIT.')
    ..writeln(
      '// 由 tool/android_bridge/generate.dart 依据 Kotlin @DartCall / @DartAsyncCall 生成。',
    )
    ..writeln('// 生成物随源码提交：构建前 Gradle 会重新生成，保持与注解一致。')
    ..writeln('@file:Suppress("UNCHECKED_CAST")')
    ..writeln()
    ..writeln('package io.github.copper.launcher.generated')
    ..writeln();
  for (final import in imports) {
    buffer.writeln('import $import');
  }
  buffer
    ..writeln()
    ..writeln('/**')
    ..writeln(' * Dart → Android 的调用通道。')
    ..writeln(' *')
    ..writeln(' * [register] 的 handler 捕获了 [activity]：Activity 销毁时调用方必须 [clear]，')
    ..writeln(' * 否则引擎比 Activity 活得久时会把旧 Activity 一直留在内存里。')
    ..writeln(' *')
    ..writeln(' * 结构体（@DartData）过通道是 Map：返回值转 `toBridgeMap()`，参数按字段还原。')
    ..writeln(' */')
    ..writeln('object AndroidCall {')
    ..writeln('    private const val CHANNEL = "$_hostChannel"')
    ..writeln()
    ..writeln('    fun register(messenger: BinaryMessenger, activity: Activity) {')
    ..writeln(
      '        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->',
    )
    ..writeln('            val args = call.arguments as? List<Any?> ?: emptyList()')
    ..writeln('            when (call.method) {');
  for (final call in sorted) {
    buffer.writeln(_kotlinCallCase(call, datas));
  }
  buffer
    ..writeln('                else -> result.notImplemented()')
    ..writeln('            }')
    ..writeln('        }')
    ..writeln('    }')
    ..writeln()
    ..writeln('    fun clear(messenger: BinaryMessenger) {')
    ..writeln('        MethodChannel(messenger, CHANNEL).setMethodCallHandler(null)')
    ..writeln('    }');

  for (final name in returnDatas.toList()..sort()) {
    buffer
      ..writeln()
      ..writeln(_kotlinToBridgeMap(datas[name]!));
  }
  for (final name in paramDatas.toList()..sort()) {
    buffer
      ..writeln()
      ..writeln(_kotlinFromBridgeMap(datas[name]!));
  }
  buffer.writeln('}');
  return buffer.toString();
}

String _kotlinToBridgeMap(_DataClass data) {
  final buffer = StringBuffer()
    ..writeln(
      '    private fun ${data.name}.toBridgeMap(): Map<String, Any?> = mapOf(',
    );
  for (final field in data.fields) {
    buffer.writeln('        "${field.name}" to ${field.name},');
  }
  buffer.writeln('    )');
  return buffer.toString();
}

String _kotlinFromBridgeMap(_DataClass data) {
  final buffer = StringBuffer()
    ..writeln(
      '    private fun ${_fromBridgeName(data.name)}(value: Any?): ${data.name} {',
    )
    ..writeln('        val map = value as Map<*, *>')
    ..writeln('        return ${data.name}(');
  for (final field in data.fields) {
    buffer.writeln(
      '            ${field.name} = ${_kotlinFieldDecode(field.type, 'map["${field.name}"]')},',
    );
  }
  buffer
    ..writeln('        )')
    ..writeln('    }');
  return buffer.toString();
}

/// 结构体字段从 Map 还原
String _kotlinFieldDecode(String kotlinType, String value) {
  switch (kotlinType) {
    case 'String':
      return '$value as String';
    case 'String?':
      return '$value as String?';
    case 'Boolean':
      return '$value as Boolean';
    case 'Boolean?':
      return '$value as Boolean?';
    case 'Int':
      return '($value as Number).toInt()';
    case 'Int?':
      return '($value as Number?)?.toInt()';
    case 'Long':
      return '($value as Number).toLong()';
    case 'Long?':
      return '($value as Number?)?.toLong()';
    case 'Double':
      return '($value as Number).toDouble()';
    case 'Double?':
      return '($value as Number?)?.toDouble()';
    case 'List<String>':
      return '$value as List<String>';
    case 'List<String>?':
      return '$value as List<String>?';
  }
  throw _GenError('数据类字段类型暂不支持：$kotlinType');
}

String _fromBridgeName(String className) =>
    '${className[0].toLowerCase()}${className.substring(1)}FromBridge';

String _kotlinCallExpr(_CallMethod call, Map<String, _DataClass> datas) {
  var dartIndex = 0;
  final arguments = <String>[];
  for (final param in call.params) {
    if (param.name == _activityParam) {
      arguments.add('activity');
      continue;
    }
    if (param.name == _applicationParam) {
      arguments.add('activity.applicationContext');
      continue;
    }
    arguments.add(_kotlinArgument(param.type, dartIndex, datas));
    dartIndex++;
  }
  final target =
      call.receiver == null ? call.name : '${call.receiver}.${call.name}';
  return '$target(${arguments.join(', ')})';
}

String _kotlinArgument(
  String type,
  int index,
  Map<String, _DataClass> datas,
) {
  final arg = 'args[$index]';
  final data = _dataOf(type, datas);
  if (data != null) {
    final decode = _fromBridgeName(data.name);
    return _isNullable(type) ? '$arg?.let { $decode(it) }' : '$decode($arg)';
  }
  return switch (type) {
    'String' => '$arg as String',
    'String?' => '$arg as String?',
    'Boolean' => '$arg as Boolean',
    'Boolean?' => '$arg as Boolean?',
    'Int' => '$arg as Int',
    'Int?' => '$arg as Int?',
    'Long' => '($arg as Number).toLong()',
    'Long?' => '($arg as Number?)?.toLong()',
    'Double' => '($arg as Number).toDouble()',
    'Double?' => '($arg as Number?)?.toDouble()',
    'List<String>' => '$arg as List<String>',
    'List<String>?' => '$arg as List<String>?',
    'Array<String>' => '($arg as List<String>).toTypedArray()',
    _ => throw _GenError('参数类型暂不支持：$type'),
  };
}

String _kotlinCallCase(_CallMethod call, Map<String, _DataClass> datas) {
  final expression = _kotlinCallExpr(call, datas);
  final data = _dataOf(call.returnType, datas);
  final String success;
  if (data == null) {
    success = expression;
  } else if (_isNullable(call.returnType)) {
    success = '$expression?.toBridgeMap()';
  } else {
    success = '$expression.toBridgeMap()';
  }

  if (call.kind == _CallKind.sync) {
    final body = call.returnType == 'Unit'
        ? '$expression\n                        result.success(null)'
        : 'result.success($success)';
    return '''
                "${call.name}" -> {
                    try {
                        $body
                    } catch (error: Throwable) {
                        result.error("call_failed", error.message, null)
                    }
                }''';
  }

  final String work;
  final String value;
  if (call.returnType == 'Unit') {
    work = expression;
    value = 'null';
  } else {
    work = 'val value = $success';
    value = 'value';
  }
  return '''
                "${call.name}" -> {
                    Thread {
                        try {
                            $work
                            Handler(Looper.getMainLooper()).post { result.success($value) }
                        } catch (error: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("call_failed", error.message, null)
                            }
                        }
                    }.start()
                }''';
}

String _kotlinEventFile(
  List<_EventMethod> events,
  Map<String, _DartDataClass> dartDatas,
) {
  final sorted = [...events]..sort((a, b) => a.name.compareTo(b.name));
  final payloadDatas = _eventPayloadDatas(sorted, dartDatas);

  final imports = <String>{
    'android.util.Log',
    'io.flutter.plugin.common.BinaryMessenger',
    'io.flutter.plugin.common.MethodChannel',
  }.toList()
    ..sort();

  final buffer = StringBuffer()
    ..writeln('// AUTO GENERATED FILE - DO NOT EDIT.')
    ..writeln('// 由 tool/android_bridge/generate.dart 依据 Dart @KotlinEvent / @KotlinData 生成。')
    ..writeln('// 生成物随源码提交：构建前 Gradle 会重新生成，保持与注解一致。')
    ..writeln()
    ..writeln('package io.github.copper.launcher.generated')
    ..writeln();
  for (final import in imports) {
    buffer.writeln('import $import');
  }
  buffer
    ..writeln()
    ..writeln('/**')
    ..writeln(' * Android → Dart 的事件通道。')
    ..writeln(' *')
    ..writeln(' * 通道在 [attach] 时建一次，`send*` 不用再传 messenger。')
    ..writeln(' *')
    ..writeln(' * 事件载荷的结构体定义在 Dart（@KotlinData），这里的 `*Payload` 是生成的镜像：')
    ..writeln(' * 宿主构造它，发出去之前转成 Map。')
    ..writeln(' *')
    ..writeln(' * Dart 还没装 handler 时（冷启动）发送会失败，只记日志：真正的数据仍在')
    ..writeln(' * IncomingIntake 里，Dart 起来后会自己取。')
    ..writeln(' */')
    ..writeln('object AndroidEvent {')
    ..writeln('    private const val CHANNEL = "$_eventChannel"')
    ..writeln('    private const val TAG = "AndroidEvent"')
    ..writeln()
    ..writeln('    /**')
    ..writeln('     * 每个活着的引擎一条通道，按 attach 顺序：发送取最后一条。')
    ..writeln('     *')
    ..writeln('     * 启动器同一进程里可能有不止一个 FlutterActivity（MainActivity / SilentLaunchActivity），')
    ..writeln('     * 各自一个引擎；单槽位会在一个销毁时把另一个的通道也带走。')
    ..writeln('     */')
    ..writeln('    private val channels = LinkedHashMap<BinaryMessenger, MethodChannel>()')
    ..writeln()
    ..writeln('    /** 接上引擎的 messenger；Activity 拿到引擎时调一次 */')
    ..writeln('    fun attach(messenger: BinaryMessenger) {')
    ..writeln('        channels[messenger] = MethodChannel(messenger, CHANNEL)')
    ..writeln('    }')
    ..writeln()
    ..writeln('    /**')
    ..writeln('     * 断开这条通道。')
    ..writeln('     *')
    ..writeln('     * Activity 销毁时必须调：静态 map 会一直持有 messenger，')
    ..writeln('     * 引擎比 Activity 活得久时就把旧实例留住了。')
    ..writeln('     */')
    ..writeln('    fun detach(messenger: BinaryMessenger) {')
    ..writeln('        channels.remove(messenger)')
    ..writeln('    }')
    ..writeln()
    ..writeln('    private fun send(name: String, payload: Any?) {')
    ..writeln('        val channel = channels.values.lastOrNull()')
    ..writeln('        if (channel == null) {')
    ..writeln('            Log.w(TAG, "通知 Dart 失败：通道还没接上（\$name）")')
    ..writeln('            return')
    ..writeln('        }')
    ..writeln('        channel.invokeMethod(name, payload, logResult(name))')
    ..writeln('    }');

  for (final event in sorted) {
    final params = event.params
        .map((param) => '${param.name}: ${_kotlinEventType(param.type, dartDatas)}')
        .toList();
    final payload = event.params.isEmpty
        ? 'null'
        : 'listOf(${event.params.map((param) => _kotlinEventPayload(param, dartDatas)).join(', ')})';
    buffer.writeln();
    if (params.isEmpty) {
      buffer.writeln(
        '    fun ${_kotlinSendName(event)}() = send("${event.name}", $payload)',
      );
      continue;
    }
    buffer
      ..writeln('    fun ${_kotlinSendName(event)}(')
      ..writeln(params.map((param) => '        $param,').join('\n'))
      ..writeln('    ) = send("${event.name}", $payload)');
  }

  buffer
    ..writeln()
    ..writeln('    private fun logResult(name: String): MethodChannel.Result =')
    ..writeln('        object : MethodChannel.Result {')
    ..writeln('            override fun success(result: Any?) = Unit')
    ..writeln()
    ..writeln(
      '            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {',
    )
    ..writeln('                Log.w(TAG, "通知 Dart \$name 失败：\$errorMessage")')
    ..writeln('            }')
    ..writeln()
    ..writeln('            override fun notImplemented() {')
    ..writeln('                Log.w(TAG, "通知 Dart 失败：Dart 侧还没装 handler（\$name）")')
    ..writeln('            }')
    ..writeln('        }');

  for (final data in payloadDatas) {
    buffer
      ..writeln()
      ..writeln(_kotlinDartDataToBridgeMap(data));
  }
  buffer.writeln('}');

  for (final data in payloadDatas) {
    buffer
      ..writeln()
      ..writeln(_kotlinDartDataMirror(data));
  }
  return buffer.toString();
}

/// 事件载荷的 Kotlin 类型（Dart 结构体用生成的 Kotlin 镜像类名，两侧同名）
String _kotlinEventType(String dartType, Map<String, _DartDataClass> dartDatas) {
  final scalar = _eventScalarTypes[dartType];
  if (scalar != null) return scalar;
  if (dartDatas.containsKey(_bareType(dartType))) return dartType;
  throw _GenError('事件载荷类型暂不支持：$dartType');
}

/// 事件载荷里的结构体：发之前先转 Map
String _kotlinEventPayload(_Param param, Map<String, _DartDataClass> dartDatas) {
  if (dartDatas.containsKey(_bareType(param.type))) {
    return _isNullable(param.type)
        ? '${param.name}?.toBridgeMap()'
        : '${param.name}.toBridgeMap()';
  }
  return param.name;
}

/// Dart @KotlinData 的 Kotlin 镜像（宿主构造它来发事件）
String _kotlinDartDataMirror(_DartDataClass data) {
  final buffer = StringBuffer()
    ..writeln('/** 由 Dart @KotlinData ${data.name} 生成的镜像；定义只在 Dart 那一处 */')
    ..writeln('data class ${data.name}(');
  for (final field in data.fields) {
    buffer.writeln(
      '    val ${field.name}: ${_dartToKotlinFieldType(field.type)},',
    );
  }
  buffer.writeln(')');
  return buffer.toString();
}

String _kotlinDartDataToBridgeMap(_DartDataClass data) {
  final buffer = StringBuffer()
    ..writeln(
      '    private fun ${data.name}.toBridgeMap(): Map<String, Any?> = mapOf(',
    );
  for (final field in data.fields) {
    buffer.writeln('        "${field.name}" to ${field.name},');
  }
  buffer.writeln('    )');
  return buffer.toString();
}

/// Dart 结构体字段类型 → Kotlin 镜像字段类型
String _dartToKotlinFieldType(String dartType) {
  final kotlin = _eventScalarTypes[dartType];
  if (kotlin != null) return kotlin;
  throw _GenError('事件结构体字段类型暂不支持：$dartType');
}

String _kotlinSendName(_EventMethod event) {
  final bare = event.name.substring(2);
  return 'send${bare[0].toUpperCase()}${bare.substring(1)}';
}

// ── 文本工具 ───────────────────────────────────────────────────

List<int> _lineStarts(String source) {
  final starts = <int>[0];
  for (var i = 0; i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) starts.add(i + 1);
  }
  return starts;
}

int _lineOf(List<int> lineStarts, int offset) {
  var low = 0;
  var high = lineStarts.length - 1;
  while (low < high) {
    final middle = (low + high + 1) ~/ 2;
    if (lineStarts[middle] <= offset) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return low + 1;
}

int _skipWhitespace(String code, int from) {
  var i = from;
  while (i < code.length && code[i].trim().isEmpty) {
    i++;
  }
  return i;
}

int _nextSignificant(String code, int from) => _skipWhitespace(code, from);

String? _lastSignificant(String code, int from, int floor) {
  var i = from;
  while (i >= floor) {
    final c = code[i];
    if (c.trim().isNotEmpty) return c;
    i--;
  }
  return null;
}

/// 从 [open] 处的开括号找配对的闭括号；找不到就报错
int _matchPair(String code, int open, String opening, String closing) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == opening) depth++;
    if (c == closing) {
      depth--;
      if (depth == 0) return i;
    }
  }
  throw _GenError('括号不配对（从偏移 $open 起）');
}

/// 注释与字符串换成空格（换行保留），偏移不变
String _stripCode(String source) {
  final units = source.codeUnits.toList();
  final length = units.length;

  void blank(int from, int to) {
    for (var i = from; i < to && i < length; i++) {
      if (units[i] != 0x0A && units[i] != 0x0D) units[i] = 0x20;
    }
  }

  var i = 0;
  while (i < length) {
    final c = units[i];
    // 行注释
    if (c == 0x2F && i + 1 < length && units[i + 1] == 0x2F) {
      final start = i;
      while (i < length && units[i] != 0x0A) {
        i++;
      }
      blank(start, i);
      continue;
    }
    // 块注释（Kotlin 可嵌套）
    if (c == 0x2F && i + 1 < length && units[i + 1] == 0x2A) {
      final start = i;
      var depth = 0;
      while (i < length) {
        if (i + 1 < length && units[i] == 0x2F && units[i + 1] == 0x2A) {
          depth++;
          i += 2;
          continue;
        }
        if (i + 1 < length && units[i] == 0x2A && units[i + 1] == 0x2F) {
          depth--;
          i += 2;
          if (depth == 0) break;
          continue;
        }
        i++;
      }
      blank(start, i);
      continue;
    }
    // 字符串 / 字符字面量（三引号原样字符串一起处理）
    if (c == 0x22 || c == 0x27) {
      final start = i;
      final triple = i + 2 < length && units[i + 1] == c && units[i + 2] == c;
      if (triple) {
        i += 3;
        while (i + 2 < length &&
            !(units[i] == c && units[i + 1] == c && units[i + 2] == c)) {
          i++;
        }
        i = i + 2 < length ? i + 3 : length;
      } else {
        i++;
        while (i < length) {
          if (units[i] == 0x5C) {
            i += 2;
            continue;
          }
          if (units[i] == c) {
            i++;
            break;
          }
          if (units[i] == 0x0A) break;
          i++;
        }
      }
      blank(start, i);
      continue;
    }
    i++;
  }
  return String.fromCharCodes(units);
}
