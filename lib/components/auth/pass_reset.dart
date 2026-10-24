// The "Change Password" box used by the employee dashboard and My Profile:
// it emails a recovery link to the account's address
// (POST /accounts/password-reset/).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/auth/auth_service.dart';
import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/utils/toast.dart';

const _gray100 = Color(0xFFF3F4F6);
const _gray500 = Color(0xFF6B7280);
const _gray700 = Color(0xFF374151);
const _gray900 = Color(0xFF111827);
const _indigo50 = Color(0xFFEEF2FF);
const _indigo100 = Color(0xFFE0E7FF);
const _indigo500 = Color(0xFF6366F1);
const _indigo600 = Color(0xFF4F46E5);
const _red600 = Color(0xFFDC2626);
const _green600 = Color(0xFF16A34A);

/// Opens the dialog for the signed-in user.
Future<void> showPasswordResetDialog(
  BuildContext context, {
  String intro = "We'll send a secure recovery link to:",
  String noEmailError = 'No registered email address found.',
}) {
  final email = '${context.read<AuthStore>().user?['email'] ?? ''}'.trim();
  return showDialog<void>(
    context: context,
    builder: (_) => _PasswordResetDialog(email: email, intro: intro, noEmailError: noEmailError),
  );
}

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({required this.email, required this.intro, required this.noEmailError});

  final String email;
  final String intro;
  final String noEmailError;

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  bool _sending = false;
  String? _error;
  String? _success;

  bool get _hasEmail => widget.email.isNotEmpty;

  Future<void> _send() async {
    if (!_hasEmail) {
      setState(() => _error = widget.noEmailError);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _success = null;
    });
    try {
      await authService.requestPasswordReset(widget.email);
      if (!mounted) return;
      setState(() => _success = 'A recovery link has been sent to your email!');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (err) {
      if (mounted) setState(() => _error = apiError(err, 'Failed to send recovery link.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Change Password',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _gray900),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20, color: _gray500),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _indigo50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _indigo100),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.mail_outline, size: 40, color: _indigo500),
                    const SizedBox(height: 12),
                    const Text(
                      'SECURE RESET VIA EMAIL',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: _gray700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.intro,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, height: 1.5, color: _gray700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hasEmail ? widget.email : 'No email registered',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _gray900),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: _red600)),
              ],
              if (_success != null) ...[
                const SizedBox(height: 16),
                Text(_success!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: _green600)),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: _gray100,
                        foregroundColor: _gray700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _indigo600,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: (_sending || !_hasEmail) ? null : _send,
                      child: Text(
                        _sending ? 'Sending…' : 'Send Recovery Link',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}