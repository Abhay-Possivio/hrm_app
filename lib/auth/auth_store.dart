import 'package:flutter/foundation.dart';

import 'token_service.dart';

/// Flutter version of useAuthStore (zustand → ChangeNotifier + provider).
///
/// Read once:        context.read<AuthStore>().setUser(user);
/// Rebuild on change: final user = context.watch<AuthStore>().user;
/// Select one field:  context.select<AuthStore, bool>((s) => s.isLoggedIn);
class AuthStore extends ChangeNotifier {
  Map<String, dynamic>? _user;

  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _user != null;

  void setUser(Map<String, dynamic>? user) {
    _user = user;
    notifyListeners();
  }

  /// The React version calls localStorage.clear(); here that means
  /// removing the saved tokens.
  Future<void> logout() async {
    await tokenService.clear();
    _user = null;
    notifyListeners();
  }
}