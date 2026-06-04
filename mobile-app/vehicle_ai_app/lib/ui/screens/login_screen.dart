import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'garage_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // toggle between login and signup
  bool _isLoading = false;
  String _error = "";

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = "";
    });

    try {
      await AuthService.signInWithGoogle();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GarageScreen()),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),

              // Logo / Title
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: AppTheme.accentGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.garage_rounded,
                        color: AppTheme.bg,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text("AutoVault", style: AppTheme.displayLarge),
                    const SizedBox(height: 6),
                    Text(
                      "Vehicle Management System",
                      style: AppTheme.bodyMedium,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),
              const SizedBox(height: 24),
              const SizedBox(height: 14),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppTheme.danger,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error,
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.accent,
                          strokeWidth: 2,
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: _isLoading
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: AppTheme.accent,
                                  strokeWidth: 2,
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: _signInWithGoogle,
                                style: AppTheme.primaryButton,
                                icon: const Icon(Icons.login),
                                label: const Text("Sign in with Google"),
                              ),
                      ),
              ),
              const SizedBox(height: 12),

              const SizedBox(height: 40),

              Center(
                child: Text(
                  "Your vehicle data is private and secure.\nOnly you can see your vehicles.",
                  style: AppTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
