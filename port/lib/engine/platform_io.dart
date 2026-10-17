import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Opens [url] in the system browser (the original used getURL(url, "_blank")).
void openUrlNative(String url) {
  try {
    if (Platform.isWindows) {
      final shell32 = DynamicLibrary.open('shell32.dll');
      final shellExecute = shell32.lookupFunction<
          IntPtr Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, int)>('ShellExecuteW');
      final op = 'open'.toNativeUtf16();
      final file = url.toNativeUtf16();
      shellExecute(0, op, file, nullptr, nullptr, 1);
      malloc.free(op);
      malloc.free(file);
    } else if (Platform.isAndroid) {
      const MethodChannel('org.decomp.therightmix/platform').invokeMethod('openUrl', {'url': url});
    }
  } catch (_) {}
}
