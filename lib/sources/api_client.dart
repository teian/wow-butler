import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/app_version.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.uri});

  final String message;
  final int? statusCode;
  final Uri? uri;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

/// Thin JSON wrapper around [http.Client] shared by all sources.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  static const userAgent =
      'wow-butler/${appVersion ?? 'dev'} (+https://github.com)';
  static const _timeout = Duration(seconds: 30);

  final http.Client _client;

  Future<Object?> getJson(Uri uri, {Map<String, String>? headers}) =>
      _send(() => _client.get(uri, headers: _headers(headers)), uri);

  Future<Object?> postJson(
    Uri uri,
    Object body, {
    Map<String, String>? headers,
  }) => _send(
    () => _client.post(
      uri,
      headers: _headers({
        ...?headers,
        HttpHeaders.contentTypeHeader: 'application/json',
      }),
      body: jsonEncode(body),
    ),
    uri,
  );

  /// Streams [uri] into [target], reporting progress in `0..1` when the
  /// server sends a content length.
  Future<void> download(
    Uri uri,
    File target, {
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', uri)..headers.addAll(_headers(headers));
    final response = await _client.send(request).timeout(_timeout);
    if (response.statusCode >= 400) {
      throw ApiException(
        'Download fehlgeschlagen',
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    await target.parent.create(recursive: true);
    final sink = target.openWrite();
    final total = response.contentLength;
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(_timeout)) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
  }

  Map<String, String> _headers(Map<String, String>? extra) => {
    HttpHeaders.userAgentHeader: userAgent,
    HttpHeaders.acceptHeader: 'application/json',
    ...?extra,
  };

  Future<Object?> _send(
    Future<http.Response> Function() request,
    Uri uri,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Zeitüberschreitung bei ${uri.host}', uri: uri);
    } on SocketException catch (e) {
      throw ApiException(
        '${uri.host} nicht erreichbar: ${e.message}',
        uri: uri,
      );
    } on http.ClientException catch (e) {
      throw ApiException('${uri.host}: ${e.message}', uri: uri);
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        _errorMessage(response),
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException('Ungültige Antwort von ${uri.host}', uri: uri);
    }
  }

  String _errorMessage(http.Response response) {
    return switch (response.statusCode) {
      401 || 403 => 'Zugriff verweigert – API-Schlüssel prüfen',
      404 => 'Nicht gefunden',
      429 => 'Zu viele Anfragen – bitte später erneut versuchen',
      >= 500 => 'Serverfehler',
      _ => 'Anfrage fehlgeschlagen',
    };
  }

  void close() => _client.close();
}

/// Helpers for reading loosely typed JSON.
extension JsonRead on Map<String, dynamic> {
  String? str(String key) {
    final v = this[key];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  int? integer(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  DateTime? date(String key) {
    final v = this[key];
    return v is String ? DateTime.tryParse(v) : null;
  }

  Map<String, dynamic>? obj(String key) {
    final v = this[key];
    return v is Map<String, dynamic> ? v : null;
  }

  List<Map<String, dynamic>> objs(String key) {
    final v = this[key];
    if (v is! List) return const [];
    return v.whereType<Map<String, dynamic>>().toList();
  }
}

/// Removes HTML tags and collapses whitespace, for summaries built from
/// HTML descriptions.
String plainText(String html, {int maxLength = 300}) {
  final text = html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';
}

/// Converts an HTML changelog to plain text, keeping paragraph and list
/// structure as lines.
String htmlToText(String html) {
  final withBreaks = html
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '\n- ')
      .replaceAll(
        RegExp(r'</\s*(p|div|h[1-6]|ul|ol|li)\s*>', caseSensitive: false),
        '\n',
      );
  return withBreaks
      .split('\n')
      .map((line) => plainText(line, maxLength: 1 << 20))
      .where((line) => line.isNotEmpty)
      .join('\n');
}
