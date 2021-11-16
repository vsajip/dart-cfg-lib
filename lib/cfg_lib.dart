/// Support for doing something awesome.
///
/// More dartdocs go here.
// ignore_for_file: non_constant_identifier_names, constant_identifier_names

library cfg_lib;

import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:complex/complex.dart';
// import 'package:timezone/data/latest.dart' as tz;

import 'src/tokens.dart';
import 'src/parser.dart';

var _IDENTIFIER_PATTERN = RegExp(r"^[\p{L}_][\p{L}\p{Nd}_]*$", unicode: true);

class ConfigException extends RecognizerException {
  ConfigException(String message, Location? loc) : super(message, loc);
}

class InvalidPathException extends ConfigException {
  InvalidPathException(String message, Location? loc) : super(message, loc);
}

class BadIndexException extends ConfigException {
  BadIndexException(String message, Location? loc) : super(message, loc);
}

class CircularReferenceException extends ConfigException {
  CircularReferenceException(String message, Location? loc)
      : super(message, loc);
}

bool isIdentifier(String s) {
  return _IDENTIFIER_PATTERN.hasMatch(s);
}

bool sameFile(String p1, String p2) {
  return p.canonicalize(p1) == p.canonicalize(p2);
}

ASTNode parsePath(String s) {
  var p = Parser.fromSource(s);
  var result = p.primary();
  if (!p.atEnd) {
    throw InvalidPathException('Extra text after path ${repr(s)}', p.position);
  }
  return result;
}

String toSource(ASTNode node) {
  String result;

  if (node is Token) {
    if (node.kind == TokenKind.Word || node.kind == TokenKind.String) {
      result = node.text;
    } else {
      result = node.value.toString();
    }
  } else {
    var path = _unpackPath(node);
    List<String> parts = [(path[0].operand as Token).text];

    for (var i = 1; i < path.length; i++) {
      var pe = path[i];

      switch (pe.op) {
        case TokenKind.Dot:
          parts.add('.');
          parts.add((pe.operand as Token).text);
          break;
        case TokenKind.LeftBracket:
          parts.add('[');
          parts.add(toSource(pe.operand));
          parts.add(']');
          break;
        case TokenKind.Colon:
          var sn = pe.operand as SliceNode;
          parts.add('[');
          if (sn.startIndex != null) {
            parts.add(toSource(sn.startIndex!));
          }
          parts.add(':');
          if (sn.stopIndex != null) {
            parts.add(toSource(sn.stopIndex!));
          }
          if (sn.step != null) {
            parts.add(':');
            parts.add(toSource(sn.step!));
          }
          parts.add(']');
          break;
        default:
          throw ConfigException(
              'Unexpected path element ${pe.operand}', pe.operand.start);
      }
    }
    result = parts.join('');
  }
  return result;
}

String _stringFor(dynamic v) {
  String result;

  if (v is List<dynamic>) {
    List<String> parts = [];
    for (var element in v) {
      parts.add(_stringFor(element));
    }
    result = '[${parts.join(', ')}]';
  } else if (v is Map<String, dynamic>) {
    List<String> parts = [];
    v.forEach((key, value) {
      parts.add('$key: ${_stringFor(value)}');
    });
    result = '{${parts.join(', ')}}';
  } else {
    result = v.toString();
  }
  return result;
}

class PathElement {
  TokenKind op;
  ASTNode operand;

  PathElement(this.op, this.operand);

  @override
  String toString() {
    return 'PathElement($op, $operand)';
  }
}

List<PathElement> _unpackPath(ASTNode node) {
  List<PathElement> result = [];

  void visit(ASTNode n) {
    if (n is Token) {
      result.add(PathElement(TokenKind.Dot, n));
    } else if (n is UnaryNode) {
      visit(n.operand);
    } else if (n is BinaryNode) {
      visit(n.lhs);
      result.add(PathElement(n.kind, n.rhs));
    }
  }

  visit(node);
  return result;
}

const _MISSING = Object();

typedef StringConverter = dynamic Function(String s, Config cfg);

var _ISO_DATETIME_PATTERN = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(([ T])(((\d{2}):(\d{2}):(\d{2}))(\.\d{1,6})?(([+-])(\d{2}):(\d{2})(:(\d{2})(\.\d{1,6})?)?)?))?$');
var _ENV_VALUE_PATTERN = RegExp(r'^\$(\w+)(\|(.*))?$');
var _INTERPOLATION_PATTERN = RegExp(r'\$\{([^}]+)\}');

dynamic _defaultStringConverter(String s, Config cfg) {
  dynamic result = s;

  var m = _ISO_DATETIME_PATTERN.firstMatch(s);
  if (m != null) {
    var year = int.parse(m.group(1)!);
    var month = int.parse(m.group(2)!);
    var day = int.parse(m.group(3)!);
    var hasTime = m.group(5) != null;

    if (!hasTime) {
      result = DateTime.utc(year, month, day);
    } else {
      var hour = int.parse(m.group(8)!);
      var minute = int.parse(m.group(9)!);
      var second = int.parse(m.group(10)!);
      var hasOffset = m.group(13) != null;
      var millis = 0;
      var micros = 0;

      if (m.group(11) != null) {
        var frac = double.parse(m.group(11)!);
        micros = (frac * 1.0e6).round();
        millis = micros ~/ 1000;
        micros -= millis * 1000;
      }
      var dt =
          DateTime.utc(year, month, day, hour, minute, second, millis, micros);
      if (hasOffset) {
        var sign = m.group(13) == '-' ? -1 : 1;
        var ohour = int.parse(m.group(14)!);
        var ominute = int.parse(m.group(15)!);
        var osecond = 0;
        var omillis = 0;
        var omicros = 0;

        if (m.group(17) != null) {
          osecond = int.parse(m.group(17)!);
          if (m.group(18) != null) {
            var frac = double.parse(m.group(18)!);
            omicros = (frac * 1.0e6).round();
            omillis = omicros ~/ 1000;
            omicros -= omillis * 1000;
          }
        }
        var offset = Duration(
            hours: ohour,
            minutes: ominute,
            seconds: osecond,
            milliseconds: omillis,
            microseconds: omicros);

        offset *= sign;
        dt = dt.add(offset);
      }
      result = dt;
    }
  } else {
    m = _ENV_VALUE_PATTERN.firstMatch(s);
    if (m != null) {
      var varName = m.group(1)!;
      if (Platform.environment.containsKey(varName)) {
        result = Platform.environment[varName]!;
      } else if (m.group(2) != null) {
        result = m.group(3);
      } else {
        result = null;
      }
    } else if (_INTERPOLATION_PATTERN.hasMatch(s)) {
      var pos = 0;
      List<String> parts = [];
      var failed = false;
      for (var m in _INTERPOLATION_PATTERN.allMatches(s)) {
        var os = m.start;
        var oe = m.end;
        var g = m.group(1)!;
        if (pos < os) {
          parts.add(s.substring(pos, os));
        }
        try {
          parts.add(_stringFor(cfg[g]));
        } catch (e) {
          failed = true;
          break;
        }
        pos = oe;
      }
      if (!failed) {
        if (pos < s.length) {
          parts.add(s.substring(pos));
        }
        result = parts.join('');
      }
    }
  }
  return result;
}

class Config {
  bool noDuplicates = true;
  bool strictConversions = true;
  List<String> includePath = [];
  String? path;
  Config? parent;
  Map<String, ASTNode>? _data;
  Map<String, dynamic>? _cache;
  Map<String, dynamic> context = {};
  final Set<ASTNode> _refsSeen = <ASTNode>{};
  StringConverter stringConverter = _defaultStringConverter;
  String get rootDir =>
      (path == null) ? Directory.current.path : p.dirname(path!);

  bool get cached => (_cache != null);
  set cached(bool cached) {
    if (cached) {
      _cache ??= {};
    } else {
      _cache = null;
    }
  }

  Config();

  Config.fromStream(Stream stream) {
    load(stream);
  }

  Config.fromSource(String source) : this.fromStream(Stream(source));
  // Config.fromFile(String path) : this.fromSource(File(path).readAsStringSync());
  factory Config.fromFile(String path) {
    var result = Config.fromSource(File(path).readAsStringSync());
    // ignore: prefer_initializing_formals
    result.path = path;
    return result;
  }

  @override
  String toString() {
    String? bn;
    if (path != null) {
      bn = p.basename(path!);
    }
    return 'Config($bn)';
  }

  void loadFile(String path) {
    load(Stream(File(path).readAsStringSync()));
    this.path = path;
  }

  void load(Stream stream) {
    var p = Parser.fromStream(stream);
    var node = p.container();

    if (node is! MappingNode) {
      throw ConfigException('Root configuration must be a mapping', null);
    }
    _data = wrapMapping(node);
    _cache?.clear();
  }

  Map<String, ASTNode> wrapMapping(MappingNode node) {
    Map<String, ASTNode> result = {};
    Map<String, Location>? seen = noDuplicates ? {} : null;

    for (var me in node.elements) {
      var k = (me.key.kind == TokenKind.Word) ? me.key.text : me.key.value;
      if (!noDuplicates) {
        result[k] = me.value;
      } else {
        if (seen!.containsKey(k)) {
          var msg =
              'Duplicate key $k seen at ${me.key.start} (previously at ${seen[k]}';
          throw ConfigException(msg, me.key.start);
        }
        seen[k] = me.key.start!;
        result[k] = me.value;
      }
    }
    return result;
  }

  dynamic get(String key, {dynamic dv = _MISSING}) {
    dynamic result;

    if ((_cache != null) && _cache!.containsKey(key)) {
      result = _cache![key];
    } else if (_data == null) {
      throw ConfigException('No data in configuration', null);
    } else {
      if (_data!.containsKey(key)) {
        result = evaluate(_data![key]!);
      } else if (isIdentifier(key)) {
        if (identical(dv, _MISSING)) {
          throw ConfigException('Not found in configuration: $key', null);
        }
        result = dv;
      } else {
        // not an identifier. Treat as a path
        _refsSeen.clear();
        try {
          result = _getFromPath(parsePath(key));
        } catch (e) {
          // print('*** GET $e');
          if (e is InvalidPathException ||
              e is CircularReferenceException ||
              e is BadIndexException) {
            rethrow;
          }
          if (identical(dv, _MISSING)) {
            if (e is! ConfigException) {
              rethrow;
            }
            throw ConfigException('Not found in configuration: $key', null);
          }
          result = dv;
        }
      }
    }
    // print('*** $key|$result');
    result = _unwrap(result);
    if (_cache != null) {
      _cache![key] = result;
    }
    return result;
  }

  operator [](String key) {
    return get(key, dv: _MISSING);
  }

  List<dynamic> _asList(List<ASTNode> list) {
    List<dynamic> result = [];

    // print('*** AL < $list');
    for (var node in list) {
      dynamic rv = evaluate(node);

      if (rv is ListNode) {
        rv = _asList(rv.elements);
      } else if (rv is List<ASTNode>) {
        rv = _asList(rv);
      } else if (rv is MappingNode) {
        var m = wrapMapping(rv);
        rv = _asDict(m);
      } else if (rv is Map<String, ASTNode>) {
        rv = _asDict(rv);
      } else if (rv is Config) {
        rv = rv.asDict();
      }
      // print('*** AL - ${result.length}: ${rv} (${rv.runtimeType})');
      result.add(rv);
    }
    // print('*** AL > $result');
    return result;
  }

  Map<String, dynamic> _asDict(Map<String, ASTNode> d) {
    Map<String, dynamic> result = {};

    // print('*** AD < $d');
    d.forEach((key, value) {
      dynamic rv = evaluate(value);

      // print('*** AD - $key: $value');
      if (rv is Token) {
        rv = rv.value;
      } else if (rv is MappingNode) {
        var m = wrapMapping(rv);
        rv = _asDict(m);
      } else if (rv is Map<String, ASTNode>) {
        rv = _asDict(rv);
      } else if (rv is Config) {
        rv = rv.asDict();
      } else if (rv is ListNode) {
        rv = _asList(rv.elements);
      } else if (rv is List<ASTNode>) {
        rv = _asList(rv);
      }
      result[key] = rv;
    });
    // print('*** AD > $result');
    return result;
  }

  Map<String, dynamic> asDict() {
    if (_data == null) {
      throw ConfigException('No data in configuration', null);
    }
    return _asDict(_data!);
  }

  dynamic evaluate(ASTNode node) {
    dynamic result;

    if (node is Token) {
      if (node.kind == TokenKind.Word) {
        if (!context.containsKey(node.text)) {
          throw ConfigException(
              'Unknown variable ${repr(node.text)}', node.start);
        }
        result = context[node.text];
      } else if (node.kind == TokenKind.BackTick) {
        result = _convertString(node.value, node.start!);
      } else {
        result = node.value;
      }
    } else if (node is MappingNode) {
      result = wrapMapping(node);
    } else if (node is ListNode) {
      result = node.elements;
    } else {
      switch (node.kind) {
        case TokenKind.At:
          result = _evalAt(node as UnaryNode);
          break;
        case TokenKind.Dollar:
          result = _evalReference(node as UnaryNode);
          break;
        case TokenKind.LeftCurly:
          assert(false);
          break;
        case TokenKind.Plus:
          result = _evalAdd(node as BinaryNode);
          break;
        case TokenKind.Minus:
          if (node is UnaryNode) {
            result = _evalNegate(node);
          } else {
            result = _evalSubtract(node as BinaryNode);
          }
          break;
        case TokenKind.Star:
          result = _evalMultiply(node as BinaryNode);
          break;
        case TokenKind.Slash:
          result = _evalDivide(node as BinaryNode);
          break;
        case TokenKind.SlashSlash:
          result = _evalIntegerDivide(node as BinaryNode);
          break;
        case TokenKind.Modulo:
          result = _evalModulo(node as BinaryNode);
          break;
        case TokenKind.LeftShift:
          result = _evalLeftShift(node as BinaryNode);
          break;
        case TokenKind.RightShift:
          result = _evalRightShift(node as BinaryNode);
          break;
        case TokenKind.Power:
          result = _evalPower(node as BinaryNode);
          break;
        case TokenKind.And:
          result = _evalLogicalAnd(node as BinaryNode);
          break;
        case TokenKind.Or:
          result = _evalLogicalOr(node as BinaryNode);
          break;
        case TokenKind.BitwiseComplement:
          result = _evalComplement(node as UnaryNode);
          break;
        case TokenKind.BitwiseAnd:
          result = _evalBitwiseAnd(node as BinaryNode);
          break;
        case TokenKind.BitwiseOr:
          result = _evalBitwiseOr(node as BinaryNode);
          break;
        case TokenKind.BitwiseXor:
          result = _evalBitwiseXor(node as BinaryNode);
          break;
        default:
          throw ConfigException(
              'Unable to evaluate node of kind $node.kind', node.start);
      }
    }
    return result;
  }

  dynamic _getFromPath(ASTNode node) {
    var elements = _unpackPath(node);

    void notFound(String k, Location loc) {
      throw ConfigException('Not found in configuration: $k', loc);
    }

    // print('*** GFP < $elements');
    var pe = elements[0];
    if (pe.op != TokenKind.Dot) {
      throw ConfigException(
          "Unexpected path start: ${pe.op}", pe.operand.start);
    }

    dynamic current = _data;
    Config config = this;

    for (pe in elements) {
      var loc = pe.operand.start!;
      if (pe.op == TokenKind.Dot) {
        var t = pe.operand as Token;
        assert(t.kind == TokenKind.Word);
        var k = t.text;
        if (current is Map<String, ASTNode>) {
          if (!current.containsKey(k)) {
            notFound(k, loc);
          }
          current = current[k];
        } else if (current is Map<String, dynamic>) {
          if (!current.containsKey(k)) {
            notFound(k, loc);
          }
          current = current[k];
        } else if (current is Config) {
          if (!current._data!.containsKey(k)) {
            notFound(k, loc);
          }
          current = current._data![k];
        } else {
          throw ConfigException('Invalid container for key $k', loc);
        }
      } else if (pe.op == TokenKind.LeftBracket) {
        if (current is! List) {
          throw BadIndexException(
              'Invalid container for numeric index: $current', loc);
        }
        var idx = config.evaluate(pe.operand);
        if (idx is! int) {
          throw ConfigException('Invalid index $idx', loc);
        }
        var size = current.length;
        var oidx = idx;
        if (idx < 0) idx += size;
        if ((idx < 0) || (idx >= size)) {
          throw BadIndexException(
              'Index out of range: is $oidx, must be between 0 and ${size - 1}',
              loc);
        }
        current = current[idx];
      } else if (pe.op == TokenKind.Colon) {
        if (current is! List) {
          throw BadIndexException(
              'Invalid container for slice index: $current', loc);
        }
        current = _getSlice(current, pe.operand as SliceNode);
      } else {
        throw ConfigException(
            'Invalid path element ${pe.op}', pe.operand.start);
      }
      if (current is ASTNode) {
        current = config.evaluate(current);
      }
      if (current is Config) {
        config = current;
      }
    }
    _refsSeen.clear();
    // print('*** GFP > $current');
    return config._unwrap(current);
  }

  dynamic _unwrap(dynamic v) {
    dynamic result = v;

    if (v is Map<String, ASTNode>) {
      result = _asDict(v);
    } else if (v is List<ASTNode>) {
      result = _asList(v);
    } else if (v is List<dynamic>) {
      List<dynamic> rv = [];

      for (var element in v) {
        var e = (element is ASTNode) ? evaluate(element) : element;
        rv.add(e);
      }
      result = rv;
    }
    return result;
  }

  _convertString(String s, Location loc) {
    var result = stringConverter(s, this);
    if (strictConversions && result == s) {
      throw ConfigException('Unable to convert string ${repr(s)}', loc);
    }
    return result;
  }

  // evaluation methods

  dynamic _evalAt(UnaryNode node) {
    dynamic result;
    var fn = evaluate(node.operand);
    var loc = node.operand.start; // for error reporting

    if (fn is! String) {
      throw ConfigException(
          '@ operand must be a string, but is $fn (${fn.runtimeType})', loc);
    }
    var found = false;
    String? fp;

    if (p.isAbsolute(fn) && File(fn).existsSync()) {
      fp = fn;
      found = true;
    } else {
      fp = p.join(rootDir, fn);
      if (File(fp).existsSync()) {
        found = true;
      } else {
        for (var d in includePath) {
          fp = p.join(d, fn);
          if (File(fp).existsSync()) {
            found = true;
            break;
          }
        }
      }
    }
    if (!found) {
      throw ConfigException('Unable to locate $fn', loc);
    }
    if ((path != null) && File(path!).existsSync() && sameFile(path!, fp!)) {
      throw ConfigException('Configuration cannot include itself: $fn', loc);
    }
    var parser = Parser.fromFile(fp!);
    var container = parser.container();
    if (container is ListNode) {
      result = container.elements;
    } else if (container is! MappingNode) {
      throw ConfigException(
          'Unexpected container type $container (${container.runtimeType})',
          loc);
    } else {
      var cfg = Config();
      cfg.noDuplicates = noDuplicates;
      cfg.strictConversions = strictConversions;
      cfg.context = context;
      cfg.path = fp;
      cfg.includePath = includePath;
      cfg.cached = cached;
      cfg.parent = this;
      cfg._data = wrapMapping(container);
      result = cfg;
    }
    return result;
  }

  dynamic _evalReference(UnaryNode node) {
    if (_refsSeen.contains(node)) {
      var nodes = _refsSeen.toList();

      int comparer(ASTNode n1, ASTNode n2) {
        if (n1.start!.line != n2.start!.line) {
          return n1.start!.line - n2.start!.line;
        }
        return n1.start!.column - n2.start!.column;
      }

      nodes.sort(comparer);
      List<String> parts = [];
      for (var n in nodes) {
        var s = toSource((n as UnaryNode).operand);
        parts.add('$s ${n.start}');
      }
      throw CircularReferenceException(
          'Circular reference: ${parts.join(', ')}', null);
    }
    _refsSeen.add(node);
    dynamic result = _getFromPath(node.operand);
    return result;
  }

  List<dynamic> _toList(dynamic aList) {
    if (aList is List<ASTNode>) {
      return _asList(aList);
    }
    if (aList is List<dynamic>) {
      return aList;
    }
    throw ConfigException("Unexpected list type ${aList.runtimeType}", null);
  }

  Map<String, dynamic> _toMap(dynamic aMap) {
    if (aMap is Map<String, ASTNode>) {
      return _asDict(aMap);
    }
    if (aMap is Map<String, dynamic>) {
      return aMap;
    }
    throw ConfigException("Unexpected map type ${aMap.runtimeType}", null);
  }

  Map<String, dynamic> _mergeMaps(
      Map<String, dynamic> map1, Map<String, dynamic> map2) {
    Map<String, dynamic> result = {};

    // print('*** MM < $map1, $map2');
    map2.forEach((key, value) {
      if (!map1.containsKey(key) || (value is! Map) || (map1[key] is! Map)) {
        result[key] = value;
      } else {
        result[key] = _mergeMaps(map1[key], value as Map<String, dynamic>);
      }
    });
    map1.forEach((key, value) {
      if (!result.containsKey(key)) {
        result[key] = value;
      }
    });
    // print('*** MM > $result');
    return result;
  }

  dynamic _evalAdd(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);
    dynamic result;

    void cannot() {
      throw ConfigException('Cannot add $lhs to $rhs', node.start);
    }

    if ((lhs is num) && (rhs is num)) {
      result = lhs + rhs;
    } else if ((lhs is String) && (rhs is String)) {
      result = lhs + rhs;
    } else if ((lhs is Complex) || (rhs is Complex)) {
      if ((lhs is Complex) && (rhs is Complex)) {
        result = lhs + rhs;
      } else if ((lhs is Complex) && (rhs is num)) {
        result = lhs + Complex(rhs.toDouble(), 0);
      } else if ((lhs is num) && (rhs is Complex)) {
        result = Complex(lhs.toDouble(), 0) + rhs;
      } else {
        cannot();
      }
    } else if ((lhs is List) && (rhs is List)) {
      result = _toList(lhs) + _toList(rhs);
    } else if ((lhs is Map) && (rhs is Map)) {
      result = _mergeMaps(_toMap(lhs), _toMap(rhs));
    } else {
      cannot();
    }
    return result;
  }

  dynamic _evalNegate(UnaryNode node) {
    var operand = evaluate(node.operand);
    dynamic result;

    void cannot() {
      throw ConfigException('Cannot negate $node', node.start);
    }

    if ((operand is num) || (operand is Complex)) {
      result = -operand;
    } else {
      cannot();
    }
    return result;
  }

  Map<String, dynamic> _subMaps(
      Map<String, dynamic> map1, Map<String, dynamic> map2) {
    Map<String, dynamic> result = {};

    map1.forEach((key, value) {
      if (!map2.containsKey(key)) {
        result[key] = value;
      }
    });
    return result;
  }

  dynamic _evalSubtract(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);
    dynamic result;

    void cannot() {
      throw ConfigException('Cannot subtract $rhs from $lhs', node.start);
    }

    if ((lhs is num) && (rhs is num)) {
      result = lhs - rhs;
    } else if ((lhs is Complex) || (rhs is Complex)) {
      if ((lhs is Complex) && (rhs is Complex)) {
        result = lhs - rhs;
      } else if ((lhs is Complex) && (rhs is num)) {
        result = lhs - Complex(rhs.toDouble(), 0);
      } else if ((lhs is num) && (rhs is Complex)) {
        result = Complex(lhs.toDouble(), 0) - rhs;
      } else {
        cannot();
      }
    } else if ((lhs is Map) && (rhs is Map)) {
      result = _subMaps(_toMap(lhs), _toMap(rhs));
    } else {
      cannot();
    }
    return result;
  }

  dynamic _evalMultiply(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);
    dynamic result;

    void cannot() {
      throw ConfigException('Cannot multiply $lhs by $rhs', node.start);
    }

    if ((lhs is num) && (rhs is num)) {
      result = lhs * rhs;
    } else {
      cannot();
    }
    return result;
  }

  dynamic _evalDivide(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);
    dynamic result;

    void cannot() {
      throw ConfigException('Cannot divide $lhs by $rhs', node.start);
    }

    if ((lhs is num) && (rhs is num)) {
      result = lhs / rhs;
    } else {
      cannot();
    }
    return result;
  }

  dynamic _evalIntegerDivide(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);
    dynamic result;

    void cannot() {
      throw ConfigException('Cannot integer-divide $lhs by $rhs', node.start);
    }

    if ((lhs is int) && (rhs is int)) {
      result = lhs ~/ rhs;
    } else {
      cannot();
    }
    return result;
  }

  dynamic _evalModulo(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);
    dynamic result;

    void cannot() {
      throw ConfigException('Cannot compute $lhs modulo $rhs', node.start);
    }

    if ((lhs is int) && (rhs is int)) {
      result = lhs % rhs;
    } else {
      cannot();
    }
    return result;
  }

  dynamic _evalLeftShift(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);
    dynamic result;

    void cannot() {
      throw ConfigException('Cannot left-shift $lhs by $rhs', node.start);
    }

    if ((lhs is int) && (rhs is int)) {
      result = lhs << rhs;
    } else {
      cannot();
    }
    return result;
  }

  _evalRightShift(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);
    dynamic result;

    void cannot() {
      throw ConfigException('Cannot right-shift $lhs by $rhs', node.start);
    }

    if ((lhs is int) && (rhs is int)) {
      result = lhs >> rhs;
    } else {
      cannot();
    }
    return result;
  }

  _evalPower(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);
    dynamic result;

    void cannot() {
      throw ConfigException(
          'Cannot raise $lhs to the power of $rhs', node.start);
    }

    if ((lhs is num) && (rhs is num)) {
      result = pow(lhs, rhs);
    } else if ((lhs is Complex) && (rhs is num)) {
      result = lhs.pow(rhs);
    } else {
      cannot();
    }
    return result;
  }

  _evalLogicalAnd(BinaryNode node) {
    var lhs = evaluate(node.lhs);

    if (!(lhs as bool)) {
      return lhs;
    }
    return evaluate(node.rhs);
  }

  _evalLogicalOr(BinaryNode node) {
    var lhs = evaluate(node.lhs);

    if (lhs as bool) {
      return lhs;
    }
    return evaluate(node.rhs);
  }

  _evalComplement(UnaryNode node) {}

  _evalBitwiseAnd(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);

    void cannot() {
      throw ConfigException('Cannot bitwise-and $lhs and $rhs', node.start);
    }

    if ((lhs is int) && (rhs is int)) {
      return lhs & rhs;
      // } else if ((lhs is Map) && (rhs is Map)) {
      //   return _subMaps(_toMap(lhs), _toMap(rhs));
    } else {
      cannot();
    }
  }

  _evalBitwiseOr(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);

    void cannot() {
      throw ConfigException('Cannot bitwise-or $lhs and $rhs', node.start);
    }

    if ((lhs is int) && (rhs is int)) {
      return lhs | rhs;
    } else if ((lhs is Map) && (rhs is Map)) {
      return _mergeMaps(_toMap(lhs), _toMap(rhs));
    } else {
      cannot();
    }
  }

  _evalBitwiseXor(BinaryNode node) {
    var lhs = evaluate(node.lhs);
    var rhs = evaluate(node.rhs);

    void cannot() {
      throw ConfigException('Cannot bitwise-xor $lhs and $rhs', node.start);
    }

    if ((lhs is int) && (rhs is int)) {
      return lhs ^ rhs;
      // } else if ((lhs is Map) && (rhs is Map)) {
      //   return _subMaps(_toMap(lhs), _toMap(rhs));
    } else {
      cannot();
    }
  }

  List<dynamic> _getSlice(List<dynamic> container, SliceNode sn) {
    int start, stop, step, size;
    List<dynamic> result = [];

    size = container.length;
    if (sn.step == null) {
      step = 1;
    } else {
      step = evaluate(sn.step!);
      if (step is! int) {
        throw ConfigException(
            'Step is not an integer, but $step (${step.runtimeType})',
            sn.start);
      }
      if (step == 0) {
        throw ConfigException('Step cannot be zero', sn.start);
      }
    }
    if (sn.startIndex == null) {
      start = 0;
    } else {
      start = evaluate(sn.startIndex!);
      if (start is! int) {
        throw ConfigException(
            'Start is not an integer, but $start (${start.runtimeType})',
            sn.start);
      }
      if (start < 0) {
        if (start >= -size) {
          start += size;
        } else {
          start = 0;
        }
      } else if (start >= size) {
        start = size - 1;
      }
    }
    if (sn.stopIndex == null) {
      stop = size - 1;
    } else {
      stop = evaluate(sn.stopIndex!);
      if (stop is! int) {
        throw ConfigException(
            'Stop is not an integer, but $stop (${stop.runtimeType})',
            sn.start);
      }
      if (stop < 0) {
        if (stop >= -size) {
          stop += size;
        } else {
          stop = 0;
        }
      }
      if (stop > size) {
        stop = size;
      }
      if (step < 0) {
        stop += 1;
      } else {
        stop -= 1;
      }
    }
    if ((step < 0) && (start < stop)) {
      int tmp = start;
      start = stop;
      stop = tmp;
    }

    // do the deed
    var i = start;
    var notDone = (step > 0) ? (i <= stop) : (i >= stop);
    while (notDone) {
      result.add(container[i]);
      i += step;
      notDone = (step > 0) ? (i <= stop) : (i >= stop);
    }
    return result;
  }
}
