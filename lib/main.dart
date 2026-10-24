import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme.dart';
import 'features/onboarding/splash_screen.dart';
import 'core/notification_service.dart'; // 1. Add this import

void main() async {
  // 2. We need this line because we are running async code before runApp()
  WidgetsFlutterBinding.ensureInitialized(); 
  
  // 3. Initialize the notifications and schedule the next 48 hours!
  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.scheduleHourlyMotivation();

  runApp(const PDFNotesApp());
}

class PDFNotesApp extends StatelessWidget {
  const PDFNotesApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BHONDU',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        // REPLACE THE TEXTTHEME LINE WITH THIS:
        fontFamily: GoogleFonts.poppins().fontFamily,
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      // The app now boots straight into the Splash Screen!
      home: const SplashScreen(),
    );
  }
}