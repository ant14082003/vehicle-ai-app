import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppConstants {
  /// The backend server URL.
  /// Reads from .env file — change .env to switch between
  /// local development and production without touching any other file.
  static String get baseUrl {
    final url = dotenv.env['BASE_URL'];
    if (url == null || url.isEmpty) {
      // Fallback if .env not loaded
      return 'https://fypbackend-production-71db.up.railway.app';
    }
    return url;
  }

  /// Current logged-in Firebase user ID
  static String get userId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'default';
}
