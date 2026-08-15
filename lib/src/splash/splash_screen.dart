import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// A small, branded animated splash screen.
///
/// Shows the Docvera mark with a fade + scale-in animation on the brand
/// background, then calls [onDone] so the caller can swap in the real home
/// screen. Kept tiny on purpose — no assets, just one logo glyph.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
    _scale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    // Hold a moment after the animation settles, then hand off to HomeScreen.
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.deepBlue,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf,
                    color: AppColors.deepBlue,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Docvera',
                  style: textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'PDF Editor',
                  style: textTheme.bodyMedium?.copyWith(
                    color: const Color(0xB3FFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}