import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

// ==========================================
// RICH TEXT & PAGE MODELS
// ==========================================

class CharFormat {
  final bool bold;
  final bool italic;
  final bool underline;
  final double fontSize;
  final int textColorValue;
  final int highlightColorValue; // 0 = no highlight (transparent)

  const CharFormat({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.fontSize = TextEditorScreenState.defaultFontSize,
    this.textColorValue = 0xFF000000,
    this.highlightColorValue = 0x00000000,
  });

  CharFormat copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    double? fontSize,
    int? textColorValue,
    int? highlightColorValue,
  }) {
    return CharFormat(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      fontSize: fontSize ?? this.fontSize,
      textColorValue: textColorValue ?? this.textColorValue,
      highlightColorValue: highlightColorValue ?? this.highlightColorValue,
    );
  }

  bool sameStyle(CharFormat other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      fontSize == other.fontSize &&
      textColorValue == other.textColorValue &&
      highlightColorValue == other.highlightColorValue;

  Map toJson() => {
        'b': bold ? 1 : 0,
        'i': italic ? 1 : 0,
        'u': underline ? 1 : 0,
        's': fontSize,
        'c': textColorValue,
        'h': highlightColorValue,
      };

  factory CharFormat.fromJson(Map json) => CharFormat(
        bold: (json['b'] ?? 0) == 1,
        italic: (json['i'] ?? 0) == 1,
        underline: (json['u'] ?? 0) == 1,
        fontSize: (json['s'] as num?)?.toDouble() ??
            TextEditorScreenState.defaultFontSize,
        textColorValue: (json['c'] as int?) ?? 0xFF000000,
        highlightColorValue: (json['h'] as int?) ?? 0x00000000,
      );
}

class RichPageTextController extends TextEditingController {
  List charFormats = [];
  CharFormat activeTypingFormat;

  RichPageTextController({
    String? text,
    List? formats,
    this.activeTypingFormat = const CharFormat(),
  }) : super(text: text) {
    final int len = (text ?? '').length;
    if (formats != null && formats.length == len) {
      charFormats = List.from(formats);
    } else {
      charFormats = List.filled(len, activeTypingFormat, growable: true);
    }
  }

  void syncWithTextChange(String oldText, String newText) {
    if (newText.length == charFormats.length) return;

    int prefix = 0;
    final int minLen = math.min(oldText.length, newText.length);
    while (prefix != minLen &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }

    int oldSuffix = oldText.length;
    int newSuffix = newText.length;
    while (oldSuffix.compareTo(prefix) == 1 &&
        newSuffix.compareTo(prefix) == 1 &&
        oldText.codeUnitAt(oldSuffix - 1) ==
            newText.codeUnitAt(newSuffix - 1)) {
      oldSuffix--;
      newSuffix--;
    }

    final List updated = [];
    if (prefix.compareTo(0) == 1) {
      updated.addAll(
          charFormats.sublist(0, math.min(prefix, charFormats.length)));
    }
    final int insertedCount = newSuffix - prefix;
    for (int i = 0; i != insertedCount; i++) {
      updated.add(activeTypingFormat);
    }
    if (oldSuffix.compareTo(charFormats.length) == -1) {
      updated.addAll(charFormats.sublist(oldSuffix));
    }

    while (updated.length.compareTo(newText.length) == -1) {
      updated.add(activeTypingFormat);
    }
    if (updated.length.compareTo(newText.length) == 1) {
      updated.removeRange(newText.length, updated.length);
    }

    charFormats = updated;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String currentText = text;
    if (currentText.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    while (charFormats.length.compareTo(currentText.length) == -1) {
      charFormats.add(activeTypingFormat);
    }

    final List<InlineSpan> spans = [];
    int runStart = 0;

    for (int i = 1; i != currentText.length + 1; i++) {
      final CharFormat startFmt = charFormats[runStart] as CharFormat;
      final bool isEnd = (i == currentText.length);
      final bool styleChanged =
          !isEnd && !(charFormats[i] as CharFormat).sameStyle(startFmt);

      if (isEnd || styleChanged) {
        final Color txtColor = Color(startFmt.textColorValue);
        final Paint? bgPaint = startFmt.highlightColorValue != 0
            ? (Paint()..color = Color(startFmt.highlightColorValue))
            : null;

        spans.add(
          TextSpan(
            text: currentText.substring(runStart, i),
            style: GoogleFonts.poppins(
              fontSize: startFmt.fontSize,
              fontWeight:
                  startFmt.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle:
                  startFmt.italic ? FontStyle.italic : FontStyle.normal,
              decoration: startFmt.underline
                  ? TextDecoration.underline
                  : TextDecoration.none,
              color: txtColor,
              background: bgPaint,
              height: 1.15,
            ),
          ),
        );
        runStart = i;
      }
    }

    return TextSpan(style: style, children: spans);
  }
}

class WordPageModel {
  final RichPageTextController controller;
  final FocusNode focusNode;
  TextAlign textAlign;
  String previousText;

  WordPageModel({
    required String text,
    List? formats,
    CharFormat activeFormat = const CharFormat(),
    this.textAlign = TextAlign.left,
  })  : controller = RichPageTextController(
          text: text,
          formats: formats,
          activeTypingFormat: activeFormat,
        ),
        focusNode = FocusNode(),
        previousText = text;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _RichClipboardBuffer {
  static String plainText = '';
  static List formats = [];
}

// ==========================================
// MS WORD-LIKE A4 TEXT EDITOR SCREEN
// ==========================================

class TextEditorScreen extends StatefulWidget {
  final String documentId;
  final String documentName;

  const TextEditorScreen({
    Key? key,
    required this.documentId,
    required this.documentName,
  }) : super(key: key);

  @override
  State createState() => TextEditorScreenState();
}

class TextEditorScreenState extends State<TextEditorScreen> {
  // Constant A4 Page dimensions in logical points so the page and fonts NEVER shrink or grow
  static const double a4PageWidth = 595.0;
  static const double a4PageHeight = 842.0;
  static const double narrowPadding = 4.0; // Narrow 4px padding on all 4 sides
  static const double innerPageWidth = a4PageWidth - (narrowPadding * 2); // 587.0
  static const double innerPageHeight = a4PageHeight - (narrowPadding * 2); // 834.0
  static const double defaultFontSize = 10.2; // Fits ~70 lines per constant A4 page

  final List fontSizes = [8.0, 10.2, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0];

  final List fontColors = [
    Colors.black,
    const Color(0xFF005EFF),
    Colors.red,
    const Color(0xFF2A9D8F),
    Colors.purple,
    Colors.brown,
    Colors.orange,
    Colors.pink,
  ];

  final List highlightColors = [
    Colors.transparent, // Clear / No highlight
    const Color(0x88FFEB3B), // Yellow highlight
    const Color(0x888BC34A), // Light Green highlight
    const Color(0x88FF9800), // Orange highlight
    const Color(0x8800E5FF), // Cyan highlight
    const Color(0x88F48FB1), // Pink highlight
  ];

  List pages = [];
  int currentPageIndex = 0;
  bool isLoading = true;
  bool _isReflowing = false;

  // Zoom & Pan Controller (2 fingers zoom & pan anywhere on the page)
  final TransformationController _transformationController =
      TransformationController();
  int _activePointers = 0;
  bool _isTwoFingerGesture = false;

  // Active Toolbar Formatting States
  bool isBold = false;
  bool isItalic = false;
  bool isUnderline = false;
  bool isBulletActive = false;
  double activeFontSize = defaultFontSize;
  Color activeTextColor = Colors.black;
  Color activeHighlightColor = Colors.transparent;
  TextAlign activeAlign = TextAlign.left;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    for (final p in pages) {
      (p as WordPageModel).dispose();
    }
    super.dispose();
  }

  CharFormat get _currentTypingFormat => CharFormat(
        bold: isBold,
        italic: isItalic,
        underline: isUnderline,
        fontSize: activeFontSize,
        textColorValue: activeTextColor.value,
        highlightColorValue: activeHighlightColor.value,
      );

  WordPageModel _pageAt(int index) => pages[index] as WordPageModel;

  void _handleDoubleTapZoom() {
    _transformationController.value = Matrix4.identity();
  }

  Future _loadDocument() async {
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('text_doc_${widget.documentId}');

    if (savedJson != null && savedJson.isNotEmpty) {
      try {
        final List decoded = jsonDecode(savedJson) as List;
        pages = decoded.map((pageMap) {
          final Map m = pageMap as Map;
          final String txt = m['text'] as String? ?? '';
          final List? rawFormats = m['formats'] as List?;
          final List fmts = rawFormats != null
              ? rawFormats
                  .map((f) => CharFormat.fromJson(f as Map))
                  .toList()
              : List.filled(txt.length, const CharFormat(), growable: true);
          final int alignIdx = m['align'] as int? ?? TextAlign.left.index;

          final page = WordPageModel(
            text: txt,
            formats: fmts,
            activeFormat: _currentTypingFormat,
            textAlign: TextAlign
                .values[alignIdx.clamp(0, TextAlign.values.length - 1)],
          );
          _attachPageListeners(page);
          return page;
        }).toList();
      } catch (e) {
        debugPrint('Error loading text document: $e');
      }
    }

    if (pages.isEmpty) {
      final firstPage = WordPageModel(
        text: '',
        activeFormat: _currentTypingFormat,
      );
      _attachPageListeners(firstPage);
      pages = [firstPage];
    }

    setState(() => isLoading = false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pages.isNotEmpty) {
        _pageAt(0).focusNode.requestFocus();
      }
    });
  }

  Future _triggerAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    final List data = pages.map((item) {
      final WordPageModel p = item as WordPageModel;
      return {
        'text': p.controller.text,
        'formats': p.controller.charFormats
            .map((f) => (f as CharFormat).toJson())
            .toList(),
        'align': p.textAlign.index,
      };
    }).toList();
    await prefs.setString('text_doc_${widget.documentId}', jsonEncode(data));
  }

  /// Checks if a single line starts with a bullet marker (e.g., `• `, `- `, `* `)
  bool _lineHasBullet(String line) {
    final String trimmed = line.trimLeft();
    return trimmed.startsWith('• ') ||
        trimmed.startsWith('◦ ') ||
        trimmed.startsWith('▪ ') ||
        trimmed == '•';
  }

  void _attachPageListeners(WordPageModel page) {
    page.controller.addListener(() {
      if (_isReflowing) return;

      final String oldText = page.previousText;
      final String newText = page.controller.text;

      if (newText != oldText) {
        // 1. Sync per-character formats first
        page.controller.syncWithTextChange(oldText, newText);

        // 2. Check if the user just pressed Enter on a bulleted line -> Auto-continue bullet!
        final TextSelection sel = page.controller.selection;
        if (newText.length == oldText.length + 1 &&
            sel.isValid &&
            sel.isCollapsed &&
            sel.baseOffset.compareTo(0) == 1 &&
            newText[sel.baseOffset - 1] == '\n') {
          final int enterPos = sel.baseOffset - 1;
          int prevLineStart =
              newText.lastIndexOf('\n', math.max(0, enterPos - 1));
          prevLineStart = prevLineStart == -1 ? 0 : prevLineStart + 1;
          final String prevLine = newText.substring(prevLineStart, enterPos);

          if (_lineHasBullet(prevLine)) {
            final int leadingSpaces =
                prevLine.length - prevLine.trimLeft().length;
            final String indentStr = ' ' * leadingSpaces;
            final String trimmedPrev = prevLine.trimLeft();

            // If user pressed Enter on an empty bullet line, remove the empty bullet and exit list mode
            if (trimmedPrev == '•' || trimmedPrev == '• ') {
              _isReflowing = true;
              final String cleaned = newText.substring(0, prevLineStart) +
                  newText.substring(enterPos + 1);
              page.controller.charFormats
                  .removeRange(prevLineStart, enterPos + 1);
              page.previousText = cleaned;
              page.controller.value = TextEditingValue(
                text: cleaned,
                selection: TextSelection.collapsed(offset: prevLineStart),
              );
              isBulletActive = false;
              _isReflowing = false;
              setState(() {});
              _triggerAutoSave();
              return;
            } else {
              // Insert new bullet with matching indentation on the new line
              final String bulletInsert = '$indentStr• ';
              _isReflowing = true;
              final String updated = newText.substring(0, enterPos + 1) +
                  bulletInsert +
                  newText.substring(enterPos + 1);
              page.controller.charFormats.insertAll(
                enterPos + 1,
                List.filled(bulletInsert.length, _currentTypingFormat),
              );
              page.previousText = updated;
              page.controller.value = TextEditingValue(
                text: updated,
                selection: TextSelection.collapsed(
                    offset: enterPos + 1 + bulletInsert.length),
              );
              _isReflowing = false;
            }
          }
        } else {
          page.previousText = newText;
        }

        final int pageIdx = pages.indexOf(page);
        if (pageIdx != -1) {
          _reflowOverflowingPages(startIndex: pageIdx);
        }
        _triggerAutoSave();
      }

      // Update toolbar state to match the cursor position
      final sel = page.controller.selection;
      if (sel.isValid && sel.isCollapsed) {
        final String currentTxt = page.controller.text;
        final int cursor = sel.baseOffset.clamp(0, currentTxt.length);
        int lineStart = currentTxt.lastIndexOf('\n', math.max(0, cursor - 1));
        lineStart = lineStart == -1 ? 0 : lineStart + 1;
        int lineEnd = currentTxt.indexOf('\n', cursor);
        if (lineEnd == -1) lineEnd = currentTxt.length;
        final String currentLine = currentTxt.substring(lineStart, lineEnd);
        final bool lineBulleted = _lineHasBullet(currentLine);

        if (sel.baseOffset.compareTo(0) == 1 &&
            page.controller.charFormats.isNotEmpty) {
          final int idx = (sel.baseOffset - 1)
              .clamp(0, page.controller.charFormats.length - 1);
          final CharFormat fmt =
              page.controller.charFormats[idx] as CharFormat;
          if (fmt.bold != isBold ||
              fmt.italic != isItalic ||
              fmt.underline != isUnderline ||
              fmt.fontSize != activeFontSize ||
              fmt.textColorValue != activeTextColor.value ||
              fmt.highlightColorValue != activeHighlightColor.value ||
              lineBulleted != isBulletActive) {
            setState(() {
              isBold = fmt.bold;
              isItalic = fmt.italic;
              isUnderline = fmt.underline;
              isBulletActive = lineBulleted;
              activeFontSize = fmt.fontSize;
              activeTextColor = Color(fmt.textColorValue);
              activeHighlightColor = Color(fmt.highlightColorValue);
              page.controller.activeTypingFormat = _currentTypingFormat;
            });
          }
        } else if (lineBulleted != isBulletActive) {
          setState(() => isBulletActive = lineBulleted);
        }
      }
    });
  }

  // ==========================================
  // CONSTANT A4 PAGE CAPACITY & OVERFLOW PAGINATION
  // ==========================================

  TextSpan _buildMeasurementSpan(String text, List formats) {
    final List<InlineSpan> spans = [];
    if (text.isEmpty) return const TextSpan(text: '');

    int runStart = 0;
    for (int i = 1; i != text.length + 1; i++) {
      final CharFormat startFmt = runStart.compareTo(formats.length) == -1
          ? formats[runStart] as CharFormat
          : _currentTypingFormat;
      final bool isEnd = (i == text.length);
      final bool styleChanged = !isEnd &&
          i.compareTo(formats.length) == -1 &&
          !(formats[i] as CharFormat).sameStyle(startFmt);

      if (isEnd || styleChanged) {
        spans.add(
          TextSpan(
            text: text.substring(runStart, i),
            style: GoogleFonts.poppins(
              fontSize: startFmt.fontSize,
              fontWeight: startFmt.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: startFmt.italic ? FontStyle.italic : FontStyle.normal,
              height: 1.15,
            ),
          ),
        );
        runStart = i;
      }
    }
    return TextSpan(children: spans);
  }

  int _findFittingCharLimit(String text, List formats) {
    if (text.isEmpty) return 0;

    final double effectiveFontSize = formats.isNotEmpty
        ? (formats.first as CharFormat).fontSize
        : activeFontSize;

    final int maxLinesPerPage =
        ((defaultFontSize / effectiveFontSize) * 70).round().clamp(10, 70);

    final TextPainter painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: _buildMeasurementSpan(text, formats),
    );
    painter.layout(maxWidth: innerPageWidth);

    final List lines = painter.computeLineMetrics();
    final bool fitsLineCount = lines.length.compareTo(maxLinesPerPage) != 1;
    final bool fitsHeight = painter.height.compareTo(innerPageHeight) != 1;
    if (fitsLineCount && fitsHeight) {
      return text.length;
    }

    int targetLineIndex = math.min(maxLinesPerPage - 1, lines.length - 1);
    while (targetLineIndex.compareTo(0) == 1) {
      final ui.LineMetrics lm = lines[targetLineIndex] as ui.LineMetrics;
      final double lineBottom = lm.baseline + lm.descent;
      if (lineBottom.compareTo(innerPageHeight) != 1) {
        break;
      }
      targetLineIndex--;
    }

    final ui.LineMetrics lastFittingLine =
        lines[targetLineIndex] as ui.LineMetrics;
    final double cutoffY = lastFittingLine.baseline;

    final TextPosition pos = painter.getPositionForOffset(
      Offset(innerPageWidth, cutoffY),
    );

    int splitIndex = pos.offset.clamp(1, text.length);

    if (splitIndex.compareTo(text.length) == -1) {
      final int lastNewline = text.lastIndexOf('\n', splitIndex);
      if (lastNewline.compareTo(splitIndex - 90) == 1 &&
          lastNewline.compareTo(0) == 1) {
        splitIndex = lastNewline + 1;
      } else {
        final int lastSpace = text.lastIndexOf(' ', splitIndex);
        if (lastSpace.compareTo(splitIndex - 35) == 1 &&
            lastSpace.compareTo(0) == 1) {
          splitIndex = lastSpace + 1;
        }
      }
    }

    return splitIndex;
  }

  void _reflowOverflowingPages({int startIndex = 0}) {
    if (_isReflowing) return;
    _isReflowing = true;

    try {
      int i = startIndex;
      while (i.compareTo(pages.length) == -1) {
        final WordPageModel page = _pageAt(i);
        final String fullText = page.controller.text;
        final List fullFormats = List.from(page.controller.charFormats);

        while (fullFormats.length.compareTo(fullText.length) == -1) {
          fullFormats.add(_currentTypingFormat);
        }

        final int fitCount = _findFittingCharLimit(fullText, fullFormats);

        if (fitCount.compareTo(fullText.length) == -1) {
          String keepText = fullText.substring(0, fitCount);
          List keepFormats = fullFormats.sublist(0, fitCount);

          if (keepText.endsWith('\n') && keepFormats.isNotEmpty) {
            keepText = keepText.substring(0, keepText.length - 1);
            keepFormats = keepFormats.sublist(0, keepFormats.length - 1);
          }

          String overflowText = fullText.substring(fitCount);
          List overflowFormats = fullFormats.sublist(fitCount);

          page.previousText = keepText;
          page.controller.charFormats = keepFormats;
          page.controller.value = TextEditingValue(
            text: keepText,
            selection: TextSelection.collapsed(offset: keepText.length),
          );

          if ((i + 1).compareTo(pages.length) == -1) {
            final WordPageModel nextPage = _pageAt(i + 1);
            final String nextExistingText = nextPage.controller.text;
            final List nextExistingFormats =
                List.from(nextPage.controller.charFormats);

            final String separator = (overflowText.isNotEmpty &&
                    !overflowText.endsWith('\n') &&
                    nextExistingText.isNotEmpty)
                ? '\n'
                : '';
            final List sepFormat = separator.isNotEmpty
                ? [
                    overflowFormats.isNotEmpty
                        ? overflowFormats.last
                        : _currentTypingFormat
                  ]
                : [];

            final String mergedText =
                overflowText + separator + nextExistingText;
            final List mergedFormats = [
              ...overflowFormats,
              ...sepFormat,
              ...nextExistingFormats,
            ];

            nextPage.previousText = mergedText;
            nextPage.controller.charFormats = mergedFormats;
            nextPage.controller.value = TextEditingValue(
              text: mergedText,
              selection: TextSelection.collapsed(offset: overflowText.length),
            );
          } else {
            final WordPageModel newPage = WordPageModel(
              text: overflowText,
              formats: overflowFormats,
              activeFormat: _currentTypingFormat,
              textAlign: page.textAlign,
            );
            _attachPageListeners(newPage);
            pages.add(newPage);
          }
        }
        i++;
      }
    } finally {
      _isReflowing = false;
    }

    if (mounted) {
      setState(() {});
    }
  }

  // ==========================================
  // FORMATTING ACTIONS (B, I, U, BULLETS, INDENT, SIZE, COLOR, HIGHLIGHT)
  // ==========================================

  void _applyFormattingToSelection({
    bool? bold,
    bool? italic,
    bool? underline,
    double? fontSize,
    Color? textColor,
    Color? highlightColor,
  }) {
    final WordPageModel page = _pageAt(currentPageIndex);
    final controller = page.controller;
    final sel = controller.selection;

    setState(() {
      if (bold != null) isBold = bold;
      if (italic != null) isItalic = italic;
      if (underline != null) isUnderline = underline;
      if (fontSize != null) activeFontSize = fontSize;
      if (textColor != null) activeTextColor = textColor;
      if (highlightColor != null) activeHighlightColor = highlightColor;

      controller.activeTypingFormat = _currentTypingFormat;

      if (sel.isValid && !sel.isCollapsed) {
        final int start = sel.start.clamp(0, controller.charFormats.length);
        final int end = sel.end.clamp(0, controller.charFormats.length);
        for (int i = start; i.compareTo(end) == -1; i++) {
          final CharFormat oldFmt = controller.charFormats[i] as CharFormat;
          controller.charFormats[i] = oldFmt.copyWith(
            bold: bold,
            italic: italic,
            underline: underline,
            fontSize: fontSize,
            textColorValue: textColor?.value,
            highlightColorValue: highlightColor?.value,
          );
        }
        controller.notifyListeners();
      }
    });

    if (fontSize != null) {
      _reflowOverflowingPages(startIndex: currentPageIndex);
    }
    _triggerAutoSave();
  }

  /// Toggles MS Word-style Bullets (`    • `) on the current line or all selected lines
  void _toggleBulletList() {
    final WordPageModel page = _pageAt(currentPageIndex);
    final controller = page.controller;
    final String text = controller.text;
    final TextSelection sel = controller.selection;

    final int startOffset = sel.isValid ? sel.start.clamp(0, text.length) : text.length;
    final int endOffset = sel.isValid ? sel.end.clamp(0, text.length) : text.length;

    int firstLineStart = text.lastIndexOf('\n', math.max(0, startOffset - 1));
    firstLineStart = firstLineStart == -1 ? 0 : firstLineStart + 1;

    int lastLineEnd = text.indexOf('\n', endOffset);
    if (lastLineEnd == -1) lastLineEnd = text.length;

    final String blockText = text.substring(firstLineStart, lastLineEnd);
    final List blockFormats =
        controller.charFormats.sublist(firstLineStart, lastLineEnd);

    final List lines = blockText.split('\n');
    bool allHaveBullets = lines.isNotEmpty;
    for (final l in lines) {
      if (!_lineHasBullet(l as String)) {
        allHaveBullets = false;
        break;
      }
    }

    final StringBuffer rebuiltBlock = StringBuffer();
    final List rebuiltFormats = [];
    int formatCursor = 0;

    for (int lineIdx = 0; lineIdx != lines.length; lineIdx++) {
      final String line = lines[lineIdx] as String;
      final List lineFmts =
          blockFormats.sublist(formatCursor, formatCursor + line.length);
      formatCursor += line.length;

      if (allHaveBullets) {
        // Remove bullet from this line
        final int bulletPos = line.indexOf('• ');
        if (bulletPos != -1) {
          final int removeStart = math.max(0, bulletPos - 4);
          final int removeEnd = bulletPos + 2;
          final String cleanedLine =
              line.substring(0, removeStart) + line.substring(removeEnd);
          final List cleanedFmts = [
            ...lineFmts.sublist(0, removeStart),
            ...lineFmts.sublist(removeEnd),
          ];
          rebuiltBlock.write(cleanedLine);
          rebuiltFormats.addAll(cleanedFmts);
        } else {
          rebuiltBlock.write(line);
          rebuiltFormats.addAll(lineFmts);
        }
      } else {
        // Add indented bullet (`    • `) to this line if not already bulleted
        if (_lineHasBullet(line)) {
          rebuiltBlock.write(line);
          rebuiltFormats.addAll(lineFmts);
        } else {
          final int leadingSpaces = line.length - line.trimLeft().length;
          const String bulletPrefix = '    • ';
          final String updatedLine = line.substring(0, leadingSpaces) +
              bulletPrefix +
              line.substring(leadingSpaces);
          final CharFormat bulletFmt = lineFmts.isNotEmpty
              ? lineFmts.first as CharFormat
              : _currentTypingFormat;
          final List updatedFmts = [
            ...lineFmts.sublist(0, leadingSpaces),
            ...List.filled(bulletPrefix.length, bulletFmt),
            ...lineFmts.sublist(leadingSpaces),
          ];
          rebuiltBlock.write(updatedLine);
          rebuiltFormats.addAll(updatedFmts);
        }
      }

      if (lineIdx != lines.length - 1) {
        rebuiltBlock.write('\n');
        rebuiltFormats.add(
          formatCursor.compareTo(blockFormats.length) == -1
              ? blockFormats[formatCursor]
              : _currentTypingFormat,
        );
        formatCursor++;
      }
    }

    final String newBlockStr = rebuiltBlock.toString();
    final String finalFullText = text.substring(0, firstLineStart) +
        newBlockStr +
        text.substring(lastLineEnd);
    final List finalFullFormats = [
      ...controller.charFormats.sublist(0, firstLineStart),
      ...rebuiltFormats,
      ...controller.charFormats.sublist(lastLineEnd),
    ];

    _isReflowing = true;
    page.previousText = finalFullText;
    controller.charFormats = finalFullFormats;
    controller.value = TextEditingValue(
      text: finalFullText,
      selection: TextSelection.collapsed(
          offset: firstLineStart + newBlockStr.length),
    );
    _isReflowing = false;

    setState(() => isBulletActive = !allHaveBullets);
    _reflowOverflowingPages(startIndex: currentPageIndex);
    _triggerAutoSave();
  }

  void _changeIndentation({required bool increase}) {
    final WordPageModel page = _pageAt(currentPageIndex);
    final controller = page.controller;
    final String text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;

    final int startOffset = sel.start.clamp(0, text.length);
    final int endOffset = sel.end.clamp(0, text.length);

    int lineStart = text.lastIndexOf('\n', math.max(0, startOffset - 1));
    lineStart = lineStart == -1 ? 0 : lineStart + 1;

    _isReflowing = true;
    if (increase) {
      const String indentSpaces = '    ';
      final String updated = text.substring(0, lineStart) +
          indentSpaces +
          text.substring(lineStart);
      controller.charFormats.insertAll(
        lineStart,
        List.filled(4, _currentTypingFormat),
      );
      page.previousText = updated;
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: endOffset + 4),
      );
    } else {
      int removeCount = 0;
      while (removeCount.compareTo(4) == -1 &&
          (lineStart + removeCount).compareTo(text.length) == -1 &&
          text[lineStart + removeCount] == ' ') {
        removeCount++;
      }
      if (removeCount.compareTo(0) == 1) {
        final String updated = text.substring(0, lineStart) +
            text.substring(lineStart + removeCount);
        controller.charFormats.removeRange(lineStart, lineStart + removeCount);
        page.previousText = updated;
        controller.value = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(
              offset: math.max(lineStart, endOffset - removeCount)),
        );
      }
    }
    _isReflowing = false;
    _reflowOverflowingPages(startIndex: currentPageIndex);
    _triggerAutoSave();
  }

  // ==========================================
  // RICH CLIPBOARD READER (READS OS HTML + UNICODE BOLD + INDENTATION + BULLETS)
  // ==========================================

  Future _copySelectedText() async {
    final WordPageModel page = _pageAt(currentPageIndex);
    final controller = page.controller;
    final sel = controller.selection;

    String copiedText = '';
    List copiedFormats = [];

    if (sel.isValid && !sel.isCollapsed) {
      final int start = sel.start.clamp(0, controller.text.length);
      final int end = sel.end.clamp(0, controller.text.length);
      copiedText = controller.text.substring(start, end);
      copiedFormats = controller.charFormats.sublist(start, end);
    } else {
      copiedText = controller.text;
      copiedFormats = List.from(controller.charFormats);
    }

    _RichClipboardBuffer.plainText = copiedText;
    _RichClipboardBuffer.formats =
        copiedFormats.map((f) => (f as CharFormat).copyWith()).toList();
    await Clipboard.setData(ClipboardData(text: copiedText));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied with Bold, Bullets & Indentation!',
              style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  /// Reads the OS native HTML clipboard format if available (Windows / Linux / macOS)
  /// so copying bold/italic/indented/bulleted text from Chrome, Word, ChatGPT, or PDFs
  /// preserves the exact bold, italic, underline, bullets, and indentation!
  Future<String?> _readSystemHtmlClipboard() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Get-Clipboard -TextFormatType Html'
          ],
        );
        final String out = result.stdout.toString().trim();
        if (out.isNotEmpty &&
            (out.contains('StartFragment') ||
                out.contains('<b') ||
                out.contains('<strong') ||
                out.contains('font-weight') ||
                out.contains('<li') ||
                out.contains('<p') ||
                out.contains('<span'))) {
          final int fragStart = out.indexOf('<!--StartFragment-->');
          final int fragEnd = out.indexOf('<!--EndFragment-->');
          if (fragStart != -1 &&
              fragEnd != -1 &&
              fragEnd.compareTo(fragStart) == 1) {
            return out.substring(fragStart + 20, fragEnd);
          }
          final int htmlStart = out.indexOf('<');
          if (htmlStart != -1) {
            return out.substring(htmlStart);
          }
        }
      } else if (Platform.isLinux) {
        final result = await Process.run(
          'xclip',
          ['-selection', 'clipboard', '-t', 'text/html', '-o'],
        );
        if (result.exitCode == 0) {
          final String out = result.stdout.toString().trim();
          if (out.isNotEmpty) return out;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Converts Mathematical Unicode Bold/Italic characters (often copied from websites/AI)
  /// into normal ASCII characters with their exact `bold` and `italic` flags!
  Map _decodeUnicodeStyledRune(int rune) {
    // Mathematical Bold Capital A-Z (0x1D400..0x1D419) & Sans-Serif Bold A-Z (0x1D5D4..0x1D5ED)
    if (rune.compareTo(0x1D3FF) == 1 && rune.compareTo(0x1D41A) == -1) {
      return {'char': String.fromCharCode(0x41 + (rune - 0x1D400)), 'b': true, 'i': false};
    }
    if (rune.compareTo(0x1D419) == 1 && rune.compareTo(0x1D434) == -1) {
      return {'char': String.fromCharCode(0x61 + (rune - 0x1D41A)), 'b': true, 'i': false};
    }
    if (rune.compareTo(0x1D5D3) == 1 && rune.compareTo(0x1D5EE) == -1) {
      return {'char': String.fromCharCode(0x41 + (rune - 0x1D5D4)), 'b': true, 'i': false};
    }
    if (rune.compareTo(0x1D5ED) == 1 && rune.compareTo(0x1D608) == -1) {
      return {'char': String.fromCharCode(0x61 + (rune - 0x1D5EE)), 'b': true, 'i': false};
    }
    // Mathematical Bold Digits 0-9 (0x1D7CE..0x1D7D7) & Sans-Serif Bold Digits (0x1D7EC..0x1D7F5)
    if (rune.compareTo(0x1D7CD) == 1 && rune.compareTo(0x1D7D8) == -1) {
      return {'char': String.fromCharCode(0x30 + (rune - 0x1D7CE)), 'b': true, 'i': false};
    }
    if (rune.compareTo(0x1D7EB) == 1 && rune.compareTo(0x1D7F6) == -1) {
      return {'char': String.fromCharCode(0x30 + (rune - 0x1D7EC)), 'b': true, 'i': false};
    }
    // Mathematical Italic A-Z / a-z (0x1D434..0x1D467) & Sans-Serif Italic (0x1D608..0x1D63B)
    if (rune.compareTo(0x1D433) == 1 && rune.compareTo(0x1D44E) == -1) {
      return {'char': String.fromCharCode(0x41 + (rune - 0x1D434)), 'b': false, 'i': true};
    }
    if (rune.compareTo(0x1D44D) == 1 && rune.compareTo(0x1D468) == -1) {
      return {'char': String.fromCharCode(0x61 + (rune - 0x1D44E)), 'b': false, 'i': true};
    }
    if (rune.compareTo(0x1D607) == 1 && rune.compareTo(0x1D622) == -1) {
      return {'char': String.fromCharCode(0x41 + (rune - 0x1D608)), 'b': false, 'i': true};
    }
    if (rune.compareTo(0x1D621) == 1 && rune.compareTo(0x1D63C) == -1) {
      return {'char': String.fromCharCode(0x61 + (rune - 0x1D622)), 'b': false, 'i': true};
    }
    // Mathematical Bold Italic (0x1D468..0x1D49B) & Sans-Serif Bold Italic (0x1D63C..0x1D66F)
    if (rune.compareTo(0x1D467) == 1 && rune.compareTo(0x1D482) == -1) {
      return {'char': String.fromCharCode(0x41 + (rune - 0x1D468)), 'b': true, 'i': true};
    }
    if (rune.compareTo(0x1D481) == 1 && rune.compareTo(0x1D49C) == -1) {
      return {'char': String.fromCharCode(0x61 + (rune - 0x1D482)), 'b': true, 'i': true};
    }
    if (rune.compareTo(0x1D63B) == 1 && rune.compareTo(0x1D656) == -1) {
      return {'char': String.fromCharCode(0x41 + (rune - 0x1D63C)), 'b': true, 'i': true};
    }
    if (rune.compareTo(0x1D655) == 1 && rune.compareTo(0x1D670) == -1) {
      return {'char': String.fromCharCode(0x61 + (rune - 0x1D656)), 'b': true, 'i': true};
    }

    return {'char': String.fromCharCode(rune), 'b': false, 'i': false};
  }

  /// Parses an HTML fragment from the OS clipboard, preserving:
  /// - Bold (`<b>`, `<strong>`, `<h1>`-`<h6>`, `font-weight: bold / 600 / 700 / 800 / 900`)
  /// - Italic (`<i>`, `<em>`, `font-style: italic`)
  /// - Underline (`<u>`, `text-decoration: underline`)
  /// - Bullets (`<li>` -> `    • `)
  /// - Indentation (`margin-left`, `padding-left`, `text-indent`, `&nbsp;`, `\t`)
  Map _parseHtmlClipboardFragment(String html, String plainFallback) {
    final StringBuffer outText = StringBuffer();
    final List outFormats = [];

    final List styleStack = [
      {'b': false, 'i': false, 'u': false}
    ];
    int listNestLevel = 0;

    void appendString(String s, bool forceBold, bool forceItalic, bool forceUnderline) {
      final Runes runes = s.runes;
      for (final int r in runes) {
        final Map decoded = _decodeUnicodeStyledRune(r);
        final String ch = decoded['char'] as String;
        final bool uBold = decoded['b'] as bool;
        final bool uItalic = decoded['i'] as bool;

        outText.write(ch);
        outFormats.add(
          CharFormat(
            bold: forceBold || uBold,
            italic: forceItalic || uItalic,
            underline: forceUnderline,
            fontSize: defaultFontSize,
            textColorValue: activeTextColor.value,
            highlightColorValue: activeHighlightColor.value,
          ),
        );
      }
    }

    String decodeEntities(String input) {
      return input
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&#160;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&bull;', '•')
          .replaceAll('&middot;', '•');
    }

    int pos = 0;
    final int len = html.length;

    while (pos.compareTo(len) == -1) {
      final int tagStart = html.indexOf('<', pos);
      if (tagStart == -1) {
        final Map top = styleStack.last as Map;
        appendString(
          decodeEntities(html.substring(pos)),
          top['b'] as bool,
          top['i'] as bool,
          top['u'] as bool,
        );
        break;
      }

      if (tagStart.compareTo(pos) == 1) {
        final String rawChunk = html.substring(pos, tagStart)
            .replaceAll('\r\n', ' ')
            .replaceAll('\n', ' ');
        final Map top = styleStack.last as Map;
        appendString(
          decodeEntities(rawChunk),
          top['b'] as bool,
          top['i'] as bool,
          top['u'] as bool,
        );
      }

      final int tagEnd = html.indexOf('>', tagStart);
      if (tagEnd == -1) break;

      final String fullTag = html.substring(tagStart + 1, tagEnd).trim();
      final String lowerTag = fullTag.toLowerCase();
      pos = tagEnd + 1;

      if (lowerTag.startsWith('!--') ||
          lowerTag.startsWith('style') ||
          lowerTag.startsWith('meta') ||
          lowerTag.startsWith('head')) {
        if (lowerTag.startsWith('style')) {
          final int closeStyle = html.toLowerCase().indexOf('</style>', pos);
          if (closeStyle != -1) pos = closeStyle + 8;
        }
        continue;
      }

      final bool isClosing = lowerTag.startsWith('/');
      final String cleanTag = isClosing ? lowerTag.substring(1).trim() : lowerTag;
      final String tagName = cleanTag.split(RegExp(r'[\s/>]')).first;

      if (isClosing) {
        if (tagName == 'ul' || tagName == 'ol') {
          listNestLevel = math.max(0, listNestLevel - 1);
        }
        if (tagName == 'p' ||
            tagName == 'div' ||
            tagName == 'li' ||
            tagName == 'tr' ||
            tagName == 'h1' ||
            tagName == 'h2' ||
            tagName == 'h3' ||
            tagName == 'h4' ||
            tagName == 'h5' ||
            tagName == 'h6') {
          if (outText.isNotEmpty && !outText.toString().endsWith('\n')) {
            final Map top = styleStack.last as Map;
            appendString('\n', top['b'] as bool, top['i'] as bool, top['u'] as bool);
          }
        }
        if (styleStack.length.compareTo(1) == 1 &&
            (tagName == 'b' ||
                tagName == 'strong' ||
                tagName == 'i' ||
                tagName == 'em' ||
                tagName == 'u' ||
                tagName == 'span' ||
                tagName == 'p' ||
                tagName == 'div' ||
                tagName == 'li' ||
                tagName.startsWith('h'))) {
          styleStack.removeLast();
        }
      } else {
        final Map currentTop = styleStack.last as Map;
        bool nextB = currentTop['b'] as bool;
        bool nextI = currentTop['i'] as bool;
        bool nextU = currentTop['u'] as bool;

        if (tagName == 'b' ||
            tagName == 'strong' ||
            tagName == 'h1' ||
            tagName == 'h2' ||
            tagName == 'h3' ||
            tagName == 'h4' ||
            tagName == 'h5' ||
            tagName == 'h6') {
          nextB = true;
        }
        if (tagName == 'i' || tagName == 'em') {
          nextI = true;
        }
        if (tagName == 'u') {
          nextU = true;
        }

        // Check inline CSS style="..." for bold, italic, underline, and indentation
        if (lowerTag.contains('font-weight')) {
          if (RegExp(r'font-weight\s*:\s*(bold|bolder|[6-9]00)')
              .hasMatch(lowerTag)) {
            nextB = true;
          } else if (RegExp(r'font-weight\s*:\s*(normal|[1-4]00)')
              .hasMatch(lowerTag)) {
            nextB = false;
          }
        }
        if (lowerTag.contains('font-style') &&
            RegExp(r'font-style\s*:\s*(italic|oblique)').hasMatch(lowerTag)) {
          nextI = true;
        }
        if (lowerTag.contains('text-decoration') &&
            lowerTag.contains('underline')) {
          nextU = true;
        }

        if (tagName == 'br') {
          appendString('\n', nextB, nextI, nextU);
          continue;
        }

        if (tagName == 'ul' || tagName == 'ol') {
          listNestLevel++;
          if (outText.isNotEmpty && !outText.toString().endsWith('\n')) {
            appendString('\n', nextB, nextI, nextU);
          }
          continue;
        }

        if (tagName == 'li') {
          if (outText.isNotEmpty && !outText.toString().endsWith('\n')) {
            appendString('\n', nextB, nextI, nextU);
          }
          final String bulletIndent = '    ' * math.max(1, listNestLevel);
          appendString('$bulletIndent• ', nextB, nextI, nextU);
        } else if (tagName == 'p' || tagName == 'div') {
          // Preserve CSS margin-left / padding-left / text-indent as leading spaces
          final RegExpMatch? indentMatch = RegExp(
                  r'(margin-left|padding-left|text-indent)\s*:\s*(\d+)')
              .firstMatch(lowerTag);
          if (indentMatch != null) {
            final int px = int.tryParse(indentMatch.group(2) ?? '0') ?? 0;
            final int spaces = (px / 8).round().clamp(0, 24);
            if (spaces.compareTo(0) == 1) {
              appendString(' ' * spaces, nextB, nextI, nextU);
            }
          }
        }

        if (!lowerTag.endsWith('/')) {
          styleStack.add({'b': nextB, 'i': nextI, 'u': nextU});
        }
      }
    }

    final String resultText = outText.toString().trimRight();
    if (resultText.isEmpty) {
      return _parsePlainTextWithFormatting(plainFallback);
    }

    return {
      'text': resultText,
      'formats': outFormats.sublist(0, resultText.length),
    };
  }

  /// Parses plain text when no HTML stream is present, preserving:
  /// - Leading spaces & tab indentations (`\t` -> 4 spaces)
  /// - Bullet symbols (`- `, `* `, `• `, `◦ `, `▪ `) normalized to indented `    • `
  /// - Unicode Mathematical Bold/Italic characters (`𝗕𝗼𝗹𝗱` -> Bold `CharFormat`)
  /// - Markdown `**bold**`, `*italic*`, `__underline__`, and `# Heading` bold lines
  Map _parsePlainTextWithFormatting(String raw) {
    final String normalizedRaw =
        raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final String normalizedBuffer = _RichClipboardBuffer.plainText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    // 1. Check if it matches our internal copied rich text buffer
    if (normalizedBuffer.isNotEmpty &&
        normalizedRaw == normalizedBuffer &&
        _RichClipboardBuffer.formats.length == normalizedBuffer.length) {
      return {
        'text': normalizedBuffer,
        'formats': _RichClipboardBuffer.formats
            .map((f) => (f as CharFormat).copyWith(fontSize: defaultFontSize))
            .toList(),
      };
    }

    final List rawLines = normalizedRaw
        .replaceAll('\t', '    ')
        .replaceAll('\u00A0', ' ')
        .split('\n');

    final StringBuffer cleanText = StringBuffer();
    final List formats = [];

    for (int lineIdx = 0; lineIdx != rawLines.length; lineIdx++) {
      String line = rawLines[lineIdx] as String;
      bool lineForceBold = false;

      // Preserve exact leading indentation spaces
      final int leadingSpaces = line.length - line.trimLeft().length;
      final String indentPrefix = ' ' * leadingSpaces;
      String trimmed = line.trimLeft();

      // Convert Markdown headings (`# Title`, `## Subtitle`) to Bold lines
      final RegExpMatch? headingMatch =
          RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (headingMatch != null) {
        lineForceBold = true;
        trimmed = headingMatch.group(2) ?? trimmed;
        line = '$indentPrefix$trimmed';
      } else if (trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.startsWith('• ') ||
          trimmed.startsWith('◦ ') ||
          trimmed.startsWith('▪ ')) {
        // Preserve and normalize bullets with indentation
        final String effectiveIndent =
            leadingSpaces.compareTo(0) == 1 ? indentPrefix : '    ';
        line = '$effectiveIndent• ${trimmed.substring(2)}';
      }

      bool b = isBold || lineForceBold;
      bool i = isItalic;
      bool u = isUnderline;

      int pos = 0;
      final int len = line.length;

      while (pos.compareTo(len) == -1) {
        final String rem = line.substring(pos);

        // Markdown **bold**
        if (rem.startsWith('**') && rem.length.compareTo(2) == 1) {
          final int closeIdx = rem.indexOf('**', 2);
          if (closeIdx != -1 || b) {
            b = !b;
            pos += 2;
            continue;
          }
        }
        // Markdown __underline__
        if (rem.startsWith('__') && rem.length.compareTo(2) == 1) {
          final int closeIdx = rem.indexOf('__', 2);
          if (closeIdx != -1 || u) {
            u = !u;
            pos += 2;
            continue;
          }
        }

        // Decode multi-byte Unicode Bold / Italic characters properly
        final int codePoint = line.runes.elementAt(
          line.substring(0, pos).runes.length,
        );
        final int charLen = String.fromCharCode(codePoint).length;
        final Map decoded = _decodeUnicodeStyledRune(codePoint);
        final String ch = decoded['char'] as String;
        final bool uBold = decoded['b'] as bool;
        final bool uItalic = decoded['i'] as bool;

        cleanText.write(ch);
        formats.add(
          CharFormat(
            bold: b || uBold,
            italic: i || uItalic,
            underline: u,
            fontSize: defaultFontSize,
            textColorValue: activeTextColor.value,
            highlightColorValue: activeHighlightColor.value,
          ),
        );
        pos += charLen;
      }

      if (lineIdx != rawLines.length - 1) {
        cleanText.write('\n');
        formats.add(
          CharFormat(
            bold: isBold,
            italic: isItalic,
            underline: isUnderline,
            fontSize: defaultFontSize,
            textColorValue: activeTextColor.value,
            highlightColorValue: activeHighlightColor.value,
          ),
        );
      }
    }

    return {
      'text': cleanText.toString(),
      'formats': formats,
    };
  }

  Future _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.isEmpty) return;

    final String plainRaw = data.text!;
    final String normalizedPlain =
        plainRaw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final String normalizedInternal = _RichClipboardBuffer.plainText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    Map parsed;
    if (normalizedInternal.isNotEmpty &&
        normalizedPlain == normalizedInternal &&
        _RichClipboardBuffer.formats.length == normalizedInternal.length) {
      // 1. Pasting text copied from inside the app
      parsed = _parsePlainTextWithFormatting(plainRaw);
    } else {
      // 2. Pasting text copied from any external app/browser -> Check OS HTML clipboard first!
      final String? systemHtml = await _readSystemHtmlClipboard();
      if (systemHtml != null && systemHtml.isNotEmpty) {
        parsed = _parseHtmlClipboardFragment(systemHtml, plainRaw);
      } else {
        parsed = _parsePlainTextWithFormatting(plainRaw);
      }
    }

    final String pastedText = parsed['text'] as String;
    final List pastedFormats = parsed['formats'] as List;

    final WordPageModel page = _pageAt(currentPageIndex);
    final RichPageTextController controller = page.controller;
    final String currentText = controller.text;
    final TextSelection sel = controller.selection;

    final int start = sel.isValid
        ? sel.start.clamp(0, currentText.length)
        : currentText.length;
    final int end = sel.isValid
        ? sel.end.clamp(0, currentText.length)
        : currentText.length;

    final int beforePageCount = pages.length;

    _isReflowing = true;
    final String newText = currentText.substring(0, start) +
        pastedText +
        currentText.substring(end);
    final List newFormats = [
      ...controller.charFormats.sublist(0, start),
      ...pastedFormats,
      ...controller.charFormats.sublist(end),
    ];

    page.previousText = newText;
    controller.charFormats = newFormats;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + pastedText.length),
    );
    _isReflowing = false;

    _reflowOverflowingPages(startIndex: currentPageIndex);
    await _triggerAutoSave();

    final int addedPages = pages.length - beforePageCount;
    if (addedPages.compareTo(0) == 1 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pasted with formatting! Added $addedPages new page(s) for overflow text.',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ==========================================
  // PAGE NAVIGATION & MANAGEMENT
  // ==========================================

  void _addBlankPageAfterCurrent() {
    setState(() {
      final newPage = WordPageModel(
        text: '',
        activeFormat: _currentTypingFormat,
        textAlign: activeAlign,
      );
      _attachPageListeners(newPage);
      pages.insert(currentPageIndex + 1, newPage);
      currentPageIndex++;
    });
    _triggerAutoSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageAt(currentPageIndex).focusNode.requestFocus();
    });
  }

  void _deleteCurrentPage() {
    if (pages.length.compareTo(1) != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete the only page!',
              style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.secondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Page ${currentPageIndex + 1}?',
            style: GoogleFonts.poppins(
                color: AppColors.primary, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to delete this page?',
            style: TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                final WordPageModel removed =
                    pages.removeAt(currentPageIndex) as WordPageModel;
                removed.dispose();
                if (currentPageIndex.compareTo(pages.length) != -1) {
                  currentPageIndex = pages.length - 1;
                }
              });
              _triggerAutoSave();
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future _exportDocumentToPdf() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Generating A4 PDF...', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final pdf = pw.Document();

      for (final item in pages) {
        final WordPageModel page = item as WordPageModel;
        final String text = page.controller.text;
        final List formats = page.controller.charFormats;

        final List<pw.InlineSpan> pdfSpans = [];
        if (text.isNotEmpty) {
          int runStart = 0;
          for (int i = 1; i != text.length + 1; i++) {
            final CharFormat startFmt = runStart.compareTo(formats.length) == -1
                ? formats[runStart] as CharFormat
                : const CharFormat();
            final bool isEnd = (i == text.length);
            final bool styleChanged = !isEnd &&
                i.compareTo(formats.length) == -1 &&
                !(formats[i] as CharFormat).sameStyle(startFmt);

            if (isEnd || styleChanged) {
              pdfSpans.add(
                pw.TextSpan(
                  text: text.substring(runStart, i),
                  style: pw.TextStyle(
                    fontSize: startFmt.fontSize,
                    color: PdfColor.fromInt(startFmt.textColorValue),
                    background: startFmt.highlightColorValue != 0
                        ? pw.BoxDecoration(
                            color:
                                PdfColor.fromInt(startFmt.highlightColorValue),
                          )
                        : null,
                    fontWeight: startFmt.bold
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    fontStyle: startFmt.italic
                        ? pw.FontStyle.italic
                        : pw.FontStyle.normal,
                    decoration: startFmt.underline
                        ? pw.TextDecoration.underline
                        : pw.TextDecoration.none,
                  ),
                ),
              );
              runStart = i;
            }
          }
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(narrowPadding),
            build: (pw.Context ctx) {
              return pw.RichText(
                text: pw.TextSpan(children: pdfSpans),
              );
            },
          ),
        );
      }

      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final String cleanName =
          widget.documentName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final File file = File('${directory.path}/${cleanName}_WordDoc.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved successfully to Downloads!',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving PDF: $e',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.secondary,
          ),
        );
      }
    }
  }

  // ==========================================
  // UI BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final WordPageModel currentPage = _pageAt(currentPageIndex);

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            // 1. TOP HEADER BAR
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  _buildCircleButton(
                    Icons.arrow_back_ios_new,
                    () => Navigator.pop(context),
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.documentName,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildCircleButton(
                      Icons.post_add, _addBlankPageAfterCurrent,
                      size: 42),
                  const SizedBox(width: 10),
                  _buildCircleButton(
                      Icons.delete_outline, _deleteCurrentPage,
                      size: 42),
                  const SizedBox(width: 10),
                  _buildCircleButton(
                      Icons.download, _exportDocumentToPdf,
                      size: 42),
                ],
              ),
            ),

            // 2. MS WORD RIBBON TOOLBAR
            _buildWordRibbonToolbar(currentPage),

            const SizedBox(height: 6),

            // 3. CONSTANT-SIZE A4 PAGE WITH 2-FINGER PAN & ZOOM
            Expanded(
              child: Listener(
                onPointerDown: (_) {
                  _activePointers++;
                  if (_activePointers.compareTo(1) == 1 &&
                      !_isTwoFingerGesture) {
                    setState(() => _isTwoFingerGesture = true);
                  }
                },
                onPointerUp: (_) {
                  _activePointers = (_activePointers - 1).clamp(0, 10);
                  if (_activePointers == 0 && _isTwoFingerGesture) {
                    setState(() => _isTwoFingerGesture = false);
                  }
                },
                onPointerCancel: (_) {
                  _activePointers = (_activePointers - 1).clamp(0, 10);
                  if (_activePointers == 0 && _isTwoFingerGesture) {
                    setState(() => _isTwoFingerGesture = false);
                  }
                },
                child: GestureDetector(
                  onDoubleTap: _handleDoubleTapZoom,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    panEnabled: _isTwoFingerGesture,
                    scaleEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Container(
                            width: a4PageWidth,
                            height: a4PageHeight,
                            padding: const EdgeInsets.all(narrowPadding),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.14),
                                  blurRadius: 20,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: IgnorePointer(
                              ignoring: _isTwoFingerGesture,
                              // Intercepts Ctrl+V and native context-menu Paste so it ALWAYS uses our Rich Paste!
                              child: Actions(
                                actions: {
                                  PasteTextIntent: CallbackAction(
                                    onInvoke: (_) {
                                      _pasteFromClipboard();
                                      return null;
                                    },
                                  ),
                                  CopySelectionTextIntent: CallbackAction(
                                    onInvoke: (_) {
                                      _copySelectedText();
                                      return null;
                                    },
                                  ),
                                },
                                child: TextField(
                                  controller: currentPage.controller,
                                  focusNode: currentPage.focusNode,
                                  autofocus: true,
                                  maxLines: null,
                                  expands: true,
                                  scrollPhysics:
                                      const NeverScrollableScrollPhysics(),
                                  keyboardType: TextInputType.multiline,
                                  textAlign: currentPage.textAlign,
                                  cursorColor: AppColors.primary,
                                  cursorWidth: 2.0,
                                  showCursor: true,
                                  style: GoogleFonts.poppins(
                                    fontSize: activeFontSize,
                                    color: activeTextColor,
                                    height: 1.15,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.zero,
                                    hintText:
                                        'Start typing or paste text here...',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 4. BOTTOM PAGE NAVIGATION BAR
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCircleButton(
                    Icons.arrow_back_ios_new,
                    () {
                      if (currentPageIndex.compareTo(0) == 1) {
                        setState(() => currentPageIndex--);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _pageAt(currentPageIndex).focusNode.requestFocus();
                        });
                      }
                    },
                    size: 40,
                    iconColor: currentPageIndex.compareTo(0) == 1
                        ? AppColors.primary
                        : AppColors.text.withOpacity(0.3),
                  ),
                  const SizedBox(width: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: const [
                        BoxShadow(
                            color: AppColors.shadow,
                            offset: Offset(4, 4),
                            blurRadius: 8),
                        BoxShadow(
                            color: Colors.white,
                            offset: Offset(-4, -4),
                            blurRadius: 8),
                      ],
                    ),
                    child: Text(
                      'Page ${currentPageIndex + 1} of ${pages.length}',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  _buildCircleButton(
                    Icons.arrow_forward_ios,
                    () {
                      if (currentPageIndex.compareTo(pages.length - 1) == -1) {
                        setState(() => currentPageIndex++);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _pageAt(currentPageIndex).focusNode.requestFocus();
                        });
                      }
                    },
                    size: 40,
                    iconColor:
                        currentPageIndex.compareTo(pages.length - 1) == -1
                            ? AppColors.primary
                            : AppColors.text.withOpacity(0.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWordRibbonToolbar(WordPageModel currentPage) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, offset: Offset(4, 4), blurRadius: 8),
          BoxShadow(
              color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Bold
            _buildFormatToggle(
              label: 'B',
              isSelected: isBold,
              fontWeight: FontWeight.bold,
              onTap: () => _applyFormattingToSelection(bold: !isBold),
            ),
            const SizedBox(width: 6),
            // Italic
            _buildFormatToggle(
              label: 'I',
              isSelected: isItalic,
              fontStyle: FontStyle.italic,
              onTap: () => _applyFormattingToSelection(italic: !isItalic),
            ),
            const SizedBox(width: 6),
            // Underline
            _buildFormatToggle(
              label: 'U',
              isSelected: isUnderline,
              decoration: TextDecoration.underline,
              onTap: () => _applyFormattingToSelection(underline: !isUnderline),
            ),
            const SizedBox(width: 6),
            // Bullets Option Button
            GestureDetector(
              onTap: _toggleBulletList,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isBulletActive ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.format_list_bulleted,
                  size: 19,
                  color: isBulletActive ? Colors.white : AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Font Size Selector
            PopupMenuButton(
              initialValue: activeFontSize,
              onSelected: (val) {
                _applyFormattingToSelection(fontSize: (val as num).toDouble());
              },
              itemBuilder: (context) => fontSizes
                  .map((s) => PopupMenuItem(
                        value: s,
                        child: Text('${(s as double).toStringAsFixed(0)} pt'),
                      ))
                  .toList(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text(
                      '${activeFontSize.toStringAsFixed(0)} pt',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down,
                        size: 18, color: AppColors.text),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Font Color Picker
            PopupMenuButton(
              tooltip: 'Font Color',
              onSelected: (val) {
                _applyFormattingToSelection(textColor: val as Color);
              },
              itemBuilder: (context) => fontColors
                  .map((c) => PopupMenuItem(
                        value: c,
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: c as Color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text('Font Color'),
                          ],
                        ),
                      ))
                  .toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.format_color_text,
                        size: 18, color: activeTextColor),
                    const SizedBox(width: 4),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: activeTextColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Highlight Color Picker
            PopupMenuButton(
              tooltip: 'Highlight Text',
              onSelected: (val) {
                _applyFormattingToSelection(highlightColor: val as Color);
              },
              itemBuilder: (context) => highlightColors
                  .map((c) => PopupMenuItem(
                        value: c,
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: (c as Color).value == 0
                                    ? Colors.white
                                    : c,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.black26),
                              ),
                              child: c.value == 0
                                  ? const Icon(Icons.close,
                                      size: 14, color: Colors.red)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Text(c.value == 0 ? 'No Highlight' : 'Highlight'),
                          ],
                        ),
                      ))
                  .toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: activeHighlightColor.value != 0
                      ? activeHighlightColor
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.border_color,
                        size: 17, color: AppColors.primary),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),
            Container(width: 1, height: 24, color: AppColors.shadow),
            const SizedBox(width: 4),

            // Indentation Decrease / Increase
            IconButton(
              tooltip: 'Decrease Indent',
              icon: const Icon(Icons.format_indent_decrease, size: 20),
              color: AppColors.text,
              onPressed: () => _changeIndentation(increase: false),
            ),
            IconButton(
              tooltip: 'Increase Indent',
              icon: const Icon(Icons.format_indent_increase, size: 20),
              color: AppColors.text,
              onPressed: () => _changeIndentation(increase: true),
            ),

            // Alignment
            IconButton(
              tooltip: 'Align Left',
              icon: Icon(
                Icons.format_align_left,
                size: 20,
                color: currentPage.textAlign == TextAlign.left
                    ? AppColors.primary
                    : AppColors.text,
              ),
              onPressed: () {
                setState(() {
                  currentPage.textAlign = TextAlign.left;
                  activeAlign = TextAlign.left;
                });
                _triggerAutoSave();
              },
            ),
            IconButton(
              tooltip: 'Align Center',
              icon: Icon(
                Icons.format_align_center,
                size: 20,
                color: currentPage.textAlign == TextAlign.center
                    ? AppColors.primary
                    : AppColors.text,
              ),
              onPressed: () {
                setState(() {
                  currentPage.textAlign = TextAlign.center;
                  activeAlign = TextAlign.center;
                });
                _triggerAutoSave();
              },
            ),

            const SizedBox(width: 4),
            Container(width: 1, height: 24, color: AppColors.shadow),
            const SizedBox(width: 8),

            // Copy Button
            GestureDetector(
              onTap: _copySelectedText,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.copy, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Copy',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Paste Button
            GestureDetector(
              onTap: _pasteFromClipboard,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.paste, size: 16, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      'Paste',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatToggle({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
    TextDecoration decoration = TextDecoration.none,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: fontWeight,
              fontStyle: fontStyle,
              decoration: decoration,
              color: isSelected ? Colors.white : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton(
    IconData icon,
    VoidCallback onTap, {
    double size = 45,
    Color iconColor = AppColors.primary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.background,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadow, offset: Offset(4, 4), blurRadius: 8),
            BoxShadow(
                color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
          ],
        ),
        child: Icon(icon, color: iconColor, size: size * 0.48),
      ),
    );
  }
}