import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/database_helper.dart';
import '../library/subject_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> folders = [];
  List<Map<String, dynamic>> upcomingEvents = [];

  String userName = "There";

  @override
  void initState() {
    super.initState();
    _refreshFolders();
    _loadUserName(); // 2. Call the loader
  }

  Future<void> _refreshFolders() async {
    final data = await DatabaseHelper.instance.getSubjects();
    setState(() {
      folders = data;
    });
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('userName') ?? 'There';
    });
  }

  String _getEmojiForSubject(String subjectName) {
    final lowerName = subjectName.toLowerCase();
    if (lowerName.contains('medical') || lowerName.contains('bio') || lowerName.contains('anatomy')) return '🔬';
    if (lowerName.contains('math') || lowerName.contains('calculus') || lowerName.contains('algebra')) return '➗';
    if (lowerName.contains('physics') || lowerName.contains('dynamics')) return '⚛️';
    if (lowerName.contains('chem')) return '🧪';
    if (lowerName.contains('computer') || lowerName.contains('dsa') || lowerName.contains('coa') || lowerName.contains('code')) return '💻';
    if (lowerName.contains('art') || lowerName.contains('design')) return '🎨';
    return '📚';
  }

  void _showAddFolderDialog({String initialText = ''}) {
    TextEditingController controller = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('New Subject Chamber', style: GoogleFonts.poppins(color: AppColors.text, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g., Computer Architecture',
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
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  _handleFolderCreation(name);
                }
              },
              child: const Text('Create', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleFolderCreation(String name) async {
    int existingIndex = folders.indexWhere((f) => f['name'] == name);
    
    if (existingIndex != -1) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Folder Already Exists', style: GoogleFonts.poppins(color: AppColors.text, fontWeight: FontWeight.bold)),
          content: const Text('A chamber with this name already exists. What would you like to do?', style: TextStyle(color: AppColors.text)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showAddFolderDialog(initialText: name);
              },
              child: const Text('Rename', style: TextStyle(color: AppColors.text)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final updatedFolder = {
                  'id': folders[existingIndex]['id'],
                  'name': name,
                  'emoji': _getEmojiForSubject(name),
                };
                await DatabaseHelper.instance.insertSubject(updatedFolder);
                _refreshFolders();
              },
              child: const Text('Replace', style: TextStyle(color: AppColors.secondary)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final newFolder = {
                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'name': '$name (Copy)',
                  'emoji': _getEmojiForSubject(name),
                };
                await DatabaseHelper.instance.insertSubject(newFolder);
                _refreshFolders();
              },
              child: const Text('Keep Copy', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      final newFolder = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': name,
        'emoji': _getEmojiForSubject(name),
      };
      await DatabaseHelper.instance.insertSubject(newFolder);
      _refreshFolders();
    }
  }

  void _deleteFolder(String id, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete $name?', style: GoogleFonts.poppins(color: AppColors.primary, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure? All files inside this chamber will be deleted.', style: TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await DatabaseHelper.instance.deleteSubject(id);
              _refreshFolders();
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openCustomCalendar() {
    showDialog(
      context: context,
      builder: (context) {
        return NeumorphicCalendarDialog(
          events: upcomingEvents,
          onAddEvent: (date, time, title) {
            setState(() {
              upcomingEvents.add({'title': title, 'date': date, 'time': time});
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    int crossAxisCount = MediaQuery.of(context).size.width > 600 ? 3 : 2;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: AppColors.shadow, offset: Offset(6, 6), blurRadius: 10),
                    BoxShadow(color: Colors.white, offset: Offset(-6, -6), blurRadius: 10),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hi $userName 😊💖', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          const SizedBox(height: 8),
                          Text("What's in your mind today?", style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                          const SizedBox(height: 4),
                          Text("Revision, Notes or Anything Special", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.text.withOpacity(0.8))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: _openCustomCalendar,
                      child: Container(
                        height: 90, width: 80,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: AppColors.text.withOpacity(0.4), width: 1.5),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.calendar_month, color: AppColors.primary, size: 28),
                            const SizedBox(height: 6),
                            Text(upcomingEvents.isEmpty ? 'Mark\nDate' : '${upcomingEvents.length}\nEvents', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 20, mainAxisSpacing: 20, childAspectRatio: 1.0),
                  itemCount: folders.length + 1,
                  itemBuilder: (context, index) {
                    if (index == folders.length) return _buildAddFolderButton();
                    return SubjectCard(
                      name: folders[index]['name'],
                      emoji: folders[index]['emoji'],
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SubjectDetailScreen(
                              subjectId: folders[index]['id'],
                              subjectName: folders[index]['name'],
                            ),
                          ),
                        );
                      },
                      onDelete: () => _deleteFolder(folders[index]['id'], folders[index]['name']),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddFolderButton() {
    return GestureDetector(
      onTap: () => _showAddFolderDialog(),
      child: CustomPaint(
        painter: DashedBorderPainter(color: AppColors.text.withOpacity(0.5)),
        child: Container(
          decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.3), borderRadius: BorderRadius.circular(20)),
          child: Center(child: Icon(Icons.add, size: 40, color: AppColors.text.withOpacity(0.6))),
        ),
      ),
    );
  }
}

class NeumorphicCalendarDialog extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final Function(DateTime date, TimeOfDay time, String title) onAddEvent;
  const NeumorphicCalendarDialog({Key? key, required this.events, required this.onAddEvent}) : super(key: key);
  @override
  State<NeumorphicCalendarDialog> createState() => _NeumorphicCalendarDialogState();
}

class _NeumorphicCalendarDialogState extends State<NeumorphicCalendarDialog> {
  late DateTime _focusedDate;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _focusedDate = DateTime.now();
    _selectedDate = DateTime.now();
  }

  Map<String, dynamic>? _getEventForDate(DateTime date) {
    for (var event in widget.events) {
      if (event['date'].year == date.year && event['date'].month == date.month && event['date'].day == date.day) {
        return event;
      }
    }
    return null;
  }

  void _addEventFlow() async {
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primary, onSurface: AppColors.text), dialogBackgroundColor: AppColors.background), child: child!),
    );
    if (pickedTime == null) return;

    if (!mounted) return;
    TextEditingController eventController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Name your Event', style: GoogleFonts.poppins(color: AppColors.text, fontWeight: FontWeight.bold)),
        content: TextField(controller: eventController, autofocus: true, decoration: const InputDecoration(focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary))), style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
            onPressed: () {
              if (eventController.text.trim().isNotEmpty) {
                widget.onAddEvent(_selectedDate, pickedTime, eventController.text.trim());
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('Save Event', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int daysInMonth = DateUtils.getDaysInMonth(_focusedDate.year, _focusedDate.month);
    int firstWeekday = DateTime(_focusedDate.year, _focusedDate.month, 1).weekday;
    int offset = firstWeekday == 7 ? 0 : firstWeekday;
    var selectedEvent = _getEventForDate(_selectedDate);

    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat('EEEE, MMMM d').format(_selectedDate), style: GoogleFonts.poppins(fontSize: 18, color: AppColors.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(selectedEvent != null ? selectedEvent['title'] : 'No events scheduled', style: GoogleFonts.poppins(fontSize: selectedEvent != null ? 20 : 14, color: selectedEvent != null ? AppColors.primary : AppColors.text.withOpacity(0.5), fontWeight: selectedEvent != null ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left, color: AppColors.text), onPressed: () => setState(() => _focusedDate = DateTime(_focusedDate.year, _focusedDate.month - 1))),
                Text(DateFormat('MMMM yyyy').format(_focusedDate), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text)),
                IconButton(icon: const Icon(Icons.chevron_right, color: AppColors.text), onPressed: () => setState(() => _focusedDate = DateTime(_focusedDate.year, _focusedDate.month + 1))),
              ],
            ),
            GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1),
              itemCount: daysInMonth + offset,
              itemBuilder: (context, index) {
                if (index < offset) return const SizedBox.shrink();
                int day = index - offset + 1;
                DateTime currentDay = DateTime(_focusedDate.year, _focusedDate.month, day);
                bool isSelected = _selectedDate.day == day && _selectedDate.month == currentDay.month;
                bool hasEvent = _getEventForDate(currentDay) != null;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDate = currentDay),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(10), border: isSelected ? Border.all(color: AppColors.primary, width: 1.5) : null),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$day', style: GoogleFonts.poppins(color: hasEvent ? AppColors.primary : AppColors.text, fontWeight: hasEvent ? FontWeight.bold : FontWeight.normal, fontSize: hasEvent ? 16 : 14)),
                        if (hasEvent) Container(margin: const EdgeInsets.only(top: 2), width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle))
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: AppColors.text))),
                ElevatedButton(onPressed: _addEventFlow, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 0), child: Text('Mark Date', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold))),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class SubjectCard extends StatefulWidget {
  final String name;
  final String emoji;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const SubjectCard({Key? key, required this.name, required this.emoji, required this.onTap, this.onDelete}) : super(key: key);
  @override
  State<SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends State<SubjectCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) { _controller.reverse(); widget.onTap(); },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: AppColors.shadow, offset: Offset(6, 6), blurRadius: 10), BoxShadow(color: Colors.white, offset: Offset(-6, -6), blurRadius: 10)]),
          child: Stack(
            children: [
              Positioned(right: -10, bottom: -10, child: Opacity(opacity: 0.15, child: Text(widget.emoji, style: const TextStyle(fontSize: 80)))),
              Padding(padding: const EdgeInsets.all(16.0), child: Align(alignment: Alignment.topLeft, child: Text(widget.name, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text), maxLines: 3, overflow: TextOverflow.ellipsis))),
              if (widget.onDelete != null)
                Positioned(
                  top: 5,
                  right: 5,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.primary, size: 20),
                    onPressed: widget.onDelete,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  final Color color;
  DashedBorderPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    final path = Path();
    path.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(20)));
    const dashWidth = 8.0, dashSpace = 6.0;
    var distance = 0.0;
    for (PathMetric pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        canvas.drawPath(pathMetric.extractPath(distance, distance + dashWidth), paint);
        distance += dashWidth + dashSpace;
      }
      distance = 0.0;
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}