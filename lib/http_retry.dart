import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RetryingHttp {
  static const int _maxAttempts = 2;
  static const Duration _retryDelay = Duration(milliseconds: 600);

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    required String operation,
  }) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        return await http.post(url, headers: headers, body: body);
      } catch (error) {
        final canRetry =
            isTransientNetworkException(error) && attempt < _maxAttempts;
        if (!canRetry) rethrow;

        debugPrint(
          '$operation 连接在传输前中断，'
          '${_retryDelay.inMilliseconds}ms 后自动重试 '
          '(${attempt + 1}/$_maxAttempts)',
        );
        await Future<void>.delayed(_retryDelay);
      }
    }

    throw StateError('网络重试流程未返回结果');
  }

  static bool isTransientNetworkException(Object error) {
    return error is HandshakeException ||
        error is SocketException ||
        error is http.ClientException;
  }
}
