// import 'dart:async';
// import 'dart:convert';
// ignore_for_file: non_constant_identifier_names

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:complex/complex.dart';
import 'package:cfg_lib/src/tokens.dart';
import 'package:cfg_lib/src/parser.dart';
import 'package:cfg_lib/cfg_lib.dart';

class LocInfo {
  int sl;
  int sc;
  int el;
  int ec;

  LocInfo(this.sl, this.sc, this.el, this.ec);

  @override
  String toString() {
    return '($sl, $sc)-($el, $ec)';
  }
}

class TokenInfo {
  TokenKind k;
  String t;
  dynamic v;
  int sl;
  int sc;
  int el;
  int ec;
  TokenInfo(this.k, this.t, this.v, this.sl, this.sc, this.el, this.ec);
}

class ErrorInfo {
  int line;
  int column;
  String message;

  ErrorInfo(this.line, this.column, this.message);
}

class StringTokenInfo {
  String value;
  int sl;
  int sc;
  int el;
  int ec;
  StringTokenInfo(this.value, this.sl, this.sc, this.el, this.ec);
}

class TestCase<T> {
  final String t;
  final T b;

  TestCase(this.t, this.b);
}

String dataFilePath(String first, [String? no2, String? no3, String? no4]) {
  var result = p.join('test', 'resources', first);

  if (no2 != null) {
    result = p.join(result, no2);
  }
  if (no3 != null) {
    result = p.join(result, no3);
  }
  if (no4 != null) {
    result = p.join(result, no4);
  }
  return result;
}

var _SEPARATOR_PATTERN = RegExp(r'^-- ([A-Z]\d+) -+');

Map<String, String> loadData(String path) {
  Map<String, String> result = {};
  var file = File(path);
  String? key;
  List<String> value = [];
  var lines = file.readAsLinesSync();

  for (var line in lines) {
    var m = _SEPARATOR_PATTERN.firstMatch(line);
    if (m == null) {
      value.add(line);
    } else {
      if ((key != null) && value.isNotEmpty) {
        result[key] = value.join('\n');
      }
      key = m.group(1);
      value.length = 0;
    }
  }
  return result;
}

class L extends Location {
  L(int line, int column) : super(line, column);
}

Token T(TokenKind k, String t, dynamic v, Location? s, Location? e) {
  var result = Token(k, t, v);
  if (s != null) {
    result.start = s;
  }
  if (e != null) {
    result.end = e;
  }
  return result;
}

Token W(String s, int line, int col) {
  var start = Location(line, col);
  Location end = Location(line, col + s.length - 1);
  return T(TokenKind.Word, s, null, start, end);
}

Token N(String s, int line, int col) {
  var start = Location(line, col);
  Location end = Location(line, col + s.length - 1);
  return T(TokenKind.Integer, s, int.parse(s), start, end);
}

Token F(String s, int line, int col) {
  var start = Location(line, col);
  Location end = Location(line, col + s.length - 1);
  return T(TokenKind.Float, s, double.parse(s), start, end);
}

Token S(String s, String t, int line, int col) {
  var start = Location(line, col);
  Location end = Location(line, col + s.length - 1);
  return T(TokenKind.String, s, t, start, end);
}

UnaryNode UN(TokenKind k, ASTNode o) {
  return UnaryNode(k, o);
}

BinaryNode BN(TokenKind k, ASTNode lhs, ASTNode rhs) {
  return BinaryNode(k, lhs, rhs);
}

SliceNode SN(ASTNode? from, ASTNode? to, ASTNode? step) {
  return SliceNode(from, to, step);
}

MappingEntry ME(Token k, ASTNode v) {
  return MappingEntry(k, v);
}

var _DIGITS = RegExp(r'\d+');

void main() {
  group('Location', () {
    var loc = L(1, 1);

    setUp(() {
      // Additional setup goes here.
    });

    test('defaults', () {
      expect(loc.line, equals(1));
      expect(loc.column, equals(1));
    });

    test('Next / Prev', () {
      loc.nextCol();
      expect(loc.line, equals(1));
      expect(loc.column, equals(2));
      loc.prevCol();
      expect(loc.line, equals(1));
      expect(loc.column, equals(1));
      loc.prevCol();
      expect(loc.line, equals(1));
      expect(loc.column, equals(0));
      loc.prevCol();
      expect(loc.line, equals(1));
      expect(loc.column, equals(0));
      loc.nextLine();
      expect(loc.line, equals(2));
      expect(loc.column, equals(1));
    });
  });

  group('Tokenizer', () {
    test('fragments', () {
      var cases = [
        TestCase('', TokenInfo(TokenKind.EOF, '', null, 1, 1, 1, 1)),
        TestCase('# a comment\n',
            TokenInfo(TokenKind.Newline, '# a comment', null, 1, 1, 2, 0)),
        TestCase(
            '# another comment',
            TokenInfo(
                TokenKind.Newline, '# another comment', null, 1, 1, 2, 0)),
        TestCase(
            '# yet another comment\r',
            TokenInfo(
                TokenKind.Newline, '# yet another comment', null, 1, 1, 2, 0)),
        TestCase('\r', TokenInfo(TokenKind.Newline, '\r', null, 1, 1, 2, 0)),
        TestCase('\n', TokenInfo(TokenKind.Newline, '\n', null, 1, 1, 2, 0)),
        TestCase(
            '\t\r\n', TokenInfo(TokenKind.Newline, '\n', null, 1, 2, 2, 0)),
        TestCase('foo', TokenInfo(TokenKind.Word, 'foo', null, 1, 1, 1, 3)),
        TestCase('foo:', TokenInfo(TokenKind.Word, 'foo', null, 1, 1, 1, 3)),
        TestCase(' foo', TokenInfo(TokenKind.Word, 'foo', null, 1, 2, 1, 4)),
        TestCase(
            '`foo`', TokenInfo(TokenKind.BackTick, '`foo`', 'foo', 1, 1, 1, 5)),
        TestCase(
            '"foo"', TokenInfo(TokenKind.String, '"foo"', 'foo', 1, 1, 1, 5)),
        TestCase('123', TokenInfo(TokenKind.Integer, '123', 123, 1, 1, 1, 3)),
        TestCase('123:', TokenInfo(TokenKind.Integer, '123', 123, 1, 1, 1, 3)),
        TestCase('123.', TokenInfo(TokenKind.Float, '123.', 123.0, 1, 1, 1, 4)),
        TestCase(
            '1_2_3', TokenInfo(TokenKind.Integer, '1_2_3', 123, 1, 1, 1, 5)),
        TestCase(
            '-123', TokenInfo(TokenKind.Integer, '-123', -123, 1, 1, 1, 4)),
        TestCase("'''bar'''",
            TokenInfo(TokenKind.String, "'''bar'''", 'bar', 1, 1, 1, 9)),
        TestCase('"""bar"""',
            TokenInfo(TokenKind.String, '"""bar"""', 'bar', 1, 1, 1, 9)),
        TestCase(
            ' 2.718281828 ',
            TokenInfo(
                TokenKind.Float, '2.718281828', 2.718281828, 1, 2, 1, 12)),
        TestCase(
            ' 2.718_281_828 ',
            TokenInfo(
                TokenKind.Float, '2.718_281_828', 2.718281828, 1, 2, 1, 14)),
        TestCase(
            '-2.718281828 ',
            TokenInfo(
                TokenKind.Float, '-2.718281828', -2.718281828, 1, 1, 1, 12)),
        TestCase('.5', TokenInfo(TokenKind.Float, '.5', 0.5, 1, 1, 1, 2)),
        TestCase('-.5', TokenInfo(TokenKind.Float, '-.5', -0.5, 1, 1, 1, 3)),
        TestCase('1e8', TokenInfo(TokenKind.Float, '1e8', 1e8, 1, 1, 1, 3)),
        TestCase('-1e8', TokenInfo(TokenKind.Float, '-1e8', -1e8, 1, 1, 1, 4)),
        TestCase('1e-8', TokenInfo(TokenKind.Float, '1e-8', 1e-8, 1, 1, 1, 4)),
        TestCase(
            '1_0e1_0', TokenInfo(TokenKind.Float, '1_0e1_0', 1e11, 1, 1, 1, 7)),
        TestCase(
            '-1e-8', TokenInfo(TokenKind.Float, '-1e-8', -1e-8, 1, 1, 1, 5)),
        TestCase('1j',
            TokenInfo(TokenKind.Complex, '1j', Complex(0, 1), 1, 1, 1, 2)),
        TestCase('1j ',
            TokenInfo(TokenKind.Complex, '1j', Complex(0, 1), 1, 1, 1, 2)),
        TestCase('-1j',
            TokenInfo(TokenKind.Complex, '-1j', Complex(0, -1), 1, 1, 1, 3)),
        TestCase('-.5j',
            TokenInfo(TokenKind.Complex, '-.5j', Complex(0, -0.5), 1, 1, 1, 4)),
        TestCase(
            '-1e-8J',
            TokenInfo(
                TokenKind.Complex, '-1e-8J', Complex(0, -1e-8), 1, 1, 1, 6)),
        TestCase(
            '0b0001_0110_0111',
            TokenInfo(
                TokenKind.Integer, '0b0001_0110_0111', 0x167, 1, 1, 1, 16)),
        TestCase(
            '0o123', TokenInfo(TokenKind.Integer, '0o123', 83, 1, 1, 1, 5)),
        TestCase('0x123aBc',
            TokenInfo(TokenKind.Integer, '0x123aBc', 0x123ABC, 1, 1, 1, 8)),
        TestCase('=x', TokenInfo(TokenKind.Assign, '=', null, 1, 1, 1, 1)),
        TestCase('==x', TokenInfo(TokenKind.Equal, '==', null, 1, 1, 1, 2)),
        TestCase(':x', TokenInfo(TokenKind.Colon, ':', null, 1, 1, 1, 1)),
        TestCase('-x', TokenInfo(TokenKind.Minus, '-', null, 1, 1, 1, 1)),
        TestCase('+x', TokenInfo(TokenKind.Plus, '+', null, 1, 1, 1, 1)),
        TestCase('*x', TokenInfo(TokenKind.Star, '*', null, 1, 1, 1, 1)),
        TestCase('**x', TokenInfo(TokenKind.Power, '**', null, 1, 1, 1, 2)),
        TestCase('/x', TokenInfo(TokenKind.Slash, '/', null, 1, 1, 1, 1)),
        TestCase(
            '//x', TokenInfo(TokenKind.SlashSlash, '//', null, 1, 1, 1, 2)),
        TestCase('%x', TokenInfo(TokenKind.Modulo, '%', null, 1, 1, 1, 1)),
        TestCase(',x', TokenInfo(TokenKind.Comma, ',', null, 1, 1, 1, 1)),
        TestCase('{x', TokenInfo(TokenKind.LeftCurly, '{', null, 1, 1, 1, 1)),
        TestCase('}x', TokenInfo(TokenKind.RightCurly, '}', null, 1, 1, 1, 1)),
        TestCase('[x', TokenInfo(TokenKind.LeftBracket, '[', null, 1, 1, 1, 1)),
        TestCase(
            ']x', TokenInfo(TokenKind.RightBracket, ']', null, 1, 1, 1, 1)),
        TestCase(
            '(x', TokenInfo(TokenKind.LeftParenthesis, '(', null, 1, 1, 1, 1)),
        TestCase(
            ')x', TokenInfo(TokenKind.RightParenthesis, ')', null, 1, 1, 1, 1)),
        TestCase('@x', TokenInfo(TokenKind.At, '@', null, 1, 1, 1, 1)),
        TestCase('\$x', TokenInfo(TokenKind.Dollar, '\$', null, 1, 1, 1, 1)),
        TestCase('<x', TokenInfo(TokenKind.LessThan, '<', null, 1, 1, 1, 1)),
        TestCase('<=x',
            TokenInfo(TokenKind.LessThanOrEqual, '<=', null, 1, 1, 1, 2)),
        TestCase('<<x', TokenInfo(TokenKind.LeftShift, '<<', null, 1, 1, 1, 2)),
        TestCase(
            '<>x', TokenInfo(TokenKind.AltUnequal, '<>', null, 1, 1, 1, 2)),
        TestCase('>x', TokenInfo(TokenKind.GreaterThan, '>', null, 1, 1, 1, 1)),
        TestCase('>=x',
            TokenInfo(TokenKind.GreaterThanOrEqual, '>=', null, 1, 1, 1, 2)),
        TestCase(
            '>>x', TokenInfo(TokenKind.RightShift, '>>', null, 1, 1, 1, 2)),
        TestCase('!x', TokenInfo(TokenKind.Not, '!', null, 1, 1, 1, 1)),
        TestCase('!=x', TokenInfo(TokenKind.Unequal, '!=', null, 1, 1, 1, 2)),
        TestCase('~x',
            TokenInfo(TokenKind.BitwiseComplement, '~', null, 1, 1, 1, 1)),
        TestCase('&x', TokenInfo(TokenKind.BitwiseAnd, '&', null, 1, 1, 1, 1)),
        TestCase('|x', TokenInfo(TokenKind.BitwiseOr, '|', null, 1, 1, 1, 1)),
        TestCase('^x', TokenInfo(TokenKind.BitwiseXor, '^', null, 1, 1, 1, 1)),
        TestCase('true', TokenInfo(TokenKind.True, 'true', true, 1, 1, 1, 4)),
        TestCase(
            'false', TokenInfo(TokenKind.False, 'false', false, 1, 1, 1, 5)),
        TestCase('null', TokenInfo(TokenKind.None, 'null', null, 1, 1, 1, 4)),
        TestCase('is', TokenInfo(TokenKind.Is, 'is', null, 1, 1, 1, 2)),
        TestCase('in', TokenInfo(TokenKind.In, 'in', null, 1, 1, 1, 2)),
        TestCase('not', TokenInfo(TokenKind.Not, 'not', null, 1, 1, 1, 3)),
        TestCase('and', TokenInfo(TokenKind.And, 'and', null, 1, 1, 1, 3)),
        TestCase('or', TokenInfo(TokenKind.Or, 'or', null, 1, 1, 1, 2)),

        // identifiers

        TestCase('\u0935\u092e\u0938',
            TokenInfo(TokenKind.Word, '\u0935\u092e\u0938', null, 1, 1, 1, 3)),
        TestCase(
            '\u00e9', TokenInfo(TokenKind.Word, '\u00e9', null, 1, 1, 1, 1)),
        TestCase(
            '\u00c8', TokenInfo(TokenKind.Word, '\u00c8', null, 1, 1, 1, 1)),
        TestCase(
            '\uc548\ub155\ud558\uc138\uc694',
            TokenInfo(TokenKind.Word, '\uc548\ub155\ud558\uc138\uc694', null, 1,
                1, 1, 5)),
        TestCase(
            '\u3055\u3088\u306a\u3089',
            TokenInfo(
                TokenKind.Word, '\u3055\u3088\u306a\u3089', null, 1, 1, 1, 4)),
        TestCase(
            '\u3042\u308a\u304c\u3068\u3046',
            TokenInfo(TokenKind.Word, '\u3042\u308a\u304c\u3068\u3046', null, 1,
                1, 1, 5)),
        TestCase(
            '\u0425\u043e\u0440\u043e\u0448\u043e',
            TokenInfo(TokenKind.Word, '\u0425\u043e\u0440\u043e\u0448\u043e',
                null, 1, 1, 1, 6)),
        TestCase(
            '\u0441\u043f\u0430\u0441\u0438\u0431\u043e',
            TokenInfo(
                TokenKind.Word,
                '\u0441\u043f\u0430\u0441\u0438\u0431\u043e',
                null,
                1,
                1,
                1,
                7)),
        TestCase(
            '\u73b0\u4ee3\u6c49\u8bed\u5e38\u7528\u5b57\u8868',
            TokenInfo(
                TokenKind.Word,
                '\u73b0\u4ee3\u6c49\u8bed\u5e38\u7528\u5b57\u8868',
                null,
                1,
                1,
                1,
                8)),
      ];

      for (var tcase in cases) {
        var tokenizer = Tokenizer.fromSource(tcase.t);
        var reason = 'Failed for ${repr(tcase.t)}';
        Token t;

        try {
          t = tokenizer.getToken();
        } catch (e) {
          print(reason);
          rethrow;
        }
        expect(t.kind, equals(tcase.b.k), reason: reason);
        expect(t.text, equals(tcase.b.t), reason: reason);
        expect(t.value, equals(tcase.b.v), reason: reason);
        expect(t.start, equals(L(tcase.b.sl, tcase.b.sc)), reason: reason);
        expect(t.end, equals(L(tcase.b.el, tcase.b.ec)), reason: reason);
      }
    });

    test('bad fragments', () {
      var cases = [
        TestCase('`foo', ErrorInfo(1, 5, 'Unterminated `-string')),
        TestCase(
            '`foo\n', ErrorInfo(1, 5, "Newlines not allowed in `-strings")),
        TestCase("'foo", ErrorInfo(1, 5, "Unterminated quoted string")),
        TestCase('"foo', ErrorInfo(1, 5, "Unterminated quoted string")),
        TestCase('"foo\n',
            ErrorInfo(1, 5, "Newlines not allowed in single-line strings")),
        TestCase('1.2.3', ErrorInfo(1, 4, "Invalid character in number: 1.2.")),
        TestCase('1..2', ErrorInfo(1, 3, "Invalid character in number: 1..")),
        TestCase('1__2', ErrorInfo(1, 3, "Invalid '_' in number: 1__")),
        TestCase('1._2', ErrorInfo(1, 3, "Invalid '_' in number: 1._")),
        TestCase('1e', ErrorInfo(1, 2, "Badly formed number: 1e")),
        TestCase('-1e--', ErrorInfo(1, 4, "Badly formed number: -1e-")),
        TestCase('1e_', ErrorInfo(1, 3, "Invalid '_' in number: 1e_")),
        TestCase('-1e-', ErrorInfo(1, 4, "Badly formed number: -1e-")),
        TestCase('1je', ErrorInfo(1, 4, "Badly formed number: 1je")),
        TestCase('1_', ErrorInfo(1, 2, "Invalid '_' at end of number: 1_")),
        TestCase('0b2', ErrorInfo(1, 3, "Invalid character in number: 0b2")),
        TestCase('0o8', ErrorInfo(1, 3, "Invalid character in number: 0o8")),
        TestCase('0xZ', ErrorInfo(1, 3, "Invalid character in number: 0xZ")),
        TestCase('-0b2', ErrorInfo(1, 4, "Invalid character in number: -0b2")),
        TestCase('-0o8', ErrorInfo(1, 4, "Invalid character in number: -0o8")),
        TestCase('-0xZ', ErrorInfo(1, 4, "Invalid character in number: -0xZ")),
        TestCase('123A', ErrorInfo(1, 4, "Invalid character in number: 123A")),
        TestCase(
            '123_A', ErrorInfo(1, 4, "Invalid '_' at end of number: 123_")),
        TestCase(
            '-1e-8_', ErrorInfo(1, 6, "Invalid '_' at end of number: -1e-8_")),
        TestCase(
            '-1e-8Z', ErrorInfo(1, 6, "Invalid character in number: -1e-8Z")),
        TestCase('079', ErrorInfo(1, 1, "Bad octal constant: 079")),
        TestCase('"\\xZZ"',
            ErrorInfo(1, 1, "Invalid escape sequence 'ZZ' at offset 0")),
        TestCase('"\\u000Z"',
            ErrorInfo(1, 1, "Invalid escape sequence '000Z' at offset 0")),
        TestCase('"\\U0000000Z"',
            ErrorInfo(1, 1, "Invalid escape sequence '0000000Z' at offset 0")),
        TestCase(' ;', ErrorInfo(1, 2, "Unexpected character: ;")),
        TestCase(' \\ ', ErrorInfo(1, 2, "Unexpected character: \\")),
      ];

      for (var tcase in cases) {
        var tokenizer = Tokenizer.fromSource(tcase.t);
        try {
          tokenizer.getToken();
        } catch (e) {
          if (e is! TokenizerException) {
            rethrow;
          }
          var reason = 'Failed for ${repr(tcase.t)}';
          expect(e.message, contains(tcase.b.message), reason: reason);
          expect(e.loc!.line, equals(tcase.b.line), reason: reason);
          expect(e.loc!.column, equals(tcase.b.column), reason: reason);
        }
      }
    });

    test('strings', () {
      var cases = [
        TestCase("'\\n'", StringTokenInfo("\n", 1, 1, 1, 4)),
        TestCase("'\\a\\b\\f\\n\\r\\t\\v\\\\'",
            StringTokenInfo("\x07\b\f\n\r\t\v\\", 1, 1, 1, 18)),
        TestCase("\"\"\"abc\ndef\n\"\"\"",
            StringTokenInfo("abc\ndef\n", 1, 1, 3, 3)),
        TestCase("'\\xfcber'", StringTokenInfo("über", 1, 1, 1, 9)),
        TestCase(
            "'\\u03bb-calculus'", StringTokenInfo("λ-calculus", 1, 1, 1, 17)),
        TestCase("'\\U0001f602-tears-joy'",
            StringTokenInfo("😂-tears-joy", 1, 1, 1, 22)),

        // empties

        TestCase("''", StringTokenInfo("", 1, 1, 1, 2)),
        TestCase('""', StringTokenInfo("", 1, 1, 1, 2)),
        TestCase("''''''", StringTokenInfo("", 1, 1, 1, 6)),
        TestCase('""""""', StringTokenInfo("", 1, 1, 1, 6)),
      ];

      for (var tcase in cases) {
        var tokenizer = Tokenizer.fromSource(tcase.t);
        Token t;

        try {
          t = tokenizer.getToken();
        } catch (e) {
          print('Failed for ${tcase.t}');
          rethrow;
        }

        expect(t.text, equals(tcase.t));
        expect(t.value, equals(tcase.b.value));
        expect(t.start, equals(L(tcase.b.sl, tcase.b.sc)));
        expect(t.end, equals(L(tcase.b.el, tcase.b.ec)));
      }
    });

    test('locations', () {
      var path = dataFilePath('pos.forms.cfg.txt');
      var file = File(path);
      var lines = file.readAsLinesSync();
      List<LocInfo> positions = [];

      for (var line in lines) {
        var r = List<int>.from(
            _DIGITS.allMatches(line).map((m) => int.parse(m.group(0)!)));
        positions.add(LocInfo(r[0], r[1], r[2], r[3]));
      }

      path = dataFilePath('forms.cfg');
      var tokenizer = Tokenizer.fromFile(path);

      for (var locinfo in positions) {
        var t = tokenizer.getToken();
        var reason = '$t';

        expect(t.start!.line, equals(locinfo.sl), reason: reason);
        expect(t.start!.column, equals(locinfo.sc), reason: reason);
        expect(t.end!.line, equals(locinfo.el), reason: reason);
        expect(t.end!.column, equals(locinfo.ec), reason: reason);
        // if ((t.start!.line != locinfo.sl) ||
        //     (t.start!.column != locinfo.sc) ||
        //     (t.end!.line != locinfo.el) ||
        //     (t.end!.column != locinfo.ec)) {
        //   print('Failed: $reason vs. $locinfo');
        // }
      }
    });

    test('data', () {
      Map<String, List<Token>> expected = {
        'C16': [
          T(TokenKind.Word, 'test', null, L(1, 1), L(1, 4)),
          T(TokenKind.Colon, ':', null, L(1, 6), L(1, 6)),
          T(TokenKind.False, 'false', false, L(1, 8), L(1, 12)),
          T(TokenKind.Newline, '\n', null, L(1, 13), L(2, 0)),
          T(TokenKind.Word, 'another_test', null, L(2, 1), L(2, 12)),
          T(TokenKind.Colon, ':', null, L(2, 13), L(2, 13)),
          T(TokenKind.True, 'true', true, L(2, 15), L(2, 18)),
          T(TokenKind.EOF, '', null, L(2, 19), L(2, 19)),
        ],
        'C17': [
          T(TokenKind.Word, 'test', null, L(1, 1), L(1, 4)),
          T(TokenKind.Colon, ':', null, L(1, 6), L(1, 6)),
          T(TokenKind.None, 'null', null, L(1, 8), L(1, 11)),
          T(TokenKind.EOF, '', null, L(1, 12), L(1, 12)),
        ],
        'C25': [
          T(TokenKind.Word, 'unicode', null, L(1, 1), L(1, 7)),
          T(TokenKind.Assign, '=', null, L(1, 9), L(1, 9)),
          T(TokenKind.String, "'Grüß Gott'", 'Grüß Gott', L(1, 11), L(1, 21)),
          T(TokenKind.Newline, '\n', null, L(1, 22), L(2, 0)),
          T(TokenKind.Word, 'more_unicode', null, L(2, 1), L(2, 12)),
          T(TokenKind.Colon, ':', null, L(2, 13), L(2, 13)),
          T(TokenKind.String, "'Øresund'", 'Øresund', L(2, 15), L(2, 23)),
          T(TokenKind.EOF, '', null, L(2, 24), L(2, 24)),
        ]
      };
      var path = dataFilePath('testdata.txt');
      var data = loadData(path);

      data.forEach((key, value) {
        var tokenizer = Tokenizer.fromSource(value);
        var tokens = tokenizer.getAllTokens();
        var reason = 'Failed for $key';

        if (expected.containsKey(key)) {
          expect(tokens, equals(expected[key]), reason: reason);
        }
      });
    });
  });

  group('Parser', () {
    test('values which are atoms', () {
      var cases = [
        TestCase('1', TokenInfo(TokenKind.Integer, '1', 1, 1, 1, 1, 1)),
        TestCase('1.0', TokenInfo(TokenKind.Float, '1.0', 1.0, 1, 1, 1, 3)),
        TestCase('2j',
            TokenInfo(TokenKind.Complex, '2j', Complex(0, 2), 1, 1, 1, 2)),
        TestCase('true', TokenInfo(TokenKind.True, 'true', true, 1, 1, 1, 4)),
        TestCase(
            'false', TokenInfo(TokenKind.False, 'false', false, 1, 1, 1, 5)),
        TestCase('null', TokenInfo(TokenKind.None, 'null', null, 1, 1, 1, 4)),
        TestCase('foo', TokenInfo(TokenKind.Word, 'foo', null, 1, 1, 1, 3)),
        TestCase(
            '`foo`', TokenInfo(TokenKind.BackTick, '`foo`', 'foo', 1, 1, 1, 5)),
        TestCase(
            "'abc'", TokenInfo(TokenKind.String, "'abc'", 'abc', 1, 1, 1, 5)),
        TestCase("'abc'\"def\"",
            TokenInfo(TokenKind.String, "'abc'\"def\"", 'abcdef', 1, 1, 1, 10)),
      ];

      for (var tcase in cases) {
        var p = Parser.fromSource(tcase.t);
        var v = p.value();
        var reason = 'Failed for ${tcase.t}';

        expect(v.kind, equals(tcase.b.k), reason: reason);
        expect(v.text, equals(tcase.b.t), reason: reason);
        expect(v.value, equals(tcase.b.v), reason: reason);
        expect(v.start, equals(L(tcase.b.sl, tcase.b.sc)), reason: reason);
        expect(v.end, equals(L(tcase.b.el, tcase.b.ec)), reason: reason);

        // These should also be testable as atoms.
        p = Parser.fromSource(tcase.t);
        var n = p.atom();
        expect(n is Token, isTrue, reason: reason);
        v = n as Token;
        expect(v.kind, equals(tcase.b.k), reason: reason);
        expect(v.text, equals(tcase.b.t), reason: reason);
        expect(v.value, equals(tcase.b.v), reason: reason);
        expect(v.start, equals(L(tcase.b.sl, tcase.b.sc)), reason: reason);
        expect(v.end, equals(L(tcase.b.el, tcase.b.ec)), reason: reason);
      }
    });

    test('atoms', () {
      var cases = [
        TestCase('[a]', ListNode([W('a', 1, 2)])),
        TestCase('[a, b]', ListNode([W('a', 1, 2), W('b', 1, 5)])),
        TestCase('[a\nb]', ListNode([W('a', 1, 2), W('b', 2, 1)])),
        TestCase('{a:1}', MappingNode([ME(W('a', 1, 2), N('1', 1, 4))])),
        TestCase(
            '{a:1, b:2}',
            MappingNode([
              ME(W('a', 1, 2), N('1', 1, 4)),
              ME(W('b', 1, 7), N('2', 1, 9))
            ])),
      ];

      for (var tcase in cases) {
        var p = Parser.fromSource(tcase.t);
        var n = p.atom();
        var reason = 'Failed for ${repr(tcase.t)}';

        expect(n, equals(tcase.b), reason: reason);
      }

      // error cases

      var ecases = [
        TestCase(
            '[',
            ErrorInfo(
                1, 2, 'Expected TokenKind.RightBracket but got TokenKind.EOF')),
        TestCase(
            '{',
            ErrorInfo(
                1, 2, 'Expected TokenKind.RightCurly but got TokenKind.EOF')),
        TestCase(
            '{a',
            ErrorInfo(
                1, 3, 'Expected key-value separator but got TokenKind.EOF')),
        TestCase('{a:', ErrorInfo(1, 4, 'Unexpected for value: TokenKind.EOF')),
        TestCase(
            '{a:1',
            ErrorInfo(
                1, 5, 'Expected TokenKind.RightCurly but got TokenKind.EOF')),
        TestCase(
            '{a:1,',
            ErrorInfo(
                1, 6, 'Expected TokenKind.RightCurly but got TokenKind.EOF')),
        TestCase(
            '{a:1,b',
            ErrorInfo(
                1, 7, 'Expected key-value separator but got TokenKind.EOF')),
      ];

      for (var tcase in ecases) {
        var reason = 'Failed for ${repr(tcase.t)}';

        bool checkException(Exception e) {
          bool result = false;

          if (e is ParserException) {
            result = (e.message == tcase.b.message) &&
                (e.loc!.line == tcase.b.line) &&
                (e.loc!.column == tcase.b.column);
          }
          return result;
        }

        var p = Parser.fromSource(tcase.t);
        expect(() => p.atom(), throwsA(checkException), reason: reason);
      }
    });

    test('primaries', () {
      var cases = [
        TestCase('a', W('a', 1, 1)),
        TestCase('a.b', BN(TokenKind.Dot, W('a', 1, 1), W('b', 1, 3))),
        TestCase('a[0]', BN(TokenKind.LeftBracket, W('a', 1, 1), N('0', 1, 3))),
        TestCase('a[:2]',
            BN(TokenKind.Colon, W('a', 1, 1), SN(null, N('2', 1, 4), null))),
        TestCase('a[::2]',
            BN(TokenKind.Colon, W('a', 1, 1), SN(null, null, N('2', 1, 5)))),
        TestCase(
            'a[1:10:2]',
            BN(TokenKind.Colon, W('a', 1, 1),
                SN(N('1', 1, 3), N('10', 1, 5), N('2', 1, 8)))),
        TestCase('a[2:]',
            BN(TokenKind.Colon, W('a', 1, 1), SN(N('2', 1, 3), null, null))),
        TestCase(
            'a[:-1:-1]',
            BN(TokenKind.Colon, W('a', 1, 1),
                SN(null, N('-1', 1, 4), N('-1', 1, 7)))),
      ];

      for (var tcase in cases) {
        var p = Parser.fromSource(tcase.t);
        var n = p.primary();
        var reason = 'Failed for ${repr(tcase.t)}';

        expect(n, equals(tcase.b), reason: reason);
      }

      // error cases

      var ecases = [
        TestCase(
            'a[1:10:2',
            ErrorInfo(
                1, 9, 'Expected TokenKind.RightBracket but got TokenKind.EOF')),
        TestCase(
            'a[',
            ErrorInfo(1, 3,
                'Invalid index at (1, 3): expected 1 expression, found 0')),
        TestCase(
            'a[]',
            ErrorInfo(1, 3,
                'Invalid index at (1, 3): expected 1 expression, found 0')),
      ];

      for (var tcase in ecases) {
        var reason = 'Failed for ${repr(tcase.t)}';

        bool checkException(Exception e) {
          bool result = false;

          if (e is ParserException) {
            result = e.message == tcase.b.message &&
                e.loc!.line == tcase.b.line &&
                e.loc!.column == tcase.b.column;
          }
          return result;
        }

        expect(
            () => Parser.fromSource(tcase.t).primary(), throwsA(checkException),
            reason: reason);
      }
    });

    test('unaries', () {
      var cases = [
        TestCase('a', W('a', 1, 1)),
        TestCase('-a', UN(TokenKind.Minus, W('a', 1, 2))),
        TestCase('+a', UN(TokenKind.Plus, W('a', 1, 2))),
        TestCase('@a', UN(TokenKind.At, W('a', 1, 2))),
        TestCase('--a', UN(TokenKind.Minus, UN(TokenKind.Minus, W('a', 1, 3)))),
        TestCase(
            '-a**b',
            UN(TokenKind.Minus,
                BN(TokenKind.Power, W('a', 1, 2), W('b', 1, 5)))),
        TestCase(
            'a**b**c',
            BN(TokenKind.Power, W('a', 1, 1),
                BN(TokenKind.Power, W('b', 1, 4), W('c', 1, 7)))),
        TestCase(
            '-a**b**c',
            UN(
                TokenKind.Minus,
                BN(TokenKind.Power, W('a', 1, 2),
                    BN(TokenKind.Power, W('b', 1, 5), W('c', 1, 8))))),
      ];

      for (var tcase in cases) {
        var p = Parser.fromSource(tcase.t);
        var n = p.unaryExpr();
        var reason = 'Failed for ${repr(tcase.t)}';

        expect(n, equals(tcase.b), reason: reason);
      }
    });

    test('expressions', () {
      var cases = [
        TestCase('a + b', BN(TokenKind.Plus, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a - b', BN(TokenKind.Minus, W('a', 1, 1), W('b', 1, 5))),
        TestCase(
            'a + b - c',
            BN(TokenKind.Minus, BN(TokenKind.Plus, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase('a * b', BN(TokenKind.Star, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a / b', BN(TokenKind.Slash, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a % b', BN(TokenKind.Modulo, W('a', 1, 1), W('b', 1, 5))),
        TestCase(
            'a // b', BN(TokenKind.SlashSlash, W('a', 1, 1), W('b', 1, 6))),
        TestCase(
            'a * b - c',
            BN(TokenKind.Minus, BN(TokenKind.Star, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase('a < b', BN(TokenKind.LessThan, W('a', 1, 1), W('b', 1, 5))),
        TestCase(
            'a > b', BN(TokenKind.GreaterThan, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a <= b',
            BN(TokenKind.LessThanOrEqual, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a >= b',
            BN(TokenKind.GreaterThanOrEqual, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a == b', BN(TokenKind.Equal, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a != b', BN(TokenKind.Unequal, W('a', 1, 1), W('b', 1, 6))),
        TestCase(
            'a <> b', BN(TokenKind.AltUnequal, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a is b', BN(TokenKind.Is, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a in b', BN(TokenKind.In, W('a', 1, 1), W('b', 1, 6))),
        TestCase(
            'a is not b', BN(TokenKind.IsNot, W('a', 1, 1), W('b', 1, 10))),
        TestCase(
            'a not in b', BN(TokenKind.NotIn, W('a', 1, 1), W('b', 1, 10))),
        TestCase('not a', UN(TokenKind.Not, W('a', 1, 5))),
        TestCase(
            'not not a', UN(TokenKind.Not, UN(TokenKind.Not, W('a', 1, 9)))),
        TestCase('a and b', BN(TokenKind.And, W('a', 1, 1), W('b', 1, 7))),
        TestCase(
            'a and b or not c',
            BN(TokenKind.Or, BN(TokenKind.And, W('a', 1, 1), W('b', 1, 7)),
                UN(TokenKind.Not, W('c', 1, 16)))),
        TestCase(
            '(a + b) - (c + d) * (e + f)',
            BN(
                TokenKind.Minus,
                BN(TokenKind.Plus, W('a', 1, 2), W('b', 1, 6)),
                BN(
                    TokenKind.Star,
                    BN(TokenKind.Plus, W('c', 1, 12), W('d', 1, 16)),
                    BN(TokenKind.Plus, W('e', 1, 22), W('f', 1, 26))))),
        TestCase('a + 4', BN(TokenKind.Plus, W('a', 1, 1), N('4', 1, 5))),
        TestCase('foo', W('foo', 1, 1)),
        TestCase('0.5', F('0.5', 1, 1)),
        TestCase("'foo''bar'", S("'foo''bar'", 'foobar', 1, 1)),
        TestCase('a.b', BN(TokenKind.Dot, W('a', 1, 1), W('b', 1, 3))),

        // unaries

        TestCase('+bar', UN(TokenKind.Plus, W('bar', 1, 2))),
        TestCase('-bar', UN(TokenKind.Minus, W('bar', 1, 2))),
        TestCase('~bar', UN(TokenKind.BitwiseComplement, W('bar', 1, 2))),
        TestCase('not bar', UN(TokenKind.Not, W('bar', 1, 5))),
        TestCase('!bar', UN(TokenKind.Not, W('bar', 1, 2))),
        TestCase('@bar', UN(TokenKind.At, W('bar', 1, 2))),

        // binaries

        TestCase('a + b', BN(TokenKind.Plus, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a - b', BN(TokenKind.Minus, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a * b', BN(TokenKind.Star, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a / b', BN(TokenKind.Slash, W('a', 1, 1), W('b', 1, 5))),
        TestCase(
            'a // b', BN(TokenKind.SlashSlash, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a % b', BN(TokenKind.Modulo, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a ** b', BN(TokenKind.Power, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a << b', BN(TokenKind.LeftShift, W('a', 1, 1), W('b', 1, 6))),
        TestCase(
            'a >> b', BN(TokenKind.RightShift, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a and b', BN(TokenKind.And, W('a', 1, 1), W('b', 1, 7))),
        TestCase('a && b', BN(TokenKind.And, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a or b', BN(TokenKind.Or, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a || b', BN(TokenKind.Or, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a & b', BN(TokenKind.BitwiseAnd, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a | b', BN(TokenKind.BitwiseOr, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a ^ b', BN(TokenKind.BitwiseXor, W('a', 1, 1), W('b', 1, 5))),

        TestCase('a < b', BN(TokenKind.LessThan, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a <= b',
            BN(TokenKind.LessThanOrEqual, W('a', 1, 1), W('b', 1, 6))),
        TestCase(
            'a > b', BN(TokenKind.GreaterThan, W('a', 1, 1), W('b', 1, 5))),
        TestCase('a >= b',
            BN(TokenKind.GreaterThanOrEqual, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a == b', BN(TokenKind.Equal, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a != b', BN(TokenKind.Unequal, W('a', 1, 1), W('b', 1, 6))),
        TestCase(
            'a <> b', BN(TokenKind.AltUnequal, W('a', 1, 1), W('b', 1, 6))),
        TestCase('a in b', BN(TokenKind.In, W('a', 1, 1), W('b', 1, 6))),
        TestCase(
            'a not in b', BN(TokenKind.NotIn, W('a', 1, 1), W('b', 1, 10))),
        TestCase('a is b', BN(TokenKind.Is, W('a', 1, 1), W('b', 1, 6))),
        TestCase(
            'a is not b', BN(TokenKind.IsNot, W('a', 1, 1), W('b', 1, 10))),

        TestCase(
            'a + b + c',
            BN(TokenKind.Plus, BN(TokenKind.Plus, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase(
            'a - b - c',
            BN(TokenKind.Minus, BN(TokenKind.Minus, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase(
            'a * b * c',
            BN(TokenKind.Star, BN(TokenKind.Star, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase(
            'a / b / c',
            BN(TokenKind.Slash, BN(TokenKind.Slash, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase(
            'a // b // c',
            BN(
                TokenKind.SlashSlash,
                BN(TokenKind.SlashSlash, W('a', 1, 1), W('b', 1, 6)),
                W('c', 1, 11))),
        TestCase(
            'a % b % c',
            BN(
                TokenKind.Modulo,
                BN(TokenKind.Modulo, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase(
            'a << b << c',
            BN(
                TokenKind.LeftShift,
                BN(TokenKind.LeftShift, W('a', 1, 1), W('b', 1, 6)),
                W('c', 1, 11))),
        TestCase(
            'a >> b >> c',
            BN(
                TokenKind.RightShift,
                BN(TokenKind.RightShift, W('a', 1, 1), W('b', 1, 6)),
                W('c', 1, 11))),
        TestCase(
            'a and b and c',
            BN(TokenKind.And, BN(TokenKind.And, W('a', 1, 1), W('b', 1, 7)),
                W('c', 1, 13))),
        TestCase(
            'a or b or c',
            BN(TokenKind.Or, BN(TokenKind.Or, W('a', 1, 1), W('b', 1, 6)),
                W('c', 1, 11))),
        TestCase(
            'a & b & c',
            BN(
                TokenKind.BitwiseAnd,
                BN(TokenKind.BitwiseAnd, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase(
            'a | b | c',
            BN(
                TokenKind.BitwiseOr,
                BN(TokenKind.BitwiseOr, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase(
            'a ^ b ^ c',
            BN(
                TokenKind.BitwiseXor,
                BN(TokenKind.BitwiseXor, W('a', 1, 1), W('b', 1, 5)),
                W('c', 1, 9))),
        TestCase(
            'a ** b ** c',
            BN(TokenKind.Power, W('a', 1, 1),
                BN(TokenKind.Power, W('b', 1, 6), W('c', 1, 11)))),

        TestCase(
            'a + b * c',
            BN(TokenKind.Plus, W('a', 1, 1),
                BN(TokenKind.Star, W('b', 1, 5), W('c', 1, 9)))),
      ];

      for (var tcase in cases) {
        var p = Parser.fromSource(tcase.t);
        var n = p.expr();
        var reason = 'Failed for ${repr(tcase.t)}';

        expect(n, equals(tcase.b), reason: reason);
      }
    });

    test('data', () {
      var data = loadData(dataFilePath('testdata.txt'));
      var errors = {
        'D01': ErrorInfo(2, 1, 'Unexpected for key: TokenKind.Integer'),
        'D02': ErrorInfo(2, 1, 'Unexpected for key: TokenKind.LeftBracket'),
        'D03': ErrorInfo(2, 1, 'Unexpected for key: TokenKind.LeftCurly'),
      };
      data.forEach((key, value) {
        var p = Parser.fromSource(value);
        var reason = 'Failed for $key';
        if (key.compareTo('D01') < 0) {
          p.mappingBody();
        } else {
          bool checkException(Exception e) {
            bool result = false;

            if (e is ParserException) {
              var ei = errors[key]!;

              result = e.message == ei.message &&
                  e.loc!.line == ei.line &&
                  e.loc!.column == ei.column;
            }
            return result;
          }

          expect(() => p.mappingBody(), throwsA(checkException),
              reason: reason);
        }
      });
    });

    test('json', () {
      var path = dataFilePath('forms.conf');
      var p = Parser.fromFile(path);
      var mn = p.mapping();
      var expected = {'refs', 'fieldsets', 'forms', 'modals', 'pages'};
      var actual = <String>{};

      for (var me in mn.elements) {
        var t = me.key;
        actual.add(t.kind == TokenKind.Word ? t.text : t.value);
      }
      expect(actual, equals(expected));
    });

    test('parser files', () {
      var d = dataFilePath('derived');

      for (var entry in Directory(d).listSync()) {
        if (entry is! File) {
          continue;
        }
        var p = Parser.fromFile(entry.path);
        p.container();
      }
    });

    test('slices', () {
      var cases = [
        TestCase('foo[start:stop:step]',
            SN(W('start', 1, 5), W('stop', 1, 11), W('step', 1, 16))),
        TestCase(
            'foo[start:stop]', SN(W('start', 1, 5), W('stop', 1, 11), null)),
        TestCase(
            'foo[start:stop:]', SN(W('start', 1, 5), W('stop', 1, 11), null)),
        TestCase('foo[start:]', SN(W('start', 1, 5), null, null)),
        TestCase('foo[start::]', SN(W('start', 1, 5), null, null)),
        TestCase('foo[:stop]', SN(null, W('stop', 1, 6), null)),
        TestCase('foo[::step]', SN(null, null, W('step', 1, 7))),
        TestCase('foo[::]', SN(null, null, null)),
        TestCase('foo[:]', SN(null, null, null)),
        TestCase(
            'foo[start::step]', SN(W('start', 1, 5), null, W('step', 1, 12))),
        TestCase('foo[start]', null),
      ];

      for (var tcase in cases) {
        var p = Parser.fromSource(tcase.t);
        var node = p.expr();

        expect(node is BinaryNode, isTrue);
        var bn = node as BinaryNode;
        expect(bn.lhs is Token, isTrue);
        var t = bn.lhs as Token;
        expect(t.kind, equals(TokenKind.Word));
        expect(t.text, equals('foo'));
        if (tcase.t == 'foo[start]') {
          expect(node.kind, equals(TokenKind.LeftBracket));
          expect(bn.rhs is Token, isTrue);
          t = bn.rhs as Token;
          expect(t.kind, equals(TokenKind.Word));
          expect(t.text, equals('start'));
        } else {
          expect(node.kind, equals(TokenKind.Colon));
          expect(bn.rhs is SliceNode, isTrue);
          var sn = bn.rhs as SliceNode;
          expect(sn, equals(tcase.b));
        }
      }
    });

    test('bad slices', () {
      var cases = [
        TestCase(
            'foo[start::step:]',
            ErrorInfo(1, 16,
                'Expected TokenKind.RightBracket but got TokenKind.Colon')),
        TestCase(
            'foo[a, b:c:d]',
            ErrorInfo(1, 5,
                'Invalid index at (1, 5): expected 1 expression, found 2')),
        TestCase(
            'foo[a:b, c:d]',
            ErrorInfo(1, 7,
                'Invalid index at (1, 7): expected 1 expression, found 2')),
        TestCase(
            'foo[a:b:c,d, e]',
            ErrorInfo(1, 9,
                'Invalid index at (1, 9): expected 1 expression, found 3')),
      ];

      for (var tcase in cases) {
        var p = Parser.fromSource(tcase.t);

        bool checkException(e) {
          bool result = false;

          if (e is ParserException) {
            return e.message == tcase.b.message &&
                e.loc == L(tcase.b.line, tcase.b.column);
          }
          return result;
        }

        expect(() => p.expr(), throwsA(checkException));
      }
    });
  });

  group('Config', () {
    final config = Config();

    test('defaults', () {
      expect(config.noDuplicates, isTrue);
      expect(config.strictConversions, isTrue);
    });

    test('identifiers', () {
      var cases = [
        TestCase('foo', true),
        TestCase('\u0935\u092e\u0938', true),
        TestCase('\u00e9', true),
        TestCase('\u00c8', true),
        TestCase('\uc548\ub155\ud558\uc138\uc694', true),
        TestCase('\u3055\u3088\u306a\u3089', true),
        TestCase('\u3042\u308a\u304c\u3068\u3046', true),
        TestCase('\u0425\u043e\u0440\u043e\u0448\u043e', true),
        TestCase('\u0441\u043f\u0430\u0441\u0438\u0431\u043e', true),
        TestCase('\u73b0\u4ee3\u6c49\u8bed\u5e38\u7528\u5b57\u8868', true),
        TestCase('foo ', false),
        TestCase('foo[', false),
        TestCase('foo [', false),
        TestCase('foo.', false),
        TestCase('foo .', false),
        TestCase('\u0935\u092e\u0938.', false),
        TestCase('\u73b0\u4ee3\u6c49\u8bed\u5e38\u7528\u5b57\u8868.', false),
        TestCase('9', false),
        TestCase('9foo', false),
        TestCase('hyphenated-key', false),
      ];

      for (var tcase in cases) {
        expect(isIdentifier(tcase.t), equals(tcase.b));
      }
    });

    test('files', () {
      var notMappings = {
        'data.cfg',
        'incl_list.cfg',
        'pages.cfg',
        'routes.cfg'
      };
      var d = dataFilePath('derived');
      var entries = Directory(d).listSync();
      var cfg = Config();

      for (var entry in entries) {
        if (entry is! File) {
          continue;
        }
        try {
          cfg.loadFile(entry.path);
        } catch (e) {
          var bn = p.basename(entry.path);
          if (e is! ConfigException) {
            rethrow;
          }
          if (bn == 'dupes.cfg') {
            expect(
                e.message,
                equals(
                    'Duplicate key foo seen at (4, 1) (previously at (1, 1)'));
          } else if (notMappings.contains(bn)) {
            expect(e.message, equals('Root configuration must be a mapping'));
          } else {
            fail('Unexpected exception message: ${repr(e.message)}');
          }
        }
      }
    });

    test('main config', () {
      var fp = dataFilePath('derived', 'main.cfg');
      var cfg = Config();
      cfg.includePath.add(dataFilePath('base'));
      cfg.loadFile(fp);
      var lcfg = cfg['logging'];
      expect(lcfg is Config, isTrue);
      var d = lcfg.asDict();
      var keys = Set.of(d.keys);
      var expected = {'formatters', 'handlers', 'loggers', 'root'};
      expect(keys, equals(expected));
      var ei =
          ErrorInfo(1, 14, "Extra text after path 'handlers.file/filename'");

      bool checkException(ConfigException e) {
        bool result = e.message == ei.message &&
            e.loc!.line == ei.line &&
            e.loc!.column == ei.column;
        return result;
      }

      expect(() => lcfg['handlers.file/filename'], throwsA(checkException));
      expect(lcfg.get('foo', dv: 'bar'), equals('bar'));
      expect(lcfg.get('foo.bar', dv: 'baz'), equals('baz'));
      expect(lcfg.get('handlers.debug.lvl', dv: 'bozz'), equals('bozz'));
      expect(lcfg['handlers.file.filename'], equals('run/server.log'));
      expect(lcfg['handlers.debug.filename'], equals('run/server-debug.log'));
      expect(lcfg['root.handlers'], equals(['file', 'error', 'debug']));
      expect(lcfg['root.handlers[2]'], equals('debug'));
      expect(lcfg['root.handlers[:2]'], equals(['file', 'error']));
      expect(lcfg['root.handlers[::2]'], equals(['file', 'debug']));

      var tcfg = cfg['test'];
      expect(tcfg is Config, isTrue);
      expect(tcfg['float'], equals(1.0e-7));
      expect(tcfg['float2'], equals(0.3));
      expect(tcfg['float3'], equals(3.0));
      expect(tcfg['list[1]'], equals(2));
      expect(tcfg['dict.a'], equals('b'));
      expect(tcfg['date'], equals(DateTime.utc(2019, 3, 28)));
      var offset = Duration(hours: 5, minutes: 30);
      var edt = DateTime.utc(2019, 3, 28, 23, 27, 4, 314, 159).add(offset);
      expect(tcfg['date_time'], equals(edt));
      edt = edt.add(offset * -2);
      expect(tcfg['neg_offset_time'], equals(edt));
      edt = DateTime.utc(2019, 3, 28, 23, 27, 4, 271, 828);
      expect(tcfg['alt_date_time'], equals(edt));
      edt = DateTime.utc(2019, 3, 28, 23, 27, 4);
      expect(tcfg['no_ms_time'], equals(edt));
      expect(tcfg['computed'], equals(3.3));
      expect(tcfg['computed2'], equals(2.7));
      expect(tcfg['computed3'], closeTo(0.9, 1.0e-7));
      expect(tcfg['computed4'], equals(10.0));
      cfg['base']; // just to see there's no error getting it
      dynamic ev = [
        'derived_foo',
        'derived_bar',
        'derived_baz',
        'test_foo',
        'test_bar',
        'test_baz',
        'base_foo',
        'base_bar',
        'base_baz'
      ];
      expect(cfg['combined_list'], equals(ev));
      ev = {
        'foo_key': 'base_foo',
        'bar_key': 'base_bar',
        'baz_key': 'base_baz',
        'base_foo_key': 'base_foo',
        'base_bar_key': 'base_bar',
        'base_baz_key': 'base_baz',
        'derived_foo_key': 'derived_foo',
        'derived_bar_key': 'derived_bar',
        'derived_baz_key': 'derived_baz',
        'test_foo_key': 'test_foo',
        'test_bar_key': 'test_bar',
        'test_baz_key': 'test_baz',
      };
      expect(cfg['combined_map_1'], equals(ev));
      ev = {
        'derived_foo_key': 'derived_foo',
        'derived_bar_key': 'derived_bar',
        'derived_baz_key': 'derived_baz',
      };
      expect(cfg['combined_map_2'], equals(ev));
      var n1 = cfg['number_1'];
      var n2 = cfg['number_2'];
      expect(cfg['number_3'], equals(n1 & n2));
      expect(cfg['number_4'], equals(n1 ^ n2));

      var cases = [
        TestCase(
            'logging[4]',
            ErrorInfo(1, 9,
                'Invalid container for numeric index: Config(logging.cfg)')),
        TestCase(
            'logging[:4]',
            ErrorInfo(1, 8,
                'Invalid container for slice index: Config(logging.cfg)')),
        TestCase('no_such_key',
            ErrorInfo(0, 0, 'Not found in configuration: no_such_key')),
      ];

      for (var tcase in cases) {
        try {
          cfg[tcase.t];
          fail('Exception not raised when it should have been');
        } catch (e) {
          if (e is! ConfigException) {
            rethrow;
          }
          expect(e.message, tcase.b.message);
          if (tcase.b.line != 0) {
            expect(e.loc, equals(L(tcase.b.line, tcase.b.column)));
          }
        }
      }
    });

    test('example config', () {
      var fp = dataFilePath('derived', 'example.cfg');
      var cfg = Config();
      cfg.includePath.add(dataFilePath('base'));
      cfg.loadFile(fp);
      expect(cfg['snowman_escaped'] == cfg['snowman_unescaped'], isTrue);
      expect(cfg['snowman_escaped'], equals('☃'));
      expect(cfg['face_with_tears_of_joy'], equals('😂'));
      expect(cfg['unescaped_face_with_tears_of_joy'], equals('😂'));
      dynamic ev = ["Oscar Fingal O'Flahertie Wills Wilde", 'size: 5"'];
      expect(cfg['strings[:2]'], equals(ev));
      if (Platform.isWindows) {
        ev = [
          "Triple quoted form\r\ncan span\r\n'multiple' lines",
          "with \"either\"\r\nkind of 'quote' embedded within"
        ];
      } else {
        ev = [
          "Triple quoted form\ncan span\n'multiple' lines",
          "with \"either\"\nkind of 'quote' embedded within"
        ];
      }
      expect(cfg['strings[2:]'], equals(ev));
      expect(cfg['special_value_2'], equals(Platform.environment['HOME']));
      var offset = Duration(
          hours: 5,
          minutes: 30,
          seconds: 43,
          milliseconds: 123,
          microseconds: 456);
      ev = DateTime.utc(2019, 3, 28, 23, 27, 4, 314, 159).add(offset);
      expect(cfg['special_value_3'], equals(ev));
      expect(cfg['special_value_4'], equals('bar'));

      // integers

      expect(cfg['decimal_integer'], equals(123));
      expect(cfg['hexadecimal_integer'], equals(0x123));
      expect(cfg['octal_integer'], equals(83));
      expect(cfg['binary_integer'], equals(0x123));

      // floats      expect(cfg['common_or_garden'], equals(123.456));
      expect(cfg['common_or_garden'], equals(123.456));
      expect(cfg['leading_zero_not_needed'], equals(0.123));
      expect(cfg['trailing_zero_not_needed'], equals(123.0));
      expect(cfg['scientific_large'], equals(1.0e6));
      expect(cfg['scientific_small'], equals(1.0e-7));
      expect(cfg['expression_1'], equals(3.14159));

      // complex

      expect(cfg['expression_2'], equals(Complex(3, 2)));
      expect(cfg['list_value[4]'], equals(Complex(1, 3)));

      // bool

      expect(cfg['boolean_value'], isTrue);
      expect(cfg['opposite_boolean_value'], isFalse);
      expect(cfg['computed_boolean_2'], isFalse);
      expect(cfg['computed_boolean_1'], isTrue);

      // list

      ev = ['a', 'b', 'c'];
      expect(cfg['incl_list'], equals(ev));

      // mapping

      ev = {'bar': 'baz', 'foo': 'bar'};
      expect(cfg['incl_mapping'].asDict(), equals(ev));
      ev = {'fizz': 'buzz', 'baz': 'bozz'};
      expect(cfg['incl_mapping_body'].asDict(), equals(ev));
    });

    test('duplicates', () {
      var p = dataFilePath('derived', 'dupes.cfg');
      var ei = ErrorInfo(
          4, 1, 'Duplicate key foo seen at (4, 1) (previously at (1, 1)');

      bool checkException(Exception e) {
        var result = false;

        if (e is ConfigException) {
          result = (e.message == ei.message) &&
              (e.loc == Location(ei.line, ei.column));
        }
        return result;
      }

      expect(() => Config.fromFile(p), throwsA(checkException));
      var cfg = Config();
      cfg.noDuplicates = false;
      cfg.loadFile(p);
      expect(cfg['foo'], equals('not again!'));
    });

    test('context', () {
      var p = dataFilePath('derived', 'context.cfg');
      var cfg = Config();
      cfg.context = {'bozz': 'bozz-bozz'};
      cfg.loadFile(p);
      expect(cfg['baz'], equals('bozz-bozz'));

      bool checkException(e) {
        bool result = false;

        if (e is ConfigException) {
          return (e.message == "Unknown variable 'not_there'") &&
              (e.loc == L(3, 7));
        }
        return result;
      }

      expect(() => cfg['bad'], throwsA(checkException));
    });
    test('expressions', () {
      var p = dataFilePath('derived', 'test.cfg');
      var cfg = Config.fromFile(p);
      expect(cfg['dicts_added'], equals({'a': 'b', 'c': 'd'}));
      dynamic ev = {
        'a': {'b': 'c', 'w': 'x'},
        'd': {'e': 'f', 'y': 'z'}
      };
      expect(cfg['nested_dicts_added'], equals(ev));
      ev = ['a', 1, 'b', 2];
      expect(cfg['lists_added'], equals(ev));
      ev = [1, 2];
      expect(cfg['list[:2]'], equals(ev));
      ev = {'a': 'b'};
      expect(cfg['dicts_subtracted'], equals(ev));
      expect(cfg['nested_dicts_subtracted'], equals({}));
      ev = {
        'a_list': [
          1,
          2,
          {'a': 3}
        ],
        'a_map': {
          'k1': [
            'b',
            'c',
            {'d': 'e'}
          ]
        }
      };
      expect(cfg['dict_with_nested_stuff'], equals(ev));
      ev = [1, 2];
      expect(cfg['dict_with_nested_stuff.a_list[:2]'], equals(ev));
      expect(cfg['unary'], equals(-4));
      expect(cfg['abcdefghijkl'], equals('mno'));
      expect(cfg['power'], equals(8));
      expect(cfg['computed5'], equals(2.5));
      expect(cfg['computed6'], equals(2));
      expect(cfg['c3'], equals(Complex(3, 1)));
      expect(cfg['c4'], equals(Complex(5, 5)));
      expect(cfg['computed8'], equals(2));
      expect(cfg['computed9'], equals(160));
      expect(cfg['computed10'], equals(62));
      expect(cfg['dict.a'], equals('b'));

      // interpolation

      ev = 'A-4 a test_foo true 10 1e-7 1 b [a, c, e, g]Z';
      expect(cfg['interp'], equals(ev));
      expect(cfg['interp2'], equals('{a: b}'));

      // error cases

      var cases = [
        TestCase('bad_include',
            ErrorInfo(67, 17, '@ operand must be a string, but is 4 (int)')),
        TestCase('computed7',
            ErrorInfo(72, 16, 'Not found in configuration: float4')),
        TestCase('bad_interp',
            ErrorInfo(86, 15, "Unable to convert string '\${computed7}'")),
      ];

      for (var tcase in cases) {
        bool checkException(e) {
          bool result = false;

          if (e is ConfigException) {
            result = e.message == tcase.b.message &&
                e.loc == L(tcase.b.line, tcase.b.column);
          }
          return result;
        }

        expect(() => cfg[tcase.t], throwsA(checkException));
      }
    });

    test('forms', () {
      var p = dataFilePath('derived', 'forms.cfg');
      var cfg = Config();
      cfg.includePath.add(dataFilePath('base'));
      cfg.loadFile(p);

      var cases = [
        TestCase('modals.deletion.contents[0].id', 'frm-deletion'),
        TestCase('refs.delivery_address_field', {
          'placeholder': 'We need this for delivering to you',
          'name': 'postal_address',
          'attrs': {'minlength': 10},
          'grpclass': 'col-md-6',
          'kind': 'field',
          'type': 'textarea',
          'label': 'Postal address',
          'label_i18n': 'postal-address',
          'short_name': 'address',
          'ph_i18n': 'your-postal-address',
          'message': ' ',
          'required': true
        }),
        TestCase('refs.delivery_instructions_field', {
          'name': 'delivery_instructions',
          'label': 'Delivery Instructions',
          'label_i18n': 'delivery-instructions',
          'placeholder': 'Any special delivery instructions?',
          'ph_i18n': 'any-special-delivery-instructions',
          'grpclass': 'col-md-6',
          'kind': 'field',
          'type': 'textarea',
          'short_name': 'notes',
          'message': ' '
        }),
        TestCase('refs.verify_field', {
          'label': 'Verification code',
          'label_i18n': 'verification-code',
          'placeholder': 'Your verification code (NOT a backup code)',
          'ph_i18n': 'verification-not-backup-code',
          'attrs': {'minlength': 6, 'maxlength': 6, 'autofocus': true},
          'kind': 'field',
          'type': 'input',
          'name': 'verification_code',
          'short_name': 'verification code',
          'append': {
            'label': 'Verify',
            'type': 'submit',
            'classes': 'btn-primary'
          },
          'message': ' ',
          'required': true
        }),
        TestCase('refs.signup_password_field', {
          'required': true,
          'kind': 'field',
          'type': 'password',
          'name': 'password',
          'label': 'Password',
          'label_i18n': 'password',
          'placeholder': 'The password you want to use on this site',
          'ph_i18n': 'password-wanted-on-site',
          'message': ' ',
          'toggle': true
        }),
        TestCase('refs.signup_password_conf_field', {
          'required': true,
          'kind': 'field',
          'type': 'password',
          'name': 'password_conf',
          'label': 'Password confirmation',
          'label_i18n': 'password-confirmation',
          'placeholder': 'The same password, again, to guard against mistyping',
          'ph_i18n': 'same-password-again',
          'message': ' ',
          'toggle': true
        }),
        TestCase('fieldsets.signup_ident[0].contents[0]', {
          'attrs': {'autofocus': true},
          'grpclass': 'col-md-6',
          'kind': 'field',
          'type': 'input',
          'name': 'display_name',
          'label': 'Your name',
          'label_i18n': 'your-name',
          'placeholder': 'Your full name',
          'ph_i18n': 'your-full-name',
          'message': ' ',
          'data_source': 'user.display_name',
          'required': true
        }),
        TestCase('fieldsets.signup_ident[0].contents[1]', {
          'grpclass': 'col-md-6',
          'kind': 'field',
          'type': 'input',
          'name': 'familiar_name',
          'label': 'Familiar name',
          'label_i18n': 'familiar-name',
          'placeholder': 'If not just the first word in your full name',
          'ph_i18n': 'if-not-first-word',
          'data_source': 'user.familiar_name',
          'message': ' '
        }),
        TestCase('fieldsets.signup_ident[1].contents[0]', {
          'data_source': 'user.email',
          'grpclass': 'col-md-6',
          'label': 'Email address (used to sign in)',
          'kind': 'field',
          'type': 'email',
          'name': 'email',
          'label_i18n': 'email-address',
          'short_name': 'email address',
          'placeholder': 'Your email address',
          'ph_i18n': 'your-email-address',
          'message': ' ',
          'required': true
        }),
        TestCase('fieldsets.signup_ident[1].contents[1]', {
          'data_source': 'customer.mobile_phone',
          'name': 'mobile_phone',
          'grpclass': 'col-md-6',
          'kind': 'field',
          'type': 'input',
          'label': 'Phone number',
          'label_i18n': 'phone-number',
          'short_name': 'phone number',
          'placeholder': 'Your phone number',
          'ph_i18n': 'your-phone-number',
          'classes': 'numeric',
          'message': ' ',
          'prepend': {'icon': 'phone'},
          'attrs': {'maxlength': 10},
          'required': true
        }),
      ];

      for (var tcase in cases) {
        expect(cfg[tcase.t], equals(tcase.b));
      }
    });

    test('paths across includes', () {
      var p = dataFilePath('base', 'main.cfg');
      var cfg = Config.fromFile(p);

      expect(cfg['logging.appenders.file.filename'], equals('run/server.log'));
      expect(cfg['logging.appenders.file.append'], isTrue);
      expect(cfg['logging.appenders.error.filename'],
          equals('run/server-errors.log'));
      expect(cfg['logging.appenders.error.append'], isFalse);
      expect(
          cfg['redirects.freeotp.url'], equals('https://freeotp.github.io/'));
      expect(cfg['redirects.freeotp.permanent'], isFalse);
    });

    test('sources', () {
      var cases = [
        "foo[::2]",
        "foo[:]",
        "foo[:2]",
        "foo[2:]",
        "foo[::1]",
        "foo[::-1]",
        "foo[3]",
        "foo[\"bar\"]",
        "foo['bar']"
      ];

      for (var s in cases) {
        var node = parsePath(s);
        expect(toSource(node), equals(s));
      }
    });

    test('circular references', () {
      var p = dataFilePath('derived', 'test.cfg');
      var cfg = Config.fromFile(p);
      var cases = [
        TestCase('circ_list[1]',
            ErrorInfo(1, 1, 'Circular reference: circ_list[1] (42, 5)')),
        TestCase(
            'circ_map.a',
            ErrorInfo(1, 1,
                'Circular reference: circ_map.b (47, 8), circ_map.c (48, 8), circ_map.a (49, 8)')),
      ];

      for (var tcase in cases) {
        bool checkException(e) {
          bool result = false;

          if (e is CircularReferenceException) {
            result = e.message == tcase.b.message;
          }
          return result;
        }

        expect(() => cfg[tcase.t], throwsA(checkException));
      }
    });

    test('slices and indices', () {
      var p = dataFilePath('derived', 'test.cfg');
      var cfg = Config.fromFile(p);
      var theList = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];

      // slices

      var cases = [
        TestCase('test_list[:]', theList),
        TestCase('test_list[::]', theList),
        TestCase('test_list[:20]', theList),
        TestCase('test_list[-20:4]', ['a', 'b', 'c', 'd']),
        TestCase('test_list[-20:20]', theList),
        TestCase('test_list[2:]', ['c', 'd', 'e', 'f', 'g']),
        TestCase('test_list[-3:]', ['e', 'f', 'g']),
        TestCase('test_list[-2:2:-1]', ['f', 'e', 'd']),
        TestCase('test_list[::-1]', ['g', 'f', 'e', 'd', 'c', 'b', 'a']),
        TestCase('test_list[2:-2:2]', ['c', 'e']),
        TestCase('test_list[::2]', ['a', 'c', 'e', 'g']),
        TestCase('test_list[::3]', ['a', 'd', 'g']),
        TestCase('test_list[::2][::3]', ['a', 'g']),
      ];

      for (var tcase in cases) {
        expect(cfg[tcase.t], equals(tcase.b));
      }

      // indices

      var n = theList.length;
      for (var i = 0; i < n; i++) {
        expect(cfg['test_list[$i]'], equals(theList[i]));
      }

      // negative indices

      for (var i = n; i > 0; i--) {
        expect(cfg['test_list[-$i]'], equals(theList[n - i]));
      }

      // invalid indices

      for (var i in [n, n + 1, -(n + 1), -(n + 2)]) {
        bool checkException(e) {
          bool result = false;

          if (e is BadIndexException) {
            return e.message ==
                'Index out of range: is $i, must be between 0 and ${n - 1}';
          }
          return result;
        }

        expect(() => cfg['test_list[$i]'], throwsA(checkException));
      }
    });

    test('include paths', () {
      var p1 = dataFilePath('derived', 'test.cfg');
      var p2 = p.absolute(p1);

      for (var p in [p1, p2]) {
        var source = "test: @'${p.replaceAll('\\', '/')}'";
        var cfg = Config.fromSource(source);

        expect(cfg['test.computed6'], equals(2));
      }
    });

    test('nested include paths', () {
      var base = dataFilePath('base');
      var derived = dataFilePath('derived');
      var another = dataFilePath('another');
      var fn = p.join(base, 'top.cfg');
      var cfg = Config.fromFile(fn);
      cfg.includePath = [derived, another];
      expect(cfg['level1.level2.final'], equals(42));
    });

    test('recursive configuration', () {
      var p = dataFilePath('derived', 'recurse.cfg');
      var cfg = Config.fromFile(p);

      bool checkException(e) {
        bool result = false;

        if (e is ConfigException) {
          return e.message ==
                  'Configuration cannot include itself: recurse.cfg' &&
              e.loc == L(1, 11);
        }
        return result;
      }

      expect(() => cfg['recurse'], throwsA(checkException));
    });
  });
}
