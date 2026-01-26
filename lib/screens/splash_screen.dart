import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();

    // Navigate after 1 second
    Future.delayed(const Duration(milliseconds: 1000), () async {
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final onboardingComplete =
            prefs.getBool('onboarding_complete') ?? false;

        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder:
                  (context, animation, secondaryAnimation) =>
                      onboardingComplete
                          ? const HomeScreen()
                          : const OnboardingScreen(),
              transitionsBuilder: (
                context,
                animation,
                secondaryAnimation,
                child,
              ) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Set system UI styling
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Dark icons for white bg
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white, // Clean white background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo without "purple glow", just clean shadow
            Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _fadeAnimation.value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF128C7E),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF128C7E).withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Image.asset(
                      'assets/aura.png',
                      fit: BoxFit.cover,
                      // Fallback icon if asset missing
                      errorBuilder:
                          (context, error, stackTrace) => const Icon(
                            Icons.call,
                            size: 60,
                            color: Colors.white,
                          ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // App name - Clean dark text
            Opacity(
              opacity: _fadeAnimation.value,
              child: const Text(
                'AURA CALL',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900, // Heavy weight
                  color: Color(0xFF111B21),
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: _fadeAnimation.value * 0.7,
              child: const Text(
                'Connect Instantly',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8696A0),
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
