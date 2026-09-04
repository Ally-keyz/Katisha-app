import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_service.dart';

class FileServiceImpl implements FileService {
  @override
  Future<String> saveFile({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Future<void> shareFile({
    required String filePath,
    String? mimeType,
    String? subject,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    await Share.shareXFiles(
      [XFile(filePath, mimeType: mimeType)],
      subject: subject,
    );
  }

  @override
  Future<void> saveAndShare({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String? subject,
  }) async {
    final path = await saveFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    await shareFile(
      filePath: path,
      mimeType: mimeType,
      subject: subject,
    );
  }
}
