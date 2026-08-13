import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter/material.dart';

import 'src/ads/ad_service.dart';
import 'src/home/home_screen.dart';
import 'src/legal/legal_pages.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();
  runApp(const PdfEditorApp());
  try {
    // Banners are optional; SDK or consent failures must never block startup.
    await AdService.instance.initialize();
  } catch (_) {
    // Ads stay collapsed (AdBannerView) if initialization fails.
  }
}

class PdfEditorApp extends StatefulWidget {
  const PdfEditorApp({super.key});

  @override
  State<PdfEditorApp> createState() => _PdfEditorAppState();
}

class _PdfEditorAppState extends State<PdfEditorApp> {
  ThemeMode _mode = ThemeMode.system;

  bool _effectiveDark(BuildContext context) {
    return switch (_mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context) ==
          Brightness.dark,
    };
  }

  void _toggleTheme() {
    setState(() {
      _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Docvera PDF Editor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      routes: {
        '/privacy': (_) => const PrivacyPolicyPage(),
        '/terms': (_) => const TermsOfServicePage(),
      },
      home: HomeScreen(
        darkMode: _effectiveDark(context),
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
