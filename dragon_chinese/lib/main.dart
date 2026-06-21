import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design_system/design_system.dart';
import 'core/config/app_config.dart';
import 'features/shell/main_shell.dart';
import 'features/billing/screens/paywall_screen.dart';
import 'features/course/screens/exercise_debug_gallery_screen.dart';
import 'features/course/screens/practice_session_screen.dart';
import 'features/course/screens/quick_study_intro_screen.dart';
import 'features/course/screens/quick_study_exercise_screen.dart';
import 'features/course/screens/quick_study_summary_screen.dart';
import 'features/course/models/study_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('AppConfig.apiBaseUrl = ${AppConfig.apiBaseUrl}');

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const DragonChineseApp());
}

class DragonChineseApp extends StatefulWidget {
  const DragonChineseApp({super.key});

  @override
  State<DragonChineseApp> createState() => _DragonChineseAppState();
}

class _DragonChineseAppState extends State<DragonChineseApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dragon Chinese',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      routes: {
        ExerciseDebugGalleryScreen.routeName: (_) =>
            const ExerciseDebugGalleryScreen(),
        PracticeSessionScreen.routeName: (_) => const PracticeSessionScreen(),
        '/debug/practice': (_) => const PracticeSessionScreen(),
        '/paywall': (_) => const PaywallScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/quick-study-intro') {
          final session = settings.arguments as StudySession;
          return MaterialPageRoute(
            builder: (_) => QuickStudyIntroScreen(session: session),
          );
        }
        if (settings.name == '/quick-study-exercise') {
          final session = settings.arguments as StudySession;
          return MaterialPageRoute(
            builder: (_) => QuickStudyExerciseScreen(session: session),
          );
        }
        if (settings.name == '/quick-study-summary') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => QuickStudySummaryScreen(
              session: args['session'] as StudySession,
              wordScores: args['scores'] as Map<String, double>,
              timeSpentSeconds: args['timeSpent'] as int,
            ),
          );
        }
        return null;
      },
      home: const MainShell(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: DsColors.primary,
        brightness: Brightness.light,
        primary: DsColors.primary,
        secondary: DsColors.secondary,
        surface: DsColors.surface,
        error: DsColors.error,
      ),
      scaffoldBackgroundColor: DsColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: DsColors.surface,
        foregroundColor: DsColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: DsColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DsRadii.lg),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DsColors.primary,
          foregroundColor: DsColors.textOnPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.lg,
            vertical: DsSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DsRadii.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DsColors.primary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.lg,
            vertical: DsSpacing.sm,
          ),
          side: const BorderSide(color: DsColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DsRadii.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DsColors.textSecondary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.md,
            vertical: DsSpacing.xs,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DsRadii.md),
          ),
        ),
      ),
      textTheme: DsTypography.textTheme,
    );
  }
}
