import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'upload_document_screen.dart';
import 'garage_screen.dart';

class LoginScreen extends StatelessWidget {
  LoginScreen({super.key});

  final AuthService authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final user = await authService.signInWithGoogle();

            if (user != null) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const GarageScreen()),
              );
            } else {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Login Failed")));
            }
          },
          child: const Text("Sign in with Google"),
        ),
      ),
    );
  }
}
