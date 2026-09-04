import 'dart:typed_data';

/// Abstract interface for file system operations that differ between platforms.
///
/// On Android: saves to the Downloads folder.
/// On iOS: saves to the app sandbox and presents the share sheet.
abstract class FileService {
  /// Saves bytes to a file. Returns the saved file path.
  /// On Android, saves to the public Downloads directory.
  /// On iOS, saves to the app's Documents directory.
  Future<String> saveFile({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  });

  /// Opens the platform share sheet for the given file.
  Future<void> shareFile({
    required String filePath,
    String? mimeType,
    String? subject,
  });

  /// Saves bytes and immediately shares them.
  Future<void> saveAndShare({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String? subject,
  });
}
