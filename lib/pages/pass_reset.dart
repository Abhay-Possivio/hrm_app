import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hrm_app/components/auth/shader.dart';

/// Port of pages/PasswordResetMaintenance.tsx, shown for /forgot-password
/// while password reset by email is being set up.
class PasswordResetMaintenancePage extends StatelessWidget {
  const PasswordResetMaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0818),
      body: Stack(
        children: [
          const Positioned.fill(child: ShaderBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0xA6140628),
                              offset: Offset(0, 30),
                              blurRadius: 80,
                              spreadRadius: -20,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Image.asset('assets/logo.png', height: 64, semanticLabel: 'BTrillions'),
                            const SizedBox(height: 24),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: const Icon(Icons.build_outlined, color: Color(0xFFD97706)),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Under maintenance',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Password reset is temporarily unavailable while we upgrade it. '
                              'Please contact your HR team or administrator to reset your password.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF6B7280)),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF4E2F68), Color(0xFF6A3FC2), Color(0xFF8B5CF6)],
                                  ),
                                ),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => context.go('/login'),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.arrow_back, size: 16, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text(
                                          'Back to sign in',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '© ${DateTime.now().year} BTrillions',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}