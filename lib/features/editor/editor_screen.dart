import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfx/pdfx.dart' as pdfx; // Using pdfx to render pages as backgrounds
import '../../core/theme.dart';
import '../../data/database_helper.dart';

// ==========================================
// DATA MODELS
// ==========================================

enum DrawingTool { pen, highlighter, eraser }
enum PageType { blank, pdf }

class Stroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final DrawingTool tool;

  Stroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.tool,
  });
}

class NotePage {
  List<Stroke> strokes = [];
  final PageType type;
  final double aspectRatio; 
  final int? pdfPageNumber; // Tracks which page of the PDF this is

  NotePage({
    this.type = PageType.blank,
    this.aspectRatio = 1 / 1.414, 
    this.pdfPageNumber,
  });
}

// ==========================================
// EDITOR SCREEN
// ==========================================

class EditorScreen extends StatefulWidget {
  final String documentId;
  final String documentName;
  final bool isImportedPdf;
  final String? pdfPath;

  const EditorScreen({
    Key? key, 
    required this.documentId,
    this.documentName = 'New Blank Note',
    this.isImportedPdf = false,
    this.pdfPath,
  }) : super(key: key);

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  List<NotePage> pages = []; 
  int currentPageIndex = 0;
  bool isLoading = true;

  // PDF Extraction Variables
  pdfx.PdfDocument? _pdfDocument;
  final Map<int, Uint8List> _pdfPageCache = {}; // Prevents OOM crashes by caching images
  final Map<int, Future<Uint8List?>> _pdfPageFutures = {}; // Prevents flickering while drawing over PDF

  final TransformationController _transformationController = TransformationController();

  DrawingTool activeTool = DrawingTool.pen;
  Color activePenColor = Colors.black;
  Color activeHighlighterColor = Colors.yellow;
  
  double activePenSize = 4.0;
  double activeEraserSize = 20.0;
  
  Stroke? currentStroke;

  final List<double> penSizes = [1.0, 2.0, 4.0, 8.0, 10.0]; 
  final List<Color> penColors = [
    Colors.black, Colors.red, Colors.white, Colors.blue, Colors.yellow, 
    Colors.green, Colors.brown, Colors.pink, Colors.cyan, Colors.orange
  ];
  final List<Color> highlighterColors = [
    Colors.lightGreen, Colors.yellow, Colors.orange
  ];

  @override
  void initState() {
    super.initState();
    _initializeDocument();
  }

  @override
  void dispose() {
    _pdfDocument?.close();
    super.dispose();
  }

  Future<void> _initializeDocument() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('doc_${widget.documentId}');

    String? resolvedPath = widget.pdfPath;
    bool isPdfDoc = widget.isImportedPdf;

    // Fallback check in SQLite in case pdfPath wasn't passed directly
    if (resolvedPath == null || resolvedPath.isEmpty) {
      try {
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query('documents', where: 'id = ?', whereArgs: [widget.documentId]);
        if (rows.isNotEmpty) {
          resolvedPath = rows.first['pdf_path'] as String?;
          if (rows.first['type'] == 'pdf') isPdfDoc = true;
        }
      } catch (_) {}
    }

    // 1. If it's a PDF, load the file into memory using the actual file path
    if (isPdfDoc && resolvedPath != null && resolvedPath.isNotEmpty) {
      try {
        _pdfDocument = await pdfx.PdfDocument.openFile(resolvedPath);
      } catch (e) {
        debugPrint("Error opening PDF: $e");
      }
    }

    // 2. Load existing save data if it exists
    if (savedData != null) {
      try {
        final List<dynamic> decodedPages = jsonDecode(savedData);
        pages = decodedPages.map((pageData) {
          final NotePage p = NotePage(
            type: pageData['type'] == 'pdf' ? PageType.pdf : PageType.blank,
            aspectRatio: (pageData['aspectRatio'] as num).toDouble(),
            pdfPageNumber: pageData['pdfPageNumber'],
          );
          
          p.strokes = (pageData['strokes'] as List).map((strokeData) {
            return Stroke(
              tool: DrawingTool.values.firstWhere((e) => e.toString() == strokeData['tool']),
              color: Color(strokeData['color']),
              strokeWidth: (strokeData['width'] as num).toDouble(),
              points: (strokeData['points'] as List).map((pt) => Offset((pt['dx'] as num).toDouble(), (pt['dy'] as num).toDouble())).toList(),
            );
          }).toList();
          return p;
        }).toList();

        // If this is a PDF document, but savedData was previously saved as a single blank page by mistake, rebuild all PDF pages
        if (isPdfDoc && _pdfDocument != null && !pages.any((p) => p.type == PageType.pdf)) {
          _setupFreshDocument();
          await _triggerAutoSave();
        }
      } catch (e) {
        debugPrint("Error loading save data: $e");
        _setupFreshDocument();
      }
    } else {
      _setupFreshDocument();
      await _triggerAutoSave();
    }

    setState(() { isLoading = false; });
  }

  void _setupFreshDocument() {
    if (_pdfDocument != null) {
      // Create a NotePage for every single page in the PDF
      int pageCount = _pdfDocument!.pagesCount;
      pages = List.generate(pageCount, (index) {
        return NotePage(
          type: PageType.pdf,
          aspectRatio: 1 / 1.414, 
          pdfPageNumber: index + 1, // PDF pages are 1-indexed
        );
      });
    } else {
      pages = [NotePage(type: PageType.blank, aspectRatio: 1 / 1.414)];
    }
  }

  Future<Uint8List?> _getPdfPageFuture(int pageNumber) {
    if (_pdfPageCache.containsKey(pageNumber)) {
      return Future.value(_pdfPageCache[pageNumber]);
    }
    return _pdfPageFutures.putIfAbsent(pageNumber, () => _getPdfPageImage(pageNumber));
  }

  // Extracts the specific PDF page as an image to use as a background
  Future<Uint8List?> _getPdfPageImage(int pageNumber) async {
    if (_pdfPageCache.containsKey(pageNumber)) return _pdfPageCache[pageNumber];
    if (_pdfDocument == null) return null;

    try {
      final page = await _pdfDocument!.getPage(pageNumber);
      
      // Render at 2x resolution and explicitly set the format to PNG
      final pageImage = await page.render(
        width: page.width * 2, 
        height: page.height * 2,
        format: pdfx.PdfPageImageFormat.png, 
      );
      
      await page.close();

      if (pageImage != null) {
        _pdfPageCache[pageNumber] = pageImage.bytes;
        return pageImage.bytes;
      }
    } catch (e) {
      debugPrint("Error rendering PDF page: $e");
    }
    return null;
  }

  Future<void> _triggerAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    
    final List<Map<String, dynamic>> serializedData = pages.map((page) {
      return {
        'type': page.type == PageType.pdf ? 'pdf' : 'blank',
        'aspectRatio': page.aspectRatio,
        'pdfPageNumber': page.pdfPageNumber,
        'strokes': page.strokes.map((stroke) {
          return {
            'tool': stroke.tool.toString(),
            'color': stroke.color.value,
            'width': stroke.strokeWidth,
            'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList(),
          };
        }).toList(),
      };
    }).toList();

    await prefs.setString('doc_${widget.documentId}', jsonEncode(serializedData));
  }

  // ==========================================
  // ACTION LOGIC
  // ==========================================

  void _handleDoubleTapZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _addNewPage() {
    setState(() {
      pages.insert(
        currentPageIndex + 1, 
        NotePage(type: PageType.blank, aspectRatio: 1 / 1.414)
      );
      currentPageIndex++; 
    });
    _triggerAutoSave();
  }

  void _deleteCurrentPage() {
    if (pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete the only page!', style: TextStyle(color: Colors.white)),
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
        title: Text('Delete Page ${currentPageIndex + 1}?', style: GoogleFonts.poppins(color: AppColors.primary, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to delete this page?', style: TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                pages.removeAt(currentPageIndex);
                if (currentPageIndex >= pages.length) {
                  currentPageIndex = pages.length - 1;
                }
              });
              _triggerAutoSave();
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  
  void _prevPage() {
    if (currentPageIndex > 0) setState(() => currentPageIndex--);
  }

  void _nextPage() {
    if (currentPageIndex < pages.length - 1) setState(() => currentPageIndex++);
  }

  void _jumpToPage() {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Jump to Page', style: GoogleFonts.poppins(color: AppColors.text, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter page (1 - ${pages.length})',
              hintStyle: TextStyle(color: AppColors.text.withOpacity(0.5)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
            ),
            style: const TextStyle(color: AppColors.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.text)),
            ),
            TextButton(
              onPressed: () {
                int? page = int.tryParse(controller.text.trim());
                if (page != null && page >= 1 && page <= pages.length) {
                  setState(() => currentPageIndex = page - 1);
                  Navigator.pop(context);
                }
              },
              child: const Text('Go', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportAndDownloadPDF() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating PDF...', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.primary, behavior: SnackBarBehavior.floating),
    );

    try {
      final pdf = pw.Document();
      double screenPaperHeight = MediaQuery.of(context).size.height - 80; 

      for (var page in pages) {
        double pdfWidth = page.aspectRatio > 1 ? 841.89 : 595.27;
        double pdfHeight = page.aspectRatio > 1 ? 841.89 / page.aspectRatio : 595.27 / page.aspectRatio;

        Uint8List? bgImageBytes;
        if (page.type == PageType.pdf && page.pdfPageNumber != null) {
          bgImageBytes = await _getPdfPageImage(page.pdfPageNumber!);
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(pdfWidth, pdfHeight),
            build: (pw.Context context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Stack(
                  fit: pw.StackFit.expand,
                  children: [
                    if (bgImageBytes != null)
                      pw.Image(pw.MemoryImage(bgImageBytes), fit: pw.BoxFit.contain),
                    pw.CustomPaint(
                      size: PdfPoint(pdfWidth, pdfHeight),
                      painter: (PdfGraphics canvas, PdfPoint size) {
                        double screenPaperWidth = screenPaperHeight * page.aspectRatio;
                        double scaleX = size.x / screenPaperWidth;
                        double scaleY = size.y / screenPaperHeight;

                        for (var stroke in page.strokes) {
                          if (stroke.points.isEmpty) continue;
                          
                          canvas.saveContext();
                          if (stroke.tool == DrawingTool.eraser) {
                            canvas.setStrokeColor(PdfColors.white); 
                          } else {
                            canvas.setStrokeColor(PdfColor.fromInt(stroke.color.value));
                          }
                          
                          if (stroke.tool == DrawingTool.highlighter) {
                            canvas.setGraphicState(const PdfGraphicState(opacity: 0.4));
                          }

                          canvas.setLineWidth(stroke.strokeWidth * scaleX);
                          canvas.setLineCap(stroke.tool == DrawingTool.highlighter ? PdfLineCap.square : PdfLineCap.round);
                          canvas.setLineJoin(stroke.tool == DrawingTool.highlighter ? PdfLineJoin.bevel : PdfLineJoin.round);

                          canvas.moveTo(stroke.points.first.dx * scaleX, size.y - (stroke.points.first.dy * scaleY));
                          for (int i = 1; i < stroke.points.length; i++) {
                            canvas.lineTo(stroke.points[i].dx * scaleX, size.y - (stroke.points[i].dy * scaleY));
                          }
                          
                          canvas.strokePath();
                          canvas.restoreContext();
                        }
                      },
                    ),
                  ],
                ),
              );
            }
          )
        );
      }

      Directory? directory;
      if (Platform.isAndroid) directory = Directory('/storage/emulated/0/Download');
      else directory = await getApplicationDocumentsDirectory(); 

      String cleanName = widget.documentName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final File file = File('${directory.path}/${cleanName}_Notes.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved successfully to Downloads!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving PDF: $e', style: const TextStyle(color: Colors.white)), backgroundColor: AppColors.secondary));
      }
    }
  }

  // ==========================================
  // DRAWING GESTURES
  // ==========================================

  void _onPanStart(DragStartDetails details) {
    setState(() {
      double calculatedWidth = activeTool == DrawingTool.eraser 
          ? activeEraserSize 
          : activeTool == DrawingTool.highlighter ? (activePenSize * 3.0) : activePenSize;

      currentStroke = Stroke(
        points: [details.localPosition],
        color: activeTool == DrawingTool.highlighter 
            ? activeHighlighterColor.withOpacity(0.3) 
            : activeTool == DrawingTool.eraser ? Colors.transparent : activePenColor,
        strokeWidth: calculatedWidth,
        tool: activeTool,
      );
      pages[currentPageIndex].strokes.add(currentStroke!);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      currentStroke?.points.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    currentStroke = null;
    _triggerAutoSave(); 
  }

  // ==========================================
  // UI BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onDoubleTap: _handleDoubleTapZoom,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Center(
                  child: _buildDynamicPage(pages[currentPageIndex]), 
                ),
              ),
            ),
            Positioned(
              top: 20, left: 0, right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: AppColors.background.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
                    child: Text(widget.documentName, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 20, right: 20,
              child: Column(
                children: [
                  _buildCircleButton(Icons.add, _addNewPage),
                  const SizedBox(height: 16),
                  _buildCircleButton(Icons.delete_outline, _deleteCurrentPage),
                  const SizedBox(height: 16),
                  _buildCircleButton(Icons.download, _exportAndDownloadPDF),
                  const SizedBox(height: 16),
                  _buildCircleButton(Icons.search, _jumpToPage),
                ],
              ),
            ),
            Positioned(
              top: 20, left: 20,
              child: _buildCircleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
            ),
            Positioned(
              left: 20, top: 100, bottom: 20,
              child: _buildPalette(),
            ),
            Positioned(
              bottom: 30, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCircleButton(Icons.arrow_back_ios_new, _prevPage, size: 45, iconColor: currentPageIndex > 0 ? AppColors.primary : AppColors.text.withOpacity(0.3)),
                  const SizedBox(width: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: AppColors.shadow, offset: Offset(4, 4), blurRadius: 8), BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)]),
                    child: Text('Page ${currentPageIndex + 1} of ${pages.length}', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: AppColors.text)),
                  ),
                  const SizedBox(width: 24),
                  _buildCircleButton(Icons.arrow_forward_ios, _nextPage, size: 45, iconColor: currentPageIndex < pages.length - 1 ? AppColors.primary : AppColors.text.withOpacity(0.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicPage(NotePage page) {
    return AspectRatio(
      aspectRatio: page.aspectRatio, 
      child: Container(
        margin: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, spreadRadius: 5)],
        ),
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. RENDER PDF BACKGROUND IF IT IS A PDF PAGE
              if (page.type == PageType.pdf && page.pdfPageNumber != null)
                FutureBuilder<Uint8List?>(
                  future: _getPdfPageFuture(page.pdfPageNumber!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                    }
                    if (snapshot.hasData && snapshot.data != null) {
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      );
                    }
                    return const Center(child: Icon(Icons.error_outline, color: Colors.red));
                  },
                ),
                
              // 2. RENDER THE DRAWING CANVAS ON TOP
              GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: CustomPaint(size: Size.infinite, painter: DrawingPainter(strokes: page.strokes)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap, {double size = 50, Color iconColor = AppColors.primary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: AppColors.background, shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: AppColors.shadow, offset: Offset(4, 4), blurRadius: 8), BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)],
        ),
        child: Icon(icon, color: iconColor, size: size * 0.5),
      ),
    );
  }

  Widget _buildPalette() {
    return Container(
      width: 65, padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.background, borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: AppColors.shadow, offset: Offset(6, 6), blurRadius: 10), BoxShadow(color: Colors.white, offset: Offset(-6, -6), blurRadius: 10)],
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildToolIcon(Icons.edit, DrawingTool.pen),
            _buildToolIcon(Icons.brush, DrawingTool.highlighter),
            _buildToolIcon(Icons.cleaning_services, DrawingTool.eraser),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: AppColors.shadow)),
            if (activeTool == DrawingTool.pen || activeTool == DrawingTool.highlighter) ...penSizes.map((s) => _buildSizeDot(s)),
            if (activeTool == DrawingTool.eraser) ...[10.0, 20.0, 40.0].map((s) => _buildSizeDot(s)),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: AppColors.shadow)),
            if (activeTool == DrawingTool.pen) ...penColors.map((c) => _buildColorDot(c)),
            if (activeTool == DrawingTool.highlighter) ...highlighterColors.map((c) => _buildColorDot(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildToolIcon(IconData icon, DrawingTool tool) {
    bool isSelected = activeTool == tool;
    return GestureDetector(
      onTap: () => setState(() => activeTool = tool),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10), padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent, shape: BoxShape.circle),
        child: Icon(icon, color: isSelected ? AppColors.primary : AppColors.text, size: 28),
      ),
    );
  }

  Widget _buildSizeDot(double size) {
    bool isSelected = (activeTool == DrawingTool.eraser && activeEraserSize == size) || ((activeTool == DrawingTool.pen || activeTool == DrawingTool.highlighter) && activePenSize == size);
    return GestureDetector(
      onTap: () => setState(() {
        if (activeTool == DrawingTool.eraser) activeEraserSize = size;
        else activePenSize = size;
      }),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8), width: 30, height: 30,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent, width: 2)),
        child: Center(child: Container(width: size > 20 ? 20 : (size < 4 ? 4 : size), height: size > 20 ? 20 : (size < 4 ? 4 : size), decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle))),
      ),
    );
  }

  Widget _buildColorDot(Color color) {
    bool isSelected = (activeTool == DrawingTool.pen && activePenColor == color) || (activeTool == DrawingTool.highlighter && activeHighlighterColor == color);
    return GestureDetector(
      onTap: () => setState(() {
        if (activeTool == DrawingTool.pen) activePenColor = color;
        else if (activeTool == DrawingTool.highlighter) activeHighlighterColor = color;
      }),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8), width: 30, height: 30,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: isSelected ? AppColors.text : Colors.black12, width: isSelected ? 3 : 1), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<Stroke> strokes;
  DrawingPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    for (final stroke in strokes) {
      final paint = Paint()..strokeWidth = stroke.strokeWidth..style = PaintingStyle.stroke;
      if (stroke.tool == DrawingTool.highlighter) {
        paint.strokeCap = StrokeCap.square; paint.strokeJoin = StrokeJoin.bevel;
      } else {
        paint.strokeCap = StrokeCap.round; paint.strokeJoin = StrokeJoin.round;
      }

      if (stroke.tool == DrawingTool.eraser) {
        paint.blendMode = BlendMode.clear; paint.color = Colors.transparent;
      } else {
        paint.color = stroke.color;
      }

      final path = Path();
      if (stroke.points.isNotEmpty) {
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) => true; 
}