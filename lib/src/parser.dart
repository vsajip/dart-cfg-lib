// import 'dart:collection';
// ignore_for_file: non_constant_identifier_names

import 'dart:io';

import 'tokens.dart';

class ParserException extends RecognizerException {
  ParserException(String message, Location? loc) : super(message, loc);
}

Set<TokenKind> _VALUE_STARTERS = {
  TokenKind.Word,
  TokenKind.Integer,
  TokenKind.Float,
  TokenKind.Complex,
  TokenKind.String,
  TokenKind.BackTick,
  TokenKind.None,
  TokenKind.True,
  TokenKind.False
};

Set<TokenKind> _EXPRESSION_STARTERS = {
  TokenKind.Word,
  TokenKind.Integer,
  TokenKind.Float,
  TokenKind.Complex,
  TokenKind.String,
  TokenKind.BackTick,
  TokenKind.None,
  TokenKind.True,
  TokenKind.False,
  TokenKind.LeftCurly,
  TokenKind.LeftBracket,
  TokenKind.LeftParenthesis,
  TokenKind.At,
  TokenKind.Dollar,
  TokenKind.Plus,
  TokenKind.Minus,
  TokenKind.BitwiseComplement,
  TokenKind.Not
};

Set<TokenKind> _COMPARISON_OPERATORS = {
  TokenKind.LessThan,
  TokenKind.LessThanOrEqual,
  TokenKind.GreaterThan,
  TokenKind.GreaterThanOrEqual,
  TokenKind.Equal,
  TokenKind.Unequal,
  TokenKind.AltUnequal,
  TokenKind.Is,
  TokenKind.In,
  TokenKind.Not
};

// Set<TokenKind> _SCALAR_TOKENS = {
//   TokenKind.Integer,
//   TokenKind.Float,
//   TokenKind.Complex,
//   TokenKind.String,
//   TokenKind.None,
//   TokenKind.True,
//   TokenKind.False
// };

class UnaryNode extends ASTNode {
  final ASTNode operand;

  UnaryNode(TokenKind kind, this.operand) : super(kind);

  @override
  bool operator ==(Object other) {
    var result = false;
    if (other is UnaryNode) {
      return kind == other.kind && operand == other.operand;
    }
    if (!result) {
      print('*** $this|$other');
    }
    return result;
  }

  @override
  int get hashCode {
    return kind.hashCode + operand.hashCode;
  }

  @override
  String toString() {
    return 'UN($kind, $operand)';
  }
}

class BinaryNode extends ASTNode {
  final ASTNode lhs;
  final ASTNode rhs;

  BinaryNode(TokenKind kind, this.lhs, this.rhs) : super(kind);

  @override
  bool operator ==(Object other) {
    var result = false;
    if (other is BinaryNode) {
      return kind == other.kind && lhs == other.lhs && rhs == other.rhs;
    }
    if (!result) {
      print('*** $this|$other');
    }
    return result;
  }

  @override
  int get hashCode {
    return kind.hashCode + lhs.hashCode + rhs.hashCode;
  }

  @override
  String toString() {
    return 'BN($kind, $lhs, $rhs)';
  }
}

class ListNode extends ASTNode {
  final List<ASTNode> elements;

  ListNode(this.elements) : super(TokenKind.LeftBracket);

  @override
  bool operator ==(Object other) {
    var result = false;
    if (other is ListNode) {
      result = (elements.length == other.elements.length);
      if (result) {
        var n = elements.length;

        for (var i = 0; i < n; i++) {
          if (elements[i] != other.elements[i]) {
            result = false;
            break;
          }
        }
      }
    }
    return result;
  }

  @override
  int get hashCode {
    return elements.hashCode;
  }
}

class MappingEntry {
  final Token key;
  final ASTNode value;

  MappingEntry(this.key, this.value);

  @override
  bool operator ==(Object other) {
    var result = false;
    if (other is MappingEntry) {
      result = (key == other.key && value == other.value);
    }
    return result;
  }

  @override
  int get hashCode {
    return key.hashCode + value.hashCode;
  }
}

class MappingNode extends ASTNode {
  final List<MappingEntry> elements;

  MappingNode(this.elements) : super(TokenKind.LeftCurly);

  @override
  bool operator ==(Object other) {
    var result = false;
    if (other is MappingNode) {
      result = (elements.length == other.elements.length);
      if (result) {
        var n = elements.length;

        for (var i = 0; i < n; i++) {
          if (elements[i] != other.elements[i]) {
            result = false;
            break;
          }
        }
      }
    }
    return result;
  }

  @override
  int get hashCode {
    return elements.hashCode;
  }
}

class SliceNode extends ASTNode {
  final ASTNode? startIndex;
  final ASTNode? stopIndex;
  final ASTNode? step;

  SliceNode(this.startIndex, this.stopIndex, this.step)
      : super(TokenKind.Colon);

  @override
  bool operator ==(Object other) {
    var result = false;
    if (other is SliceNode) {
      result = (startIndex == other.startIndex) &&
          (stopIndex == other.stopIndex) &&
          (step == other.step);
    }
    return result;
  }

  @override
  int get hashCode {
    return startIndex.hashCode + stopIndex.hashCode + step.hashCode;
  }
}

class _TrailerResult {
  final TokenKind _op;
  final ASTNode _operand;

  _TrailerResult(this._op, this._operand);
}

class Parser {
  late final Tokenizer _tokenizer;
  late Token _next;

  Parser(Tokenizer tokenizer) {
    _tokenizer = tokenizer;
    _next = _tokenizer.getToken();
  }

  Parser.fromStream(Stream stream) : this(Tokenizer(stream));
  Parser.fromSource(String source) : this.fromStream(Stream(source));
  Parser.fromFile(String path) : this.fromSource(File(path).readAsStringSync());

  bool get atEnd => _next.kind == TokenKind.EOF;
  Location get position => _next.start!;

  TokenKind _advance() {
    _next = _tokenizer.getToken();
    return _next.kind;
  }

  Token _expect(TokenKind kind) {
    if (_next.kind != kind) {
      throw ParserException(
          'Expected $kind but got ${_next.kind}', _next.start);
    }
    var result = _next;
    _advance();
    return result;
  }

  TokenKind _consumeNewlines() {
    var result = _next.kind;
    while (result == TokenKind.Newline) {
      result = _advance();
    }
    return result;
  }

  Token _strings() {
    var result = _next;

    assert(result.kind == TokenKind.String);

    if (_advance() == TokenKind.String) {
      var allText = '';
      var allValue = '';
      TokenKind k;
      Location end;
      var t = result.text;
      var v = result.value as String;
      var start = result.start;

      do {
        allText += t;
        allValue += v;
        t = _next.text;
        v = _next.value as String;
        end = _next.end!;
        k = _advance();
      } while (k == TokenKind.String);
      allText += t;
      allValue += v;
      result = Token(TokenKind.String, allText, allValue);
      result.start = start!.copy();
      result.end = end.copy();
    }
    return result;
  }

  Token value() {
    var kind = _next.kind;
    Token result;

    if (!_VALUE_STARTERS.contains(kind)) {
      throw ParserException('Unexpected for value: $kind', _next.start);
    }
    if (kind == TokenKind.String) {
      result = _strings();
    } else {
      result = _next;
      _advance();
    }
    return result;
  }

  ASTNode atom() {
    ASTNode result;
    var kind = _next.kind;

    switch (kind) {
      case TokenKind.LeftCurly:
        result = mapping();
        break;
      case TokenKind.LeftBracket:
        result = _list();
        break;
      case TokenKind.Dollar:
        _advance();
        _expect(TokenKind.LeftCurly);
        var spos = _next.start;
        result = UnaryNode(TokenKind.Dollar, primary());
        result.start = spos;
        _expect(TokenKind.RightCurly);
        break;
      case TokenKind.LeftParenthesis:
        _advance();
        result = expr();
        _expect(TokenKind.RightParenthesis);
        break;
      default:
        result = value();
        break;
    }
    return result;
  }

  _TrailerResult _trailer() {
    ASTNode? result; // always assigned but compiler can't see this
    var op = _next.kind;
    var start = _next.start;

    void invalidIndex(int n, Location pos) {
      var msg = 'Invalid index at $pos: expected 1 expression, found $n';
      throw ParserException(msg, pos);
    }

    if (op != TokenKind.LeftBracket) {
      _expect(TokenKind.Dot);
      result = _expect(TokenKind.Word);
    } else {
      var kind = _advance();
      var isSlice = false;
      ASTNode? startIndex, stopIndex, step;

      ASTNode getSliceElement() {
        var lb = _listBody();
        var size = lb.elements.length;

        if (size != 1) {
          invalidIndex(size, lb.start!);
        }
        return lb.elements[0];
      }

      void tryGetStep() {
        var kind = _advance();
        if (kind != TokenKind.RightBracket) {
          step = getSliceElement();
        }
      }

      if (kind == TokenKind.Colon) {
        // it's a slice like [:xyz:abc]
        isSlice = true;
      } else {
        var elem = getSliceElement();

        kind = _next.kind;
        if (kind != TokenKind.Colon) {
          result = elem;
        } else {
          startIndex = elem;
          isSlice = true;
        }
      }
      if (isSlice) {
        // at this point startIndex is either null (if foo[:xyz]) or a
        // value representing the start. We are pointing at the COLON
        // after the start value
        kind = _advance();
        if (kind == TokenKind.Colon) {
          tryGetStep();
        } else if (kind != TokenKind.RightBracket) {
          stopIndex = getSliceElement();
          kind = _next.kind;
          if (kind == TokenKind.Colon) {
            tryGetStep();
          }
        }
        op = TokenKind.Colon;
        result = SliceNode(startIndex, stopIndex, step);
        result.start = start;
      }
      _expect(TokenKind.RightBracket);
    }
    return _TrailerResult(op, result!);
  }

  ASTNode primary() {
    var result = atom();
    var kind = _next.kind;

    while ((kind == TokenKind.Dot) || (kind == TokenKind.LeftBracket)) {
      var t = _trailer();
      result = BinaryNode(t._op, result, t._operand);
      kind = _next.kind;
    }
    return result;
  }

  Token mappingKey() {
    Token result;

    if (_next.kind == TokenKind.String) {
      result = _strings();
    } else {
      result = _next;
      _advance();
    }
    return result;
  }

  MappingNode mappingBody() {
    List<MappingEntry> elements = [];
    var kind = _consumeNewlines();
    if (kind != TokenKind.RightCurly &&
        kind != TokenKind.EOF &&
        kind != TokenKind.Word &&
        kind != TokenKind.String) {
      throw ParserException("Unexpected for key: $kind", _next.start);
    }
    var spos = _next.start;
    while (kind == TokenKind.Word || kind == TokenKind.String) {
      var key = mappingKey();
      kind = _next.kind;
      if (kind != TokenKind.Colon && kind != TokenKind.Assign) {
        throw ParserException(
            "Expected key-value separator but got $kind", _next.start);
      }
      _advance();
      _consumeNewlines();
      var me = MappingEntry(key, expr());
      elements.add(me);
      kind = _next.kind;
      if (kind == TokenKind.Newline || kind == TokenKind.Comma) {
        _advance();
        kind = _consumeNewlines();
      }
    }
    var result = MappingNode(elements);
    result.start = spos;
    return result;
  }

  MappingNode mapping() {
    _expect(TokenKind.LeftCurly);
    var result = mappingBody();
    _expect(TokenKind.RightCurly);
    return result;
  }

  ListNode _listBody() {
    List<ASTNode> elements = [];
    var kind = _consumeNewlines();
    var spos = _next.start;

    while (_EXPRESSION_STARTERS.contains(kind)) {
      elements.add(expr());
      kind = _next.kind;
      if (kind != TokenKind.Newline && kind != TokenKind.Comma) {
        break;
      }
      _advance();
      kind = _consumeNewlines();
    }
    var result = ListNode(elements);
    result.start = spos;
    return result;
  }

  ListNode _list() {
    _expect(TokenKind.LeftBracket);
    var result = _listBody();
    _expect(TokenKind.RightBracket);
    return result;
  }

  ASTNode container() {
    var kind = _consumeNewlines();
    ASTNode result;

    if (kind == TokenKind.LeftCurly) {
      result = mapping();
    } else if (kind == TokenKind.LeftBracket) {
      result = _list();
    } else if (kind == TokenKind.Word ||
        kind == TokenKind.String ||
        kind == TokenKind.EOF) {
      result = mappingBody();
    } else {
      throw ParserException("Unexpected for container: $kind", _next.start);
    }
    _consumeNewlines();
    return result;
  }

  ASTNode _power() {
    var result = primary();

    while (_next.kind == TokenKind.Power) {
      _advance();
      result = BinaryNode(TokenKind.Power, result, unaryExpr());
    }
    return result;
  }

  ASTNode unaryExpr() {
    ASTNode result;
    var kind = _next.kind;
    var spos = _next.start;

    if ((kind != TokenKind.Plus) &&
        (kind != TokenKind.Minus) &&
        (kind != TokenKind.BitwiseComplement) &&
        (kind != TokenKind.At)) {
      result = _power();
    } else {
      _advance();
      result = UnaryNode(kind, unaryExpr());
    }
    result.start = spos;
    return result;
  }

  ASTNode _mulExpr() {
    var result = unaryExpr();
    var kind = _next.kind;

    while ((kind == TokenKind.Star) ||
        (kind == TokenKind.Slash) ||
        (kind == TokenKind.SlashSlash) ||
        (kind == TokenKind.Modulo)) {
      _advance();
      result = BinaryNode(kind, result, unaryExpr());
      kind = _next.kind;
    }
    return result;
  }

  ASTNode _addExpr() {
    var result = _mulExpr();
    var kind = _next.kind;

    while ((kind == TokenKind.Plus) || (kind == TokenKind.Minus)) {
      _advance();
      result = BinaryNode(kind, result, _mulExpr());
      kind = _next.kind;
    }
    return result;
  }

  ASTNode _shiftExpr() {
    var result = _addExpr();
    var kind = _next.kind;

    while ((kind == TokenKind.LeftShift) || (kind == TokenKind.RightShift)) {
      _advance();
      result = BinaryNode(kind, result, _addExpr());
      kind = _next.kind;
    }
    return result;
  }

  ASTNode _bitandExpr() {
    var result = _shiftExpr();

    while (_next.kind == TokenKind.BitwiseAnd) {
      _advance();
      result = BinaryNode(TokenKind.BitwiseAnd, result, _shiftExpr());
    }
    return result;
  }

  ASTNode _bitxorExpr() {
    var result = _bitandExpr();

    while (_next.kind == TokenKind.BitwiseXor) {
      _advance();
      result = BinaryNode(TokenKind.BitwiseXor, result, _bitandExpr());
    }
    return result;
  }

  ASTNode _bitorExpr() {
    var result = _bitxorExpr();

    while (_next.kind == TokenKind.BitwiseOr) {
      _advance();
      result = BinaryNode(TokenKind.BitwiseOr, result, _bitxorExpr());
    }
    return result;
  }

  TokenKind _compOp() {
    var result = _next.kind;
    var shouldAdvance = false;
    var nk = _advance();

    if (result == TokenKind.Is && nk == TokenKind.Not) {
      result = TokenKind.IsNot;
      shouldAdvance = true;
    } else if (result == TokenKind.Not && nk == TokenKind.In) {
      result = TokenKind.NotIn;
      shouldAdvance = true;
    }
    if (shouldAdvance) {
      _advance();
    }
    return result;
  }

  ASTNode _comparison() {
    var result = _bitorExpr();

    if (_COMPARISON_OPERATORS.contains(_next.kind)) {
      var op = _compOp();
      result = BinaryNode(op, result, _bitorExpr());
    }
    return result;
  }

  ASTNode _notExpr() {
    if (_next.kind != TokenKind.Not) {
      return _comparison();
    }
    _advance();
    return UnaryNode(TokenKind.Not, _notExpr());
  }

  ASTNode _andExpr() {
    var result = _notExpr();

    while (_next.kind == TokenKind.And) {
      _advance();
      result = BinaryNode(TokenKind.And, result, _notExpr());
    }
    return result;
  }

  ASTNode expr() {
    var result = _andExpr();

    while (_next.kind == TokenKind.Or) {
      _advance();
      result = BinaryNode(TokenKind.Or, result, _andExpr());
    }
    return result;
  }
}
