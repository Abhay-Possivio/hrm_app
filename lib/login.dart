import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:hrm_app/auth/auth_service.dart';
import 'package:hrm_app/auth/auth_store.dart';
import 'package:hrm_app/components/auth/attendance_backdrop.dart';

/// Colors carried over from the Tailwind classes in the React version.
class _C {
  /// Page background (`bg-[#f6f2fc]`).
  static const bg = Color(0xFFF6F2FC);
  static const brandDeep = Color(0xFF4E2F68);
  static const brand = Color(0xFF6A3FC2);
  static const brandLight = Color(0xFF8B5CF6);
  static const focus = Color(0xFF7E52D9);

  static const gray50 = Color(0xFFF9FAFB);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray900 = Color(0xFF111827);

  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  String _error = '';
  bool _showPassword = false;

  // Card entrance: 700ms, cubic-bezier(.2,.7,.2,1), 120ms delay.
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _riseCurve = CurvedAnimation(
    parent: _rise,
    curve: const Cubic(.2, .7, .2, 1),
  );

  // Error shake: 400ms, 0 → -4 → 4 → 0.
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final Animation<double> _shakeOffset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -4), weight: 25),
    TweenSequenceItem(tween: Tween(begin: -4, end: 4), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 25),
  ]).animate(CurvedAnimation(parent: _shake, curve: const Cubic(.36, .07, .19, .97)));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _rise.forward();
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _rise.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() => _error = message);
    if (!MediaQuery.disableAnimationsOf(context)) _shake.forward(from: 0);
  }

  Future<void> _handleLogin() async {
    if (_loading) return;

    // Stand-in for the HTML `required` attribute.
    if (_username.text.isEmpty || _password.text.isEmpty) {
      _showError('Enter your username and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      await authService.login(_username.text, _password.text);
      final user = await authService.me();
      if (!mounted) return;
      context.read<AuthStore>().setUser(user);
      TextInput.finishAutofillContext(); // lets the OS offer to save the password
      context.go('/');
    } catch (err) {
      if (!mounted) return;
      _showError(_extractMessage(err));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Mirrors the React logic: prefer `detail`, then `error`, from the response body.
  String _extractMessage(Object err) {
    const fallback = 'Invalid credentials. Please try again.';
    if (err is DioException) {
      final data = err.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String) return detail;
        final error = data['error'];
        if (error is String) return error;
      }
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Equivalents of the [@media(max-height:…)] variants.
    final compact = size.height <= 700;
    final tiny = size.height <= 480;
    final hideCopyright = size.height <= 620;
    final wide = size.width >= 640; // Tailwind `sm:`

    // Light page, so dark status-bar icons.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      // The backdrop sits behind the Scaffold so it keeps the full screen size
      // when the keyboard opens (only the form area shrinks and scrolls).
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _C.bg),
          const AttendanceBackdrop(),
          Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const vPad = 16.0;
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: vPad),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight - vPad * 2),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: _riseIn(
                            reduceMotion: reduceMotion,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildCard(compact: compact, tiny: tiny, wide: wide),
                                if (!hideCopyright)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(
                                      '© ${DateTime.now().year} BTrillions',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _C.brandDeep.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _riseIn({required bool reduceMotion, required Widget child}) {
    if (reduceMotion) return child;
    return FadeTransition(
      opacity: _riseCurve,
      child: AnimatedBuilder(
        animation: _riseCurve,
        builder: (_, c) => Transform.translate(
          offset: Offset(0, 14 * (1 - _riseCurve.value)),
          child: c,
        ),
        child: child,
      ),
    );
  }

  Widget _buildCard({required bool compact, required bool tiny, required bool wide}) {
    final padding = tiny
        ? const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
        : compact
            ? const EdgeInsets.all(24)
            : EdgeInsets.all(wide ? 32 : 28);
    final gap = tiny ? 8.0 : compact ? 12.0 : 16.0;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        // ring-1 ring-[#4E2F68]/10
        border: Border.all(color: _C.brandDeep.withValues(alpha: 0.1)),
        // shadow-[0_24px_60px_-24px_rgba(78,47,104,0.45)]
        boxShadow: [
          BoxShadow(
            color: _C.brandDeep.withValues(alpha: 0.45),
            offset: const Offset(0, 24),
            blurRadius: 60,
            spreadRadius: -24,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Image.asset(
            'assets/logoname.png',
            height: tiny ? 36 : compact ? 48 : 64,
            semanticLabel: 'BTrillions',
          ),
          SizedBox(height: tiny ? 4 : compact ? 12 : 16),
          Text(
            'Welcome back',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: tiny ? 18 : compact ? 20 : 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: _C.gray900,
            ),
          ),
          if (!tiny) ...[
            const SizedBox(height: 4),
            const Text(
              'Sign in to continue to your workspace',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _C.gray500),
            ),
          ],
          SizedBox(height: tiny ? 8 : compact ? 16 : 24),

          // Form
          AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error.isNotEmpty) ...[
                  _buildErrorBanner(),
                  SizedBox(height: gap),
                ],
                _AuthField(
                  label: 'Username',
                  controller: _username,
                  icon: Icons.person_outline,
                  hint: 'Enter your username',
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                ),
                SizedBox(height: gap),
                _AuthField(
                  label: 'Password',
                  controller: _password,
                  icon: Icons.lock_outline,
                  hint: '••••••••',
                  obscureText: !_showPassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                  labelTrailing: _HoverLink(
                    text: 'Forgot password?',
                    tooltip: 'Recover your account',
                    onTap: () => context.push('/forgot-password'),
                  ),
                  suffix: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                      tooltip: _showPassword ? 'Hide password' : 'Show password',
                      icon: Icon(
                        _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      ),
                      iconSize: 20,
                      color: _C.gray400,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                SizedBox(height: gap),
                _GradientButton(
                  height: tiny ? 40 : 48,
                  loading: _loading,
                  onPressed: _handleLogin,
                ),
              ],
            ),
          ),

          // Footer
          if (!tiny) ...[
            SizedBox(height: compact ? 16 : 24),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined, size: 14, color: _C.gray400),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Authorized personnel only · Secure connection',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _C.gray400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Semantics(
      liveRegion: true, // same role as role="alert"
      child: AnimatedBuilder(
        animation: _shakeOffset,
        builder: (_, child) => Transform.translate(
          offset: Offset(_shakeOffset.value, 0),
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _C.red50,
            border: Border.all(color: _C.red200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: _C.red500, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _C.red600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled text field with the focus ring from `focus:ring-4 focus:ring-[#7e52d9]/15`.
class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.hint,
    this.labelTrailing,
    this.obscureText = false,
    this.suffix,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final Widget? labelTrailing;
  final bool obscureText;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _C.gray600,
              ),
            ),
            const Spacer(),
            if (widget.labelTrailing != null) widget.labelTrailing!,
          ],
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              if (_focused)
                BoxShadow(color: _C.focus.withValues(alpha: 0.15), spreadRadius: 4),
            ],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.obscureText,
            autofillHints: widget.autofillHints,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            autocorrect: false,
            enableSuggestions: !widget.obscureText,
            cursorColor: _C.focus,
            style: const TextStyle(fontSize: 14, color: _C.gray900),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(fontSize: 14, color: _C.gray400),
              filled: true,
              fillColor: _focused ? Colors.white : _C.gray50,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              prefixIcon: Icon(widget.icon, size: 16, color: _C.gray400),
              prefixIconConstraints: const BoxConstraints(minWidth: 40),
              suffixIcon: widget.suffix,
              enabledBorder: _border(_C.gray200),
              focusedBorder: _border(_C.focus),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Forgot password?" link with the hover color change.
class _HoverLink extends StatefulWidget {
  const _HoverLink({required this.text, required this.tooltip, required this.onTap});

  final String text;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<_HoverLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        link: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _hover ? _C.brandDeep : _C.brand,
              ),
              child: Text(widget.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient submit button with hover shimmer, press scale and loading spinner.
class _GradientButton extends StatefulWidget {
  const _GradientButton({
    required this.height,
    required this.loading,
    required this.onPressed,
  });

  final double height;
  final bool loading;
  final VoidCallback onPressed;

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: disabled ? 'Signing in' : null,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
          onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: disabled ? null : widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1,
            duration: const Duration(milliseconds: 150),
            child: AnimatedOpacity(
              opacity: disabled ? 0.7 : 1,
              duration: const Duration(milliseconds: 200),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [_C.brandDeep, _C.brand, _C.brandLight],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _C.brand.withValues(alpha: _hover ? 0.4 : 0.3),
                      blurRadius: _hover ? 25 : 15,
                      offset: Offset(0, _hover ? 20 : 10),
                      spreadRadius: _hover ? -5 : -3,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Shimmer sweep on hover
                      AnimatedSlide(
                        offset: _hover ? const Offset(1, 0) : const Offset(-1, 0),
                        duration: const Duration(milliseconds: 1000),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.2),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: widget.loading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                  backgroundColor: Colors.white.withValues(alpha: 0.3),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Sign in',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedSlide(
                                    offset: _hover ? const Offset(0.25, 0) : Offset.zero,
                                    duration: const Duration(milliseconds: 150),
                                    child: const Icon(
                                      Icons.arrow_forward,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}