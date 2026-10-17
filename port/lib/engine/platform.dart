import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';

/// Opens [url] in the system browser (the original used getURL(url, "_blank")).
void openUrl(String url) => openUrlNative(url);
