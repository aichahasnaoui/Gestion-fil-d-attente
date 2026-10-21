import 'file_opener_stub.dart'
    if (dart.library.html) 'file_opener_web.dart';

void openExternalFile(String url, {String? fileName}) {
  openFileUrl(url, fileName: fileName);
}
