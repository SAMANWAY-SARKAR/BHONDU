import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../home/home_screen.dart';
import 'name_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  // Animation Phases
  late Animation<double> _scaleAnimation;
  late Animation<double> _textOpacityAnimation;
  late Animation<Color?> _bgColorAnimation;
  late Animation<Color?> _textColorAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _screenOpacityAnimation;

  Widget? _targetScreen;

  @override
  void initState() {
    super.initState();
    _checkPrefsAndLoad();

    // Total duration of the intro sequence is 3.5 seconds
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 3500));

    // Phase 1: Zoom in and Fade in together (0.0 to 0.4 seconds)
    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack))
    );
    _textOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.3, curve: Curves.easeIn))
    );

    // Phase 2: The "Splash" Color Swap (0.5 to 0.6 seconds)
    _bgColorAnimation = ColorTween(begin: Colors.white, end: AppColors.primary).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.6, curve: Curves.easeInOut))
    );
    _textColorAnimation = ColorTween(begin: AppColors.primary, end: Colors.white).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.6, curve: Curves.easeInOut))
    );

    // Phase 3: Slide up to top & Fade out (0.7 to 1.0 seconds)
    _slideAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -1.0)).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.7, 1.0, curve: Curves.easeInCubic))
    );
    _screenOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.7, 1.0, curve: Curves.easeOut))
    );

    // Start the animation and route when finished
    _controller.forward().then((_) {
      if (_targetScreen != null && mounted) {
         // Replaces the splash screen route with a 0-second transition 
         // so it seamlessly hands control over to the screen already underneath it
         Navigator.pushReplacement(
           context,
           PageRouteBuilder(
             pageBuilder: (context, animation, secondaryAnimation) => _targetScreen!,
             transitionDuration: Duration.zero,
           ),
         );
      }
    });
  }

  // Pre-load the target screen while the animation plays
  Future<void> _checkPrefsAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('userName');
    setState(() {
      _targetScreen = name == null ? const NameScreen() : const HomeScreen();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // Standard background for the screen behind it
      body: Stack(
        children: [
          // BOTTOM LAYER: The actual app (pre-loaded so it is ready to be revealed)
          if (_targetScreen != null) _targetScreen!,

          // TOP LAYER: The Animated Splash Overlay
          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _screenOpacityAnimation,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Container(
                    // White initially, turns Pink
                    color: _bgColorAnimation.value ?? Colors.white, 
                    child: Center(
                      child: FadeTransition(
                        opacity: _textOpacityAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Text(
                            'COGNIRE', 
                            style: GoogleFonts.poppins(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              // Pink initially, turns White
                              color: _textColorAnimation.value ?? AppColors.primary,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}