import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../home/home_screen.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({Key? key}) : super(key: key);

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final TextEditingController _nameController = TextEditingController();

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      // Save the name permanently to the device
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', name);
      
      if (mounted) {
        // Replace this screen with the Home Screen so they can't swipe back to it
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome 💖',
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Let's set up your workspace.\nWhat should I call you?",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: AppColors.text.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 40),
              
              // Neumorphic Text Field
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: AppColors.shadow, offset: Offset(6, 6), blurRadius: 10, spreadRadius: 1),
                    BoxShadow(color: Colors.white, offset: Offset(-6, -6), blurRadius: 10, spreadRadius: 1),
                  ],
                ),
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: GoogleFonts.poppins(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 18),
                  decoration: InputDecoration(
                    hintText: 'Enter your name...',
                    hintStyle: TextStyle(color: AppColors.text.withOpacity(0.3)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _saveAndContinue(),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Neumorphic Continue Button
              Center(
                child: GestureDetector(
                  onTap: _saveAndContinue,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withOpacity(0.4), offset: const Offset(4, 4), blurRadius: 10),
                      ],
                    ),
                    child: Text(
                      'Continue',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}