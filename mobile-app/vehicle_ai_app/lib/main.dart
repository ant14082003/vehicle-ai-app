import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'ui/screens/garage_screen.dart';
import 'ui/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();

  runApp(const VehicleAIApp());
}

class VehicleAIApp extends StatelessWidget {
  const VehicleAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AutoVault',
      theme: AppTheme.theme,
      // StreamBuilder watches login state — auto navigates on login/logout
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Still loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: AppTheme.bg,
              body: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.accent,
                  strokeWidth: 2,
                ),
              ),
            );
          }
          // User is logged in — show garage
          if (snapshot.hasData && snapshot.data != null) {
            return const GarageScreen();
          }
          // Not logged in — show login
          return const LoginScreen();
        },
      ),
    );
  }
}
