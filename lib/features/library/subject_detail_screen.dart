import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme.dart';
import '../../data/database_helper.dart';
import '../editor/editor_screen.dart';

class SubjectDetailScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;
  
  const SubjectDetailScreen({Key? key, required this.subjectId, this.subjectName = 'Notes Library'}) : super(key: key);

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  List<Map<String, dynamic>> documents = [];

  @override
  void initState() {
    super.initState();
    _refreshDocuments();
  }

  Future<void> _refreshDocuments() async {
    final data = await DatabaseHelper.instance.getDocumentsForSubject(widget.subjectId);
    setState(() {
      documents = data;
    });
  }

  Future<void> _importPDF() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'],
      );

      if (result != null) {
        String fileName = result.files.single.name;
        String displayTitle = fileName.replaceAll('.pdf', '');

        if (documents.any((doc) => doc['title'] == displayTitle)) {
           _showDuplicateErrorDialog(displayTitle, isImport: true);
           return;
        }

        final newDoc = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'subject_id': widget.subjectId,
          'title': displayTitle,
          'type': 'pdf',
          'date': DateFormat('MMM d, yyyy').format(DateTime.now()),
        };

        await DatabaseHelper.instance.insertDocument(newDoc);
        _refreshDocuments();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$fileName imported!', style: const TextStyle(color: Colors.white)), backgroundColor: AppColors.primary, behavior: SnackBarBehavior.floating),
          );
        }
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    }
  }

  void _createBlankNote({String initialText = ''}) {
    TextEditingController controller = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('New Blank File', style: GoogleFonts.poppins(color: AppColors.text, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g., Chapter 3 Summary',
              hintStyle: TextStyle(color: AppColors.text.withOpacity(0.5)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
            ),
            style: const TextStyle(color: AppColors.text),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppColors.text))),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  _handleBlankNoteCreation(name);
                }
              },
              child: const Text('Create', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _handleBlankNoteCreation(String name) async {
    bool nameExists = documents.any((doc) => doc['title'] == name);
    if (nameExists) {
      _showDuplicateErrorDialog(name, isImport: false);
    } else {
      final newDoc = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'subject_id': widget.subjectId,
        'title': name,
        'type': 'blank',
        'date': DateFormat('MMM d, yyyy').format(DateTime.now()),
      };
      
      await DatabaseHelper.instance.insertDocument(newDoc);
      _refreshDocuments();
    }
  }

  void _showDuplicateErrorDialog(String duplicateName, {required bool isImport}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('File Already Exists', style: GoogleFonts.poppins(color: AppColors.text, fontWeight: FontWeight.bold)),
        content: Text('A document named "$duplicateName" already exists in this folder. Please use a different name.', style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppColors.text))),
          if (!isImport)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _createBlankNote(initialText: duplicateName);
              },
              child: const Text('Rename', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  void _deleteDocument(String id, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete $title?', style: GoogleFonts.poppins(color: AppColors.primary, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure? This action cannot be undone.', style: TextStyle(color: AppColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppColors.text))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await DatabaseHelper.instance.deleteDocument(id);
              _refreshDocuments();
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int crossAxisCount = MediaQuery.of(context).size.width > 600 ? 4 : 2;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  NeuActionButton(icon: Icons.arrow_back_ios_new, onTap: () => Navigator.pop(context), size: 50),
                  const SizedBox(width: 20),
                  Expanded(child: Text(widget.subjectName, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.text), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: [
                  Expanded(child: NeuActionButton(text: "Import PDF", icon: Icons.picture_as_pdf, iconColor: AppColors.primary, onTap: _importPDF, height: 70)),
                  const SizedBox(width: 20),
                  Expanded(child: NeuActionButton(text: "Blank File", icon: Icons.note_add, iconColor: AppColors.secondary, onTap: () => _createBlankNote(), height: 70)),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: documents.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.folder_open, size: 80, color: AppColors.text.withOpacity(0.3)), const SizedBox(height: 16), Text("This chamber is empty.\nImport a PDF or create a blank file!", textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.text.withOpacity(0.6), fontSize: 16))]))
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 20, mainAxisSpacing: 20, childAspectRatio: 0.75),
                      itemCount: documents.length,
                      itemBuilder: (context, index) {
                        final doc = documents[index];
                        return DocumentCard(
                          title: doc['title'], type: doc['type'], date: doc['date'],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EditorScreen(
                                  documentId: doc['id'],
                                  documentName: doc['title'],
                                ),
                              ),
                            );
                          },
                          onDelete: () => _deleteDocument(doc['id'], doc['title']),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class NeuActionButton extends StatefulWidget {
  final String? text;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final double size;
  final double height;
  const NeuActionButton({Key? key, this.text, required this.icon, this.iconColor = AppColors.text, required this.onTap, this.size = 0, this.height = 0}) : super(key: key);
  @override
  State<NeuActionButton> createState() => _NeuActionButtonState();
}

class _NeuActionButtonState extends State<NeuActionButton> with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    bool isSquare = widget.text == null;
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) { setState(() => _isPressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: isSquare ? widget.size : null,
        height: isSquare ? widget.size : widget.height,
        decoration: BoxDecoration(
          color: AppColors.background, borderRadius: BorderRadius.circular(isSquare ? 15 : 20),
          boxShadow: _isPressed ? [const BoxShadow(color: AppColors.shadow, offset: Offset(2, 2), blurRadius: 4, spreadRadius: -1), const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4, spreadRadius: -1)] : [const BoxShadow(color: AppColors.shadow, offset: Offset(5, 5), blurRadius: 10), const BoxShadow(color: Colors.white, offset: Offset(-5, -5), blurRadius: 10)],
        ),
        child: Center(
          child: isSquare ? Icon(widget.icon, color: widget.iconColor, size: widget.size * 0.4) : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(widget.icon, color: widget.iconColor), const SizedBox(width: 8), Text(widget.text!, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text))]),
        ),
      ),
    );
  }
}

class DocumentCard extends StatefulWidget {
  final String title;
  final String type;
  final String date;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const DocumentCard({Key? key, required this.title, required this.type, required this.date, required this.onTap, required this.onDelete}) : super(key: key);
  @override
  State<DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<DocumentCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    bool isPdf = widget.type == 'pdf';
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) { _controller.reverse(); widget.onTap(); },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: AppColors.shadow, offset: Offset(5, 5), blurRadius: 10), BoxShadow(color: Colors.white, offset: Offset(-5, -5), blurRadius: 10)]),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isPdf ? AppColors.primary.withOpacity(0.1) : AppColors.surface, borderRadius: BorderRadius.circular(10)), child: Icon(isPdf ? Icons.picture_as_pdf : Icons.edit_document, color: isPdf ? AppColors.primary : AppColors.text, size: 32)),
                    const Spacer(),
                    Text(widget.title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(widget.date, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.text.withOpacity(0.6))),
                  ],
                ),
              ),
              Positioned(top: 5, right: 5, child: IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.primary, size: 20), onPressed: widget.onDelete)),
            ],
          ),
        ),
      ),
    );
  }
}