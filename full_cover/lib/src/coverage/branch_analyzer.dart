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

    // The VM's own branch data (BRDA, from `--branch-coverage`) keyed by the
    // source line of each branch's entry token. The AST decides *which* branches
    // exist; this tells us whether each arm was taken — accurately even when the
    // arm body is a `return <literal>;` the VM omits from line data. We key by
    // line and keep the max so any covered path wins.
    final vmBranchHits = <int, int>{};
    for (final b in record.branches) {
      final hits = b.hits ?? 0;
      vmBranchHits.update(
        b.line,
        (v) => hits > v ? hits : v,
        ifAbsent: () => hits,
      );
    }
    final hasVmBranches = record.branches.isNotEmpty;

    // The AST is the structural source of truth. We do not adopt the VM's
    // branch *list* directly (it includes spurious function-entry entries), but
    // we do consult its hit counts per arm via [vmBranchHits].
    final parseResult = parseString(content: source, throwIfDiagnostics: false);
    final visitor = _BranchVisitor(
      lineHits,
      vmBranchHits,
      hasVmBranches,
      parseResult.lineInfo,
    );
    parseResult.unit.accept(visitor);

    // Backfill statement lines the VM omitted from its line data. The VM does
    // not emit a coverable position for some fall-through statements (e.g. a
    // bare `return <literal>;` reached only when the `if` above it is false),
    // which makes those lines silently absent rather than flagged. The branch
    // pass already derives how often control reached each such line, so we add
    // a DA entry for any inferred line the VM didn't report. We never override
    // real VM hits — only fill genuine gaps.
    var lines = _withBackfilledLines(record.lines, visitor.inferredLines);
    if (visitor.abstractLines.isNotEmpty) {
      lines = lines
          .where((l) => !visitor.abstractLines.contains(l.line))
          .toList();
    }

    // Strip blank lines — the VM never emits coverage for them, so any
    // injected zero-hit entries for blank lines are noise.
    final sourceLines = source.split('\n');
    lines = lines
        .where(
          (l) =>
              l.line < 1 ||
              l.line > sourceLines.length ||
              sourceLines[l.line - 1].trim().isNotEmpty,
        )
        .toList();

    return record.copyWith(
      lines: lines,
      branches: visitor.branches,
      functions: visitor.functions,
    );
  }

  List<LineData> _withBackfilledLines(
    List<LineData> vmLines,
    Map<int, int> inferred,
  ) {
    final existing = {for (final l in vmLines) l.line};
    final backfill = [
      for (final entry in inferred.entries)
        if (!existing.contains(entry.key)) LineData(entry.key, entry.value),
    ];
    if (backfill.isEmpty) return vmLines;
    return [...vmLines, ...backfill]..sort((a, b) => a.line.compareTo(b.line));
  }
}

class _BranchVisitor extends RecursiveAstVisitor<void> {
  final Map<int, int> lineHits;
  final Map<int, int> vmBranchHits;
  final bool hasVmBranches;
  final LineInfo lineInfo;
  final List<BranchData> branches = [];
  final List<FunctionData> functions = [];

  /// Lines the branch pass reached, mapped to their inferred hit count. Used to
  /// backfill statement lines the VM omitted from its line data.
  final Map<int, int> inferredLines = {};

  /// Lines belonging to abstract member declarations (EmptyFunctionBody).
  /// The VM sometimes emits coverable positions for these even though they
  /// have no executable body; they are stripped from line coverage.
  final Set<int> abstractLines = {};

  int _blockId = 0;

  _BranchVisitor(
    this.lineHits,
    this.vmBranchHits,
    this.hasVmBranches,
    this.lineInfo,
  );

  void _collectAbstractLines(AstNode node) {
    final start = _lineOf(node.beginToken.offset);
    final end = _lineOf(node.endToken.offset);
    for (var i = start; i <= end; i++) {
      abstractLines.add(i);
    }
  }

  /// Records [hits] for [line], keeping the highest count if it's seen more
  /// than once (any path that executed it wins over one that didn't).
  void _inferLine(int line, int hits) {
    final existing = inferredLines[line];
    if (existing == null || hits > existing) inferredLines[line] = hits;
  }

  // ------------------------------------------------------------------ helpers

  int _lineOf(int offset) => lineInfo.getLocation(offset).lineNumber;

  int _hitsAt(int line) => lineHits[line] ?? 0;

  /// The source line of an arm's entry token — a block's `{`, or the bare
  /// statement/expression itself. This is where the VM keys the arm's branch.
  int _entryLine(AstNode node) {
    if (node is Block) return _lineOf(node.leftBracket.offset);
    return _lineOf(node.beginToken.offset);
  }

  /// Hit count for a branch arm whose entry token is on [entryLine] and whose
  /// first executable line is [bodyLine].
  ///
  /// Prefers the VM's branch data (accurate even when [bodyLine] is a constant
  /// `return` the VM drops from line data); falls back to line hits when the VM
  /// has no branch entry for this arm (e.g. unit tests, or an implicit else).
  int _armHits(int entryLine, int bodyLine) {
    if (hasVmBranches) {
      final vm = vmBranchHits[entryLine] ?? vmBranchHits[bodyLine];
      if (vm != null) return vm;
    }
    return _hitsAt(bodyLine);
  }

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
      // Single-line if: `if (cond) statement;` (then sits on the decision line).
      if (elseNode != null) return; // can't infer for single-line if-else
      final block = _blockId++;
      final trueHits = _armHits(decisionLine, decisionLine);
      branches.add(BranchData(decisionLine, block, 0, trueHits));

      // The false arm is the fall-through to the next sibling statement. The VM
      // has no branch entry for an implicit else, so this relies on line hits —
      // and stays 0 when that sibling is itself a VM-omitted constant return.
      final nextLine = _nextSiblingLine(ifNode);
      if (nextLine == null) return; // last statement in block, no reference
      final falseHits = _armHits(nextLine, nextLine);
      branches.add(BranchData(decisionLine, block, 1, falseHits));
      _inferLine(nextLine, falseHits);
      return;
    }

    // Multi-line if: then-body starts on a different line.
    final block = _blockId++;
    final trueHits = _armHits(_entryLine(thenNode), thenLine);
    branches.add(BranchData(decisionLine, block, 0, trueHits));
    _inferLine(thenLine, trueHits);

    final elseLine = elseNode == null ? null : _firstLineOf(elseNode);
    if (elseNode != null && elseLine != null && elseLine != decisionLine) {
      // Else with a body on its own line: read its hits directly.
      final falseHits = _armHits(_entryLine(elseNode), elseLine);
      branches.add(BranchData(decisionLine, block, 1, falseHits));
      _inferLine(elseLine, falseHits);
    } else {
      // No else, or an else with no distinct body line (empty/same-line):
      // infer the false arm from how often the condition didn't take the then.
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
      final thenHits = _armHits(thenLine, thenLine);
      final elseHits = _armHits(elseLine, elseLine);
      branches.add(BranchData(condLine, block, 0, thenHits));
      branches.add(BranchData(condLine, block, 1, elseHits));
      if (thenLine != condLine) _inferLine(thenLine, thenHits);
      if (elseLine != condLine) _inferLine(elseLine, elseHits);
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

  /// Hit count for a function declared on [declLine] with [body].
  ///
  /// Uses the max of the declaration line and the first body line. The first
  /// body line alone is unreliable: the VM omits some statement positions (e.g.
  /// a bare `switch` keyword) so a clearly-executed function can read 0 there,
  /// while the function-entry position on the declaration line is recorded.
  int _functionHits(int declLine, FunctionBody body) {
    final declHits = _hitsAt(declLine);
    final bodyHits = _firstBodyHits(body);
    return declHits > bodyHits ? declHits : bodyHits;
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
    if (body is EmptyFunctionBody) {
      _collectAbstractLines(node);
    } else {
      final declLine = _lineOf(node.beginToken.offset);
      functions.add(
        FunctionData(
          node.name.lexeme,
          declLine,
          hits: _functionHits(declLine, body),
        ),
      );
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final body = node.body;
    if (body is EmptyFunctionBody) {
      _collectAbstractLines(node);
    } else {
      final typeName = _enclosingTypeName(node);
      final name = typeName.isNotEmpty
          ? '$typeName.${node.name.lexeme}'
          : node.name.lexeme;
      final declLine = _lineOf(node.beginToken.offset);
      functions.add(
        FunctionData(name, declLine, hits: _functionHits(declLine, body)),
      );
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
      final declLine = _lineOf(node.beginToken.offset);
      functions.add(
        FunctionData(name, declLine, hits: _functionHits(declLine, body)),
      );
    }
    super.visitConstructorDeclaration(node);
  }

  // ------------------------------------------------- compilation unit / directives

  @override
  void visitCompilationUnit(CompilationUnit node) {
    // Directives (import, export, library, part, part of) are not executable.
    for (final directive in node.directives) {
      _collectAbstractLines(directive);
    }
    super.visitCompilationUnit(node);
  }

  // ------------------------------------------------------ class declarations

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    super.visitClassDeclaration(node); // visit members first

    // Only strip the full class span for `abstract interface class` declarations.
    // A plain `abstract class` can mix abstract and concrete members and should
    // remain in coverage. Concrete classes may also have empty const constructors
    // (EmptyFunctionBody) that are executable — their spans must not be stripped.
    if (node.abstractKeyword == null || node.interfaceKeyword == null) return;

    // If an abstract class has no concrete members (all methods abstract, no
    // fields with initializers), mark its entire span so injected zero-coverage
    // entries are stripped and the record is dropped when otherwise empty.
    final hasConcreteMembers = node.body.members.any((m) {
      if (m is MethodDeclaration) return m.body is! EmptyFunctionBody;
      if (m is ConstructorDeclaration) {
        return m.body is! EmptyFunctionBody && m.redirectedConstructor == null;
      }
      if (m is FieldDeclaration) return true;
      return false;
    });

    if (!hasConcreteMembers) _collectAbstractLines(node);
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
        // The VM keys a switch arm at its `case`/`default` keyword.
        final hits = _armHits(_lineOf(member.beginToken.offset), firstLine);
        branches.add(BranchData(switchLine, block, branchIdx, hits));
        _inferLine(firstLine, hits);
      }
      branchIdx++;
    }

    super.visitSwitchStatement(node);
  }
}
