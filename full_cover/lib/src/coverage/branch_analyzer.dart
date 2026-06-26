import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'lcov_record.dart';

/// Replaces the branch data in [record] with condition-level branch data
/// derived by parsing the source file's AST and correlating with line hits.
///
/// The Dart VM's branch coverage is line-level only. This analyzer walks
/// the AST to find every decision point (if/else, ternary, switch) and infers
/// which branches were taken from the line-hit counts.
///
/// If analysis produces no branches (e.g. the file has no decision points the
/// analyzer can handle), the original VM-level branch data is preserved rather
/// than replaced with an empty list.
class BranchAnalyzer {
  LcovRecord analyze(LcovRecord record) {
    final file = File(record.sourceFile);
    if (!file.existsSync()) return record;

    String source;
    try {
      source = file.readAsStringSync();
    } catch (_) {
      return record;
    }

    final lineHits = <int, int>{for (final l in record.lines) l.line: l.hits};

    // Parsing succeeded — the AST is the source of truth from here.
    // An empty visitor.branches means the file has no decision points, which
    // is correct (branchesFound = 0). We do NOT fall back to VM data because
    // the VM emits spurious BRDA entries for function entry points that are
    // not condition-level branches.
    final parseResult = parseString(content: source, throwIfDiagnostics: false);
    final visitor = _BranchVisitor(lineHits, parseResult.lineInfo);
    parseResult.unit.accept(visitor);
    return record.copyWith(
      branches: visitor.branches,
      functions: visitor.functions,
    );
  }
}

class _BranchVisitor extends RecursiveAstVisitor<void> {
  final Map<int, int> lineHits;
  final LineInfo lineInfo;
  final List<BranchData> branches = [];
  final List<FunctionData> functions = [];

  int _blockId = 0;

  _BranchVisitor(this.lineHits, this.lineInfo);

  // ------------------------------------------------------------------ helpers

  int _lineOf(int offset) => lineInfo.getLocation(offset).lineNumber;

  int _hitsAt(int line) => lineHits[line] ?? 0;

  /// Returns the first executable line inside [node], or null for an empty block.
  int? _firstLineOf(AstNode node) {
    if (node is Block) {
      if (node.statements.isEmpty) return null;
      return _lineOf(node.statements.first.beginToken.offset);
    }
    return _lineOf(node.beginToken.offset);
  }

  /// Returns the first line of the statement that follows [node] in its
  /// parent [Block], or null when there is no such sibling.
  ///
  /// Used to infer the false-branch hit count for single-line `if` statements
  /// such as `if (guard) throw ...;` where the then-body sits on the same line
  /// as the `if` keyword.
  int? _nextSiblingLine(AstNode node) {
    final parent = node.parent;
    if (parent is Block) {
      final stmts = parent.statements;
      final idx = stmts.indexOf(node as Statement);
      if (idx >= 0 && idx + 1 < stmts.length) {
        return _lineOf(stmts[idx + 1].beginToken.offset);
      }
    }
    if (parent is SwitchMember) {
      final stmts = parent.statements;
      final idx = stmts.indexOf(node as Statement);
      if (idx >= 0 && idx + 1 < stmts.length) {
        return _lineOf(stmts[idx + 1].beginToken.offset);
      }
    }
    return null;
  }

  // ---------------------------------------------------------- if / if-element

  void _analyzeIf({
    required AstNode ifNode,
    required int decisionLine,
    required AstNode thenNode,
    required AstNode? elseNode,
  }) {
    final thenLine = _firstLineOf(thenNode);

    if (thenLine == null || thenLine == decisionLine) {
      // Single-line if: `if (cond) statement;`
      // We can't read the true-branch hit directly, but we can infer it from
      // how many times execution fell through to the next sibling statement.
      //   false_hits = hits on next statement (condition evaluated to false)
      //   true_hits  = condition_hits - false_hits
      if (elseNode != null) return; // can't infer for single-line if-else
      final nextLine = _nextSiblingLine(ifNode);
      if (nextLine == null) {
        return; // last statement in block, no reference point
      }
      final condHits = _hitsAt(decisionLine);
      final falseHits = _hitsAt(nextLine);
      final trueHits = (condHits - falseHits).clamp(0, condHits);
      final block = _blockId++;
      branches.add(BranchData(decisionLine, block, 0, trueHits));
      branches.add(BranchData(decisionLine, block, 1, falseHits));
      return;
    }

    // Multi-line if: then-body starts on a different line.
    final block = _blockId++;
    final trueHits = _hitsAt(thenLine);
    branches.add(BranchData(decisionLine, block, 0, trueHits));

    if (elseNode != null) {
      final elseLine = _firstLineOf(elseNode);
      final falseHits = (elseLine != null && elseLine != decisionLine)
          ? _hitsAt(elseLine)
          : (_hitsAt(decisionLine) - trueHits).clamp(0, _hitsAt(decisionLine));
      branches.add(BranchData(decisionLine, block, 1, falseHits));
    } else {
      final condHits = _hitsAt(decisionLine);
      branches.add(
        BranchData(
          decisionLine,
          block,
          1,
          (condHits - trueHits).clamp(0, condHits),
        ),
      );
    }
  }

  @override
  void visitIfStatement(IfStatement node) {
    _analyzeIf(
      ifNode: node,
      decisionLine: _lineOf(node.beginToken.offset),
      thenNode: node.thenStatement,
      elseNode: node.elseStatement,
    );
    super.visitIfStatement(node);
  }

  @override
  void visitIfElement(IfElement node) {
    _analyzeIf(
      ifNode: node,
      decisionLine: _lineOf(node.beginToken.offset),
      thenNode: node.thenElement,
      elseNode: node.elseElement,
    );
    super.visitIfElement(node);
  }

  // -------------------------------------------------------- ternary  ? :

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    final condLine = _lineOf(node.question.offset);
    final thenLine = _lineOf(node.thenExpression.beginToken.offset);
    final elseLine = _lineOf(node.elseExpression.beginToken.offset);

    // Only emit branches when sub-expressions are on distinct lines from the `?`.
    if (thenLine != condLine || elseLine != condLine) {
      final block = _blockId++;
      branches.add(BranchData(condLine, block, 0, _hitsAt(thenLine)));
      branches.add(BranchData(condLine, block, 1, _hitsAt(elseLine)));
    }

    super.visitConditionalExpression(node);
  }

  // -------------------------------------------------- function declarations

  String _enclosingTypeName(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is ClassDeclaration) return current.namePart.typeName.lexeme;
      if (current is MixinDeclaration) return current.name.lexeme;
      if (current is ExtensionDeclaration) return current.name?.lexeme ?? '';
      if (current is EnumDeclaration) return current.namePart.typeName.lexeme;
      current = current.parent;
    }
    return '';
  }

  int _firstBodyHits(FunctionBody body) {
    if (body is BlockFunctionBody) {
      if (body.block.statements.isNotEmpty) {
        return _hitsAt(_lineOf(body.block.statements.first.beginToken.offset));
      }
      return 0;
    }
    if (body is ExpressionFunctionBody) {
      return _hitsAt(_lineOf(body.expression.beginToken.offset));
    }
    return 0;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final body = node.functionExpression.body;
    if (body is! EmptyFunctionBody) {
      final fn = FunctionData(
        node.name.lexeme,
        _lineOf(node.beginToken.offset),
        hits: _firstBodyHits(body),
      );
      functions.add(fn);
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final body = node.body;
    if (body is! EmptyFunctionBody) {
      final typeName = _enclosingTypeName(node);
      final name = typeName.isNotEmpty
          ? '$typeName.${node.name.lexeme}'
          : node.name.lexeme;
      final fn = FunctionData(
        name,
        _lineOf(node.beginToken.offset),
        hits: _firstBodyHits(body),
      );
      functions.add(fn);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final body = node.body;
    if (body is! EmptyFunctionBody && node.redirectedConstructor == null) {
      final typeName = _enclosingTypeName(node);
      final ctorSuffix = node.name?.lexeme;
      final name = ctorSuffix != null ? '$typeName.$ctorSuffix' : typeName;
      final fn = FunctionData(
        name,
        _lineOf(node.beginToken.offset),
        hits: _firstBodyHits(body),
      );
      functions.add(fn);
    }
    super.visitConstructorDeclaration(node);
  }

  // -------------------------------------------------------- switch

  @override
  void visitSwitchStatement(SwitchStatement node) {
    final switchLine = _lineOf(node.beginToken.offset);
    final block = _blockId++;

    var branchIdx = 0;
    for (final member in node.members) {
      final firstLine = member.statements.isNotEmpty
          ? _lineOf(member.statements.first.beginToken.offset)
          : null;
      if (firstLine != null) {
        branches.add(
          BranchData(switchLine, block, branchIdx, _hitsAt(firstLine)),
        );
      }
      branchIdx++;
    }

    super.visitSwitchStatement(node);
  }
}
