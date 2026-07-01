import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'lcov_record.dart';

/// Replaces [record]'s branch data with condition-level data inferred from
/// the AST and line hits — the VM's own branch coverage is line-level only.
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

    // VM branch data (BRDA) keyed by entry line, max hits kept per line — the
    // AST decides which branches exist; this tells us if an arm was taken,
    // accurately even when its body is a `return <literal>;` the VM drops.
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

    // The AST decides which branches exist; the VM's own list isn't used
    // directly (it includes spurious function-entry entries).
    final parseResult = parseString(content: source, throwIfDiagnostics: false);
    final visitor = _BranchVisitor(
      lineHits,
      vmBranchHits,
      hasVmBranches,
      parseResult.lineInfo,
    );
    parseResult.unit.accept(visitor);

    // Backfill fall-through statement lines the VM silently omits (e.g. a
    // bare `return <literal>;`), using hit counts the branch pass already
    // derived. Never overrides real VM hits — only fills genuine gaps.
    var lines = _withBackfilledLines(record.lines, visitor.inferredLines);
    final linesToStrip = {
      ...visitor.abstractLines,
      ...visitor.misattributedLines,
      ...visitor.typeHeaderLines,
      ...visitor.tryHeaderLines,
    };
    if (linesToStrip.isNotEmpty) {
      lines = lines.where((l) => !linesToStrip.contains(l.line)).toList();
    }

    // Strip blank lines, full-line comments, and closing-punctuation-only
    // lines (e.g. a bare `}`) — the VM never emits real positions for these,
    // so any zero-hit entry here is an injection/backfill artifact.
    final sourceLines = source.split('\n');
    lines = lines
        .where(
          (l) =>
              l.line < 1 ||
              l.line > sourceLines.length ||
              !_isNonExecutableSourceLine(sourceLines[l.line - 1]),
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

final _fullLineComment = RegExp(r'^//');
final _punctuationOnly = RegExp(r'^[)\]}\s;,]*$');

/// True for a line that can never be a real VM position: blank, a full-line
/// `//` comment, or only closing punctuation (e.g. a bare `}` or `});`).
bool _isNonExecutableSourceLine(String rawLine) {
  final trimmed = rawLine.trim();
  if (trimmed.isEmpty) return true;
  if (_fullLineComment.hasMatch(trimmed)) return true;
  return _punctuationOnly.hasMatch(trimmed);
}

class _BranchVisitor extends RecursiveAstVisitor<void> {
  final Map<int, int> lineHits;
  final Map<int, int> vmBranchHits;
  final bool hasVmBranches;
  final LineInfo lineInfo;
  final List<BranchData> branches = [];
  final List<FunctionData> functions = [];

  /// Lines the branch pass reached, for backfilling lines the VM omitted.
  final Map<int, int> inferredLines = {};

  /// Lines of abstract members (EmptyFunctionBody) to strip from coverage —
  /// the VM sometimes emits positions for these despite no executable body.
  final Set<int> abstractLines = {};

  /// Lines the VM hit-tagged on a preceding annotation (e.g. `@override`) or
  /// doc comment instead of the actual declaration below it — stripped once
  /// their hit count has been relocated onto the real declaration line.
  final Set<int> misattributedLines = {};

  /// A type declaration's own header (signature through the opening `{`)
  /// and closing `}` lines — never themselves an executable position.
  final Set<int> typeHeaderLines = {};

  /// `try {`, untyped `catch (e) {`, and `finally {` header lines — the VM
  /// never emits a real position for these (unlike a typed `on X {` clause,
  /// which does get one to report whether that arm was entered), so any hit
  /// here is a synthetic zero-fill artifact from cross-package coverage.
  final Set<int> tryHeaderLines = {};

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

  /// Marks [node]'s header (signature through [body]'s opening `{`) and
  /// [body]'s closing `}` as non-executable structural lines.
  void _collectTypeHeaderLines(AnnotatedNode node, AstNode body) {
    final headerStart = _lineOf(node.firstTokenAfterCommentAndMetadata.offset);
    final headerEnd = _lineOf(body.beginToken.offset);
    for (var i = headerStart; i <= headerEnd; i++) {
      typeHeaderLines.add(i);
    }
    typeHeaderLines.add(_lineOf(body.endToken.offset));
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

  /// Hit count for a branch arm entering at [entryLine] with body [bodyLine].
  /// Prefers VM branch data (accurate even for a dropped constant `return`),
  /// falling back to line hits when the VM has no entry for this arm.
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

  /// First line of the statement following [node] in its parent [Block], or
  /// null if none — used to infer the false-branch hits for single-line
  /// `if`s like `if (guard) throw ...;`.
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

      // False arm falls through to the next sibling statement (no VM entry
      // for an implicit else, so this relies on line hits).
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
      // No else (or no distinct body line): infer from condition vs then hits.
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

  /// Max of decl-line, relocated-annotation-line and first-body-line hits —
  /// the body line alone is unreliable (the VM omits some statement
  /// positions, e.g. a bare `switch`).
  int _functionHits(int declLine, int relocatedHits, FunctionBody body) {
    final declHits = _hitsAt(declLine);
    final bodyHits = _firstBodyHits(body);
    var best = declHits > bodyHits ? declHits : bodyHits;
    if (relocatedHits > best) best = relocatedHits;
    return best;
  }

  /// [node]'s beginToken includes any doc comment/annotations (e.g.
  /// `@override`), so the VM's own coverage sometimes hit-tags that line
  /// instead of [declLine]. If so, relocate the hit onto [declLine] and mark
  /// the annotation line for stripping.
  int _relocateAnnotationHit(AnnotatedNode node, int declLine) {
    final annotationLine = _lineOf(node.beginToken.offset);
    if (annotationLine == declLine) return 0;
    final hits = lineHits[annotationLine];
    if (hits == null) return 0;
    misattributedLines.add(annotationLine);
    _inferLine(declLine, hits);
    return hits;
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
      final declLine = _lineOf(node.firstTokenAfterCommentAndMetadata.offset);
      final relocatedHits = _relocateAnnotationHit(node, declLine);
      functions.add(
        FunctionData(
          node.name.lexeme,
          declLine,
          hits: _functionHits(declLine, relocatedHits, body),
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
      final declLine = _lineOf(node.firstTokenAfterCommentAndMetadata.offset);
      final relocatedHits = _relocateAnnotationHit(node, declLine);
      functions.add(
        FunctionData(
          name,
          declLine,
          hits: _functionHits(declLine, relocatedHits, body),
        ),
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
      final declLine = _lineOf(node.firstTokenAfterCommentAndMetadata.offset);
      final relocatedHits = _relocateAnnotationHit(node, declLine);
      functions.add(
        FunctionData(
          name,
          declLine,
          hits: _functionHits(declLine, relocatedHits, body),
        ),
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
    _collectTypeHeaderLines(node, node.body);
    super.visitClassDeclaration(node); // visit members first

    // Only `abstract interface class` can be fully stripped — a plain
    // `abstract class` may mix in concrete (executable) members.
    if (node.abstractKeyword == null || node.interfaceKeyword == null) return;

    // No concrete members: mark the whole span so it's dropped when empty.
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

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _collectTypeHeaderLines(node, node.body);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _collectTypeHeaderLines(node, node.body);
    super.visitEnumDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _collectTypeHeaderLines(node, node.body);
    super.visitExtensionDeclaration(node);
  }

  // -------------------------------------------------------- try / catch

  @override
  void visitTryStatement(TryStatement node) {
    tryHeaderLines.add(_lineOf(node.tryKeyword.offset));
    final finallyKeyword = node.finallyKeyword;
    if (finallyKeyword != null) {
      tryHeaderLines.add(_lineOf(finallyKeyword.offset));
    }
    super.visitTryStatement(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    // Only the untyped form (`catch (e) {`, no `on` clause) is stripped —
    // a typed `on X {` header is a real VM-tracked branch entry point.
    if (node.exceptionType == null) {
      final keyword = node.catchKeyword;
      if (keyword != null) tryHeaderLines.add(_lineOf(keyword.offset));
    }
    super.visitCatchClause(node);
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
