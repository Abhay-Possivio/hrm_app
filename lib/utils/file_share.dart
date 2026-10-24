// Downloads a file from the API and opens the phone's share sheet for it
// (save to Files, email, WhatsApp, ...). The web app's "download" buttons
// use this in the app. Needs the share_plus package.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:share_plus/share_plus.dart';

import 'package:hrm_app/api/api_client.dart';

const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const pdfMime = 'application/pdf';
const csvMime = 'text/csv';

/// GETs [path] as raw bytes and shares it as [fileName].
Future<void> downloadAndShare(
  String path, {
  required String fileName,
  required String mimeType,
  Map<String, dynamic>? queryParameters,
  String? subject,
}) async {
  final res = await api.get<List<int>>(
    path,
    queryParameters: queryParameters,
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = Uint8List.fromList(res.data ?? const []);
  await Share.shareXFiles(
    [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
    fileNameOverrides: [fileName],
    subject: subject ?? fileName,
  );
}