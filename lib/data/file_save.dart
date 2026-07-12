// عمارتي — saving exports to the device (#41).
//
// Every export used to end at the system SHARE sheet, so a manager who just
// wanted the file on their phone had no way to get it. These helpers write the
// bytes to a real, user-reachable folder and hand back the path so the caller
// can show it.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The best user-reachable folder for a saved export.
///
/// Android: the public Downloads folder when it is writable, else the app's own
/// external files folder (scoped storage blocks the public one on newer
/// versions) — both are visible from a file manager.
/// Desktop: the OS Downloads folder. Anything else: the app documents folder.
Future<Directory> downloadsDir() async {
  try {
    if (Platform.isAndroid) {
      final public = Directory('/storage/emulated/0/Download');
      if (await public.exists()) {
        return public;
      }
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        return ext;
      }
    } else {
      final dl = await getDownloadsDirectory();
      if (dl != null) {
        return dl;
      }
    }
  } catch (_) {
    // Fall through to the always-available documents folder.
  }
  return getApplicationDocumentsDirectory();
}

/// Write [bytes] as [fileName] into [downloadsDir]; returns the full path.
/// A same-named file is suffixed rather than overwritten.
Future<String> saveToDownloads(String fileName, List<int> bytes) async {
  final dir = await downloadsDir();
  var file = File('${dir.path}${Platform.pathSeparator}$fileName');
  if (await file.exists()) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    for (var i = 2; await file.exists(); i++) {
      file = File('${dir.path}${Platform.pathSeparator}$stem-$i$ext');
    }
  }
  await file.writeAsBytes(bytes);
  return file.path;
}
