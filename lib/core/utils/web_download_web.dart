import 'dart:convert';
import 'dart:html' as html;

void downloadText(String name, String content) {
  final blob = html.Blob([utf8.encode(content)], 'text/html');
  html.AnchorElement(href: html.Url.createObjectUrlFromBlob(blob))
    ..setAttribute('download', name)
    ..click();
}
