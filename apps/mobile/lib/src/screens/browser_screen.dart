import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../media/media_detector.dart';
import '../models/detected_media.dart';
import 'cast_media_dialog.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _web;
  final _address = TextEditingController(text: 'https://example.com');
  final List<DetectedMedia> _media = [];
  var _progress = 0;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) => setState(() => _progress = value),
          onPageFinished: (_) => _scan(),
          onNavigationRequest: (request) {
            _capture(request.url);
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_address.text));
  }

  Future<void> _scan() async {
    final raw = await _web.runJavaScriptReturningResult(MediaDetector.domScannerScript);
    String json = raw.toString();
    if (json.startsWith('"') && json.endsWith('"')) {
      json = jsonDecode(json) as String;
    }
    final decoded = jsonDecode(json);
    if (decoded is! List) return;
    for (final item in decoded.whereType<Map>()) {
      _capture(
        item['url']?.toString() ?? '',
        label: item['label']?.toString(),
        mime: item['type']?.toString(),
      );
    }
  }

  void _capture(String url, {String? label, String? mime}) {
    final candidate = MediaDetector.fromUrl(url, label: label, mime: mime);
    if (candidate == null || _media.contains(candidate)) return;
    setState(() => _media.add(candidate));
  }

  void _go() {
    var value = _address.text.trim();
    if (!value.contains('://')) {
      if (value.contains('.') && !value.contains(' ')) {
        value = 'https://$value';
      } else {
        value = 'https://www.google.com/search?q=${Uri.encodeQueryComponent(value)}';
      }
    }
    final uri = Uri.tryParse(value);
    if (uri != null) _web.loadRequest(uri);
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                IconButton(onPressed: _web.goBack, icon: const Icon(Icons.arrow_back)),
                Expanded(
                  child: TextField(
                    controller: _address,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _go(),
                    decoration: const InputDecoration(
                      hintText: 'Suchen oder URL eingeben',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(onPressed: _go, icon: const Icon(Icons.arrow_forward)),
                Badge(
                  label: Text('${_media.length}'),
                  isLabelVisible: _media.isNotEmpty,
                  child: IconButton(
                    tooltip: 'Gefundene Medien',
                    onPressed: _media.isEmpty ? null : () => _showMedia(context),
                    icon: const Icon(Icons.video_collection_outlined),
                  ),
                ),
              ],
            ),
          ),
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          Expanded(child: WebViewWidget(controller: _web)),
        ],
      ),
    );
  }

  void _showMedia(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _media.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _media[index];
          return ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(item.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${item.kind.name.toUpperCase()} • ${item.url.host}'),
            onTap: () async {
              Navigator.of(context).pop();
              final device = await showDialog<Object?>(
                context: this.context,
                builder: (_) => CastMediaDialog(media: item),
              );
              if (!mounted || device == null) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Wiedergabe an den Fernseher gesendet.')),
              );
            },
          );
        },
      ),
    );
  }
}
