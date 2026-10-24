import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/auth/auth_store.dart';

/// Superuser (platform) accounts are web-only.
class UnsupportedPage extends StatelessWidget {
  const UnsupportedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.desktop_windows_outlined, size: 40, color: Color(0xFF6366F1)),
                  const SizedBox(height: 16),
                  const Text(
                    'Platform admin is web-only',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Manage companies and the device fleet from the web console. '
                    'To use the app, sign in with a company, HR or employee account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => context.read<AuthStore>().logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}