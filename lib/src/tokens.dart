// ignore_for_file: constant_identifier_names, non_constant_identifier_names
import 'dart:io';
import 'package:complex/complex.dart';

class Location {
  int line;
  int column;

  Location(this.line, this.column);

  factory Location.instance() {
    return Location(1, 1);
  }

  void nextLine() {
    ++line;
    column = 1;
  }

  void nextCol() {
    ++column;
  }

  void prevCol() {
    if (column > 0) {
      --column;
    }
  }

  Location copy() {
    return Location(line, column);
  }

  void update(Location other) {
    line = other.line;
    column = other.column;
  }

  @override
  String toString() => '($line, $column)';

  @override
  bool operator ==(Object other) =>
      other is Location && other.line == line && other.column == column;

  @override
  int get hashCode => line.hashCode + column.hashCode;
}

abstract class RecognizerException implements Exception {
  String message;
  Location? loc;

  RecognizerException(this.message, this.loc);

  @override
  String toString() {
    String ls = loc == null ? '' : ' @ $loc';
    return '${runtimeType.toString()}$ls: $message';
  }
}

class TokenizerException extends RecognizerException {
  TokenizerException(String message, Location? loc) : super(message, loc);
}

class _PushbackInfo {
  String c;
  Location charLoc;
  Location loc;

  _PushbackInfo(this.c, this.charLoc, this.loc);
}

enum TokenKind {
  EOF,
  Word,
  Integer,
  Float,
  String,
  Newline,
  LeftCurly,
  RightCurly,
  LeftBracket,
  RightBracket,
  LeftParenthesis,
  RightParenthesis,
  LessThan,
  GreaterThan,
  LessThanOrEqual,
  GreaterThanOrEqual,
  Assign,
  Equal,
  Unequal,
  AltUnequal,
  LeftShift,
  RightShift,
  Dot,
  Comma,
  Colon,
  At,
  Plus,
  Minus,
  Star,
  Power,
  Slash,
  SlashSlash,
  Modulo,
  BackTick,
  Dollar,
  True,
  False,
  None,
  Is,
  In,
  Not,
  And,
  Or,
  BitwiseAnd,
  BitwiseOr,
  BitwiseXor,
  BitwiseComplement,
  Complex,
  IsNot,
  NotIn
}

abstract class ASTNode {
  final TokenKind kind;
  Location? start;
  Location? end;

  ASTNode(this.kind);
}

class Token extends ASTNode {
  String text;
  dynamic value;

  Token(kind, this.text, this.value) : super(kind);

  @override
  String toString() {
    return 'Token($kind:${repr(text)}:$value[$start-$end])';
  }

  @override
  int get hashCode {
    int result = text.hashCode;

    if (value != null) {
      result += value.hashCode;
    }
    if (start != null) {
      result += start!.line.hashCode + start!.column.hashCode;
    }
    if (end != null) {
      result += end!.line.hashCode + end!.column.hashCode;
    }
    return result;
  }

  @override
  bool operator ==(Object other) {
    bool result = other is Token &&
        kind == other.kind &&
        text == other.text &&
        value == other.value;
    if (result) {
      if (start != null) {
        result = start == other.start;
      }
      if (result && (end != null)) {
        result = end == other.end;
      }
    }
    if (!result) {
      print('*** $this|$other');
    }
    return result;
  }
}

const _PUNCTUATION = {
  ':': TokenKind.Colon,
  '-': TokenKind.Minus,
  '+': TokenKind.Plus,
  '*': TokenKind.Star,
  '/': TokenKind.Slash,
  '%': TokenKind.Modulo,
  ',': TokenKind.Comma,
  '{': TokenKind.LeftCurly,
  '}': TokenKind.RightCurly,
  '[': TokenKind.LeftBracket,
  ']': TokenKind.RightBracket,
  '(': TokenKind.LeftParenthesis,
  ')': TokenKind.RightParenthesis,
  '@': TokenKind.At,
  '\$': TokenKind.Dollar,
  '<': TokenKind.LessThan,
  '>': TokenKind.GreaterThan,
  '!': TokenKind.Not,
  '~': TokenKind.BitwiseComplement,
  '&': TokenKind.BitwiseAnd,
  '|': TokenKind.BitwiseOr,
  '^': TokenKind.BitwiseXor,
  '.': TokenKind.Dot,
  '=': TokenKind.Assign
};

const _KEYWORDS = {
  'true': TokenKind.True,
  'false': TokenKind.False,
  'null': TokenKind.None,
  'is': TokenKind.Is,
  'in': TokenKind.In,
  'not': TokenKind.Not,
  'and': TokenKind.And,
  'or': TokenKind.Or
};

const _KEYWORD_VALUES = {
  TokenKind.True: true,
  TokenKind.False: false,
  TokenKind.None: null
};

const _ESCAPES = {
  'a': '\u0007',
  'b': '\b',
  'f': '\u000C',
  'n': '\n',
  'r': '\r',
  't': '\t',
  'v': '\u000B',
  '\\': '\\',
  '\'': '\'',
  '"': '"'
};

class Stream {
  final String _content;
  int _pos = 0;
  int _len = 0;

  Stream(this._content) {
    _len = _content.length;
  }

  bool get atEnd => _pos >= _len;

  String read(int n) {
    if (_pos >= _len) {
      return '';
    }
    if ((_pos + n) >= _len) {
      n = _len - _pos;
    }
    var result = _content.substring(_pos, _pos + n);
    _pos += n;
    return result;
  }
}

bool inRange(String c, String lower, String higher) {
  return c.compareTo(lower) >= 0 && c.compareTo(higher) <= 0;
}

String repr(String s) {
  var result = '';
  for (var i = 0; i < s.length; i++) {
    var c = s[i];

    if (inRange(c, ' ', '~')) {
      if (c != '\'') {
        result += c;
      } else {
        result += '\\\'';
      }
    } else {
      var nc = c.codeUnitAt(0);

      switch (nc) {
        case 7:
          result += '\\a';
          break;
        case 8:
          result += '\\b';
          break;
        case 9:
          result += '\\t';
          break;
        case 10:
          result += '\\n';
          break;
        case 11:
          result += '\\v';
          break;
        case 12:
          result += '\\f';
          break;
        case 13:
          result += '\\r';
          break;
        default:
          result += '\\x${nc.toRadixString(16)}';
          break;
      }
    }
  }
  return '\'$result\'';
}

var _WS = RegExp(r"\s");

bool isWhitespace(String c) {
  return _WS.hasMatch(c);
}

var _LETTER = RegExp(r"\p{L}", unicode: true);

bool isLetter(String c) {
  return _LETTER.hasMatch(c);
}

var _DIGIT = RegExp(r"\p{Nd}", unicode: true);

bool isDigit(String c) {
  return _DIGIT.hasMatch(c);
}

var _HEXDIGIT = RegExp("[0-9a-fA-F]");
var _HEXDIGITS = RegExp(r'^[0-9a-fA-F]+$');

bool isHexDigit(String c) {
  return _HEXDIGIT.hasMatch(c);
}

var _LETTER_OR_DIGIT = RegExp(r"[\p{L}\p{Nd}]", unicode: true);

bool isLetterOrDigit(String c) {
  return _LETTER_OR_DIGIT.hasMatch(c);
}

var _NUMBER = RegExp(r"^[-]?\d+(\.\d*)?([eE][-+]?\d+)?[jJ]?$");

String _parseEscapes(String s, Location start) {
  var i = s.indexOf('\\');
  if (i < 0) {
    return s;
  }
  var failed = false;
  var n = s.length;
  var pos = 0;
  var result = '';
  var hp = '';

  while (!failed && (i >= 0)) {
    if (i > pos) {
      result += s.substring(pos, i);
    }
    if (i == (n - 1)) {
      failed = true;
      break;
    }
    var c = s[i + 1];
    if (_ESCAPES.containsKey(c)) {
      result += _ESCAPES[c]!;
      pos += 2;
    } else if ((c == 'x') || (c == 'X') || (c == 'u') || (c == 'U')) {
      int slen;

      if ((c == 'x') || (c == 'X')) {
        slen = 4;
      } else {
        slen = (c == 'u') ? 6 : 10;
      }
      if ((i + slen) > n) {
        failed = true;
        break;
      }
      hp = s.substring(i + 2, i + slen);
      if (!_HEXDIGITS.hasMatch(hp)) {
        failed = true;
        break;
      }
      var nc = int.parse(hp, radix: 16);
      if ((nc >= 0xd800) && nc <= 0xdfff) {
        failed = true;
        break;
      }
      if (nc >= 0x110000) {
        failed = true;
        break;
      }
      result += String.fromCharCode(nc);
      pos += slen;
    } else {
      failed = true;
      break;
    }
    i = s.indexOf('\\', pos);
  }
  if (failed) {
    Location loc = start.copy();
    if (hp != '') {
      hp = '\'$hp\' ';
    }
    throw TokenizerException(
        'Invalid escape sequence ${hp}at offset $i in ${repr(s)}', loc);
  }
  if (pos < n) {
    result += s.substring(pos);
  }
  return result;
}

class Tokenizer {
  final Stream _stream;
  final List<_PushbackInfo> _pushedBack = [];
  final Location _charLocation = Location.instance();
  final Location _location = Location.instance();

  Tokenizer(this._stream);

  factory Tokenizer.fromSource(String s) {
    return Tokenizer(Stream(s));
  }

  factory Tokenizer.fromFile(String p) {
    var file = File(p);
    var s = file.readAsStringSync();
    return Tokenizer(Stream(s));
  }

  String getChar() {
    String result;
    var n = _pushedBack.length;

    if (n > 0) {
      var pb = _pushedBack[n - 1];
      --_pushedBack.length;
      _charLocation.update(pb.charLoc);
      _location.update(pb.loc);
      result = pb.c;
    } else {
      _charLocation.update(_location);
      result = _stream.read(1);
      if (result == '\n') {
        _location.nextLine();
      } else if (result != '') {
        _location.nextCol();
      }
    }
    return result;
  }

  void pushBack(c) {
    if (c != '') {
      var pb = _PushbackInfo(c, _charLocation, _location);

      _pushedBack.add(pb);
    }
  }

  Token getToken() {
    var kind = TokenKind.EOF;
    var text = '';
    dynamic value;
    Location startLoc = Location.instance();
    Location endLoc = Location.instance();

    void getNumber() {
      kind = TokenKind.Integer;
      var inExponent = false;
      var radix = 0;
      var dotSeen = text.contains('.');
      var lastWasDigit = isDigit(text[text.length - 1]);
      String c;

      while (true) {
        c = getChar();
        if (c == '') {
          break;
        }
        if (c == '.') {
          dotSeen = true;
        }
        if (c == '_') {
          if (lastWasDigit) {
            text += c;
            endLoc.update(_charLocation);
            lastWasDigit = false;
            continue;
          }
          throw TokenizerException(
              "Invalid '_' in number: $text$c", _charLocation);
        }
        lastWasDigit = false; // unless set in one of the clauses below
        if (((radix == 0) && inRange(c, '0', '9')) ||
            ((radix == 2) && inRange(c, '0', '1')) ||
            ((radix == 8) && inRange(c, '0', '7')) ||
            ((radix == 16) && isHexDigit(c))) {
          text += c;
          endLoc.update(_charLocation);
          lastWasDigit = true;
        } else if (((c == 'o') ||
                (c == 'O') ||
                (c == 'x') ||
                (c == 'X') ||
                (c == 'b') ||
                (c == 'B')) &&
            ((text == '0') || (text == '-0'))) {
          radix = ((c == 'x') || (c == 'X'))
              ? 16
              : (((c == 'o') || (c == 'O')) ? 8 : 2);
          text += c;
          endLoc.update(_charLocation);
        } else if ((radix == 0) &&
            (c == '.') &&
            !inExponent &&
            !text.contains(c)) {
          text += c;
          endLoc.update(_charLocation);
        } else if ((radix == 0) &&
            (c == '-') &&
            !text.contains('-', 1) &&
            inExponent) {
          text += c;
          endLoc.update(_charLocation);
        } else if ((radix == 0) &&
            ((c == 'e') || (c == 'E')) &&
            !text.contains('e') &&
            !text.contains('E') &&
            (text[text.length - 1] != '_')) {
          text += c;
          endLoc.update(_charLocation);
          inExponent = true;
        } else {
          break;
        }
      }
      // Reached the end of the actual number part. Before checking
      // for complex, ensure that the last char wasn't an underscore.
      if (text[text.length - 1] == '_') {
        throw TokenizerException("Invalid '_' at end of number: $text", endLoc);
      }
      if ((radix == 0) && ((c == 'j') || (c == 'J'))) {
        text += c;
        endLoc.update(_charLocation);
        kind = TokenKind.Complex;
      } else {
        // not allowed to have a letter or digit which wasn't accepted
        if ((c != '.') && !isLetterOrDigit(c)) {
          pushBack(c);
        } else if (c != '') {
          var loc = _charLocation.copy();
          throw TokenizerException('Invalid character in number: $text$c', loc);
        }
      }
      var s = text.replaceAll('_', '');
      if (s[0] == '.') {
        s = '0' + s;
      } else if (s[0] == '-' && s[1] == '.') {
        s = '-0' + s.substring(1);
      }
      if (radix == 0 && !_NUMBER.hasMatch(s)) {
        throw TokenizerException('Badly formed number: $text', endLoc);
      }
      if (radix != 0) {
        value = int.parse(s.substring(2), radix: radix);
      } else if (kind == TokenKind.Complex) {
        var im = double.parse(s.substring(0, s.length - 1));
        value = Complex(0, im);
      } else if (inExponent || dotSeen) {
        kind = TokenKind.Float;
        try {
          value = double.parse(s);
        } catch (e) {
          throw TokenizerException(
              'Bad floating-point number: $text', startLoc);
        }
      } else {
        radix = (s[0] == '0') ? 8 : 10;
        try {
          value = int.parse(s, radix: radix);
        } catch (e) {
          var msg = radix == 8 ? "Bad octal constant" : "Bad integer number";
          throw TokenizerException('$msg: $text', startLoc);
        }
      }
    }

    while (true) {
      String c = getChar();
      startLoc.update(_charLocation);
      endLoc.update(_charLocation);

      if (c == '') {
        break;
      } else if (c == '#') {
        var nlSeen = false;

        text += c;
        while (true) {
          c = getChar();
          if (c == '') {
            break;
          } else if (c == '\n') {
            nlSeen = true;
            break;
          } else if (c != '\r') {
            text += c;
            continue;
          }
          c = getChar();
          if (c != '\n') {
            pushBack(c);
            break;
          }
          nlSeen = true;
          break;
        }
        kind = TokenKind.Newline;
        if (!nlSeen) {
          _location.nextLine();
        }
        endLoc.update(_location);
        break;
      } else if (c == '\n') {
        text += c;
        endLoc.update(_location);
        kind = TokenKind.Newline;
        break;
      } else if (c == '\r') {
        c = getChar();
        if (c != '\n') {
          pushBack(c);
          text += '\r';
        } else {
          text += c;
        }
        if (c != '\n') {
          // if we saw a newline, we bumped in getChar()
          endLoc.update(_location);
        }
        endLoc.nextLine();
        kind = TokenKind.Newline;
        break;
      } else if (isWhitespace(c)) {
        continue;
      } else if ((c == '_') || isLetter(c)) {
        kind = TokenKind.Word;
        text += c;
        endLoc.update(_charLocation);
        c = getChar();
        while ((c != '') && ((c == '_') || isLetterOrDigit(c))) {
          text += c;
          endLoc.update(_charLocation);
          c = getChar();
        }
        pushBack(c);
        if (_KEYWORDS.containsKey(text)) {
          kind = _KEYWORDS[text]!;
          if (_KEYWORD_VALUES.containsKey(kind)) {
            value = _KEYWORD_VALUES[kind];
          }
        }
        break;
      } else if (c == '`') {
        kind = TokenKind.BackTick;
        text += c;
        endLoc.update(_charLocation);
        while (true) {
          c = getChar();
          if (c == '') {
            break;
          }
          text += c;
          endLoc.update(_charLocation);
          if (c == '\r' || c == '\n') {
            throw TokenizerException(
                "Newlines not allowed in `-strings", _charLocation);
          }
          if (c == '`') {
            break;
          }
        }
        if (c == '') {
          throw TokenizerException("Unterminated `-string", _charLocation);
        }
        value = _parseEscapes(text.substring(1, text.length - 1), startLoc);
        break;
      } else if ((c == '"') || (c == "'")) {
        var quote = c;
        var multiLine = false;
        var escaped = false;

        kind = TokenKind.String;
        text += c;
        var c1 = getChar();
        var c1cLoc = _charLocation.copy();

        if (c1 != quote) {
          pushBack(c1);
        } else {
          var c2 = getChar();

          if (c2 != quote) {
            pushBack(c2);
            _charLocation.update(c1cLoc);
            pushBack(c1);
          } else {
            multiLine = true;
            text += quote + quote;
          }
        }
        var quoter = text;
        while (true) {
          c = getChar();
          if (c == '') {
            break;
          }
          text += c;
          endLoc.update(_charLocation);
          if (!multiLine && (c == '\r' || c == '\n')) {
            throw TokenizerException(
                "Newlines not allowed in single-line strings", _charLocation);
          }
          if ((c == quote) && !escaped) {
            var n = text.length;
            if (!multiLine ||
                (n >= 6) &&
                    (text.substring(n - 3) == quoter) &&
                    text[n - 4] != '\\') {
              break;
            }
          }
          escaped = (c == '\\') ? !escaped : false;
        }
        if (c == '') {
          var loc = _charLocation.copy();
          if (text[text.length - 1] == '\n') {
            loc.nextCol();
          }
          throw TokenizerException("Unterminated quoted string", loc);
        }
        var n = quoter.length;
        value = _parseEscapes(text.substring(n, text.length - n), startLoc);
        if (value == "") {
          // hack - revisit
          _charLocation.nextCol();
        }
        break;
      } else if (isDigit(c)) {
        text += c;
        endLoc.update(_charLocation);
        getNumber();
        break;
      } else if (_PUNCTUATION.containsKey(c)) {
        kind = _PUNCTUATION[c]!;
        text += c;
        endLoc.update(_charLocation);
        // if (c == ':' || c == '{') {
        //   print('*** $c|$_charLocation|$_location');
        // }
        if (c == '.') {
          c = getChar();
          if (!isDigit(c)) {
            pushBack(c);
          } else {
            text += c;
            endLoc.update(_charLocation);
            getNumber();
          }
        } else if (c == '=') {
          c = getChar();
          if (c != '=') {
            pushBack(c);
          } else {
            text += c;
            endLoc.update(_charLocation);
            kind = TokenKind.Equal;
          }
        } else if (c == '-') {
          c = getChar();
          if ((c != '.') && !isDigit(c)) {
            pushBack(c);
          } else {
            text += c;
            endLoc.update(_charLocation);
            getNumber();
          }
        } else if (c == '<') {
          var append = true;
          c = getChar();
          if (c == '=') {
            kind = TokenKind.LessThanOrEqual;
          } else if (c == '>') {
            kind = TokenKind.AltUnequal;
          } else if (c == '<') {
            kind = TokenKind.LeftShift;
          } else {
            append = false;
            pushBack(c);
          }
          if (append) {
            text += c;
            endLoc.update(_charLocation);
          }
        } else if (c == '>') {
          var append = true;
          c = getChar();
          if (c == '=') {
            kind = TokenKind.GreaterThanOrEqual;
          } else if (c == '>') {
            kind = TokenKind.RightShift;
          } else {
            append = false;
            pushBack(c);
          }
          if (append) {
            text += c;
            endLoc.update(_charLocation);
          }
        } else if (c == '!') {
          c = getChar();
          if (c != '=') {
            pushBack(c);
          } else {
            text += c;
            endLoc.update(_charLocation);
            kind = TokenKind.Unequal;
          }
        } else if (c == '/') {
          c = getChar();
          if (c != '/') {
            pushBack(c);
          } else {
            text += c;
            endLoc.update(_charLocation);
            kind = TokenKind.SlashSlash;
          }
        } else if (c == '*') {
          c = getChar();
          if (c != '*') {
            pushBack(c);
          } else {
            text += c;
            endLoc.update(_charLocation);
            kind = TokenKind.Power;
          }
        } else if ((c == '&') || (c == '|')) {
          var c2 = getChar();
          if (c2 != c) {
            pushBack(c2);
          } else {
            text += c;
            endLoc.update(_charLocation);
            kind = (c == '&') ? TokenKind.And : TokenKind.Or;
          }
        }
        break;
      } else if (c == '\\') {
        var cloc = _charLocation.copy();
        c = getChar();
        if (c == '\r') {
          c = getChar();
        }
        if (c != '\n') {
          throw TokenizerException('Unexpected character: \\', cloc);
        }
        endLoc.update(_charLocation);
        continue;
      } else {
        throw TokenizerException('Unexpected character: $c', _charLocation);
      }
    }
    var result = Token(kind, text, value);
    if (kind == TokenKind.Newline) {
      endLoc.prevCol();
    }
    result.start = startLoc;
    result.end = endLoc;
    // print('$result');
    return result;
  }

  List<Token> getAllTokens() {
    List<Token> result = [];

    while (true) {
      var t = getToken();

      result.add(t);
      if (t.kind == TokenKind.EOF) {
        break;
      }
    }
    return result;
  }
}
