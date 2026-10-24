// Small replacements for react-hot-toast and the shared apiError() helper.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Short message at the bottom of the screen (toast.success / toast.error).
void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? const Color(0xFFB91C1C) : const Color(0xFF111827),
      ),
    );
}

/// The API's `detail` or `error` message, or [fallback].
String apiError(Object err, String fallback) {
  if (err is DioException) {
    final data = err.response?.data;
    if (data is Map) {
      final message = data['detail'] ?? data['error'];
      if (message is String && message.isNotEmpty) return message;
    }
  }
  return fallback;
}