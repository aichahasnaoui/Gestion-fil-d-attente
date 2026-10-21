import 'dart:html' as html;

void openFileUrl(String url, {String? fileName}) {
  html.window.open(url, '_blank');
}
