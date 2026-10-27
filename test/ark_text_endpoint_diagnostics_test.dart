import 'dart:convert';

import 'package:anime_chat_app/web_context_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit text endpoint keeps existing priority over environment', () {
    final resolved = WebContextService.textEndpointResolutionForTest(
      configured: ' ep-text-config ',
      environment: 'ep-text-env',
      visionEndpoint: 'ep-vision-old',
    );
    expect(resolved['endpoint'], 'ep-text-config');
    expect(resolved['source'], contains('doubaoTextEndpoint'));
    expect(resolved['usesVisionFallback'], isFalse);
  });

  test('environment is used when dedicated text configuration is empty', () {
    final resolved = WebContextService.textEndpointResolutionForTest(
      configured: ' ',
      environment: ' ep-text-env ',
      visionEndpoint: 'ep-vision-old',
    );
    expect(resolved['endpoint'], 'ep-text-env');
    expect(resolved['source'], contains('ARK_TEXT_ENDPOINT'));
    expect(resolved['usesVisionFallback'], isFalse);
  });

  test('legacy vision inheritance is identifiable rather than hidden', () {
    final resolved = WebContextService.textEndpointResolutionForTest(
      configured: '',
      environment: '',
      visionEndpoint: 'ep-vision-old',
    );
    expect(resolved['endpoint'], 'ep-vision-old');
    expect(resolved['source'], contains('doubaoVisionEndpoint'));
    expect(resolved['usesVisionFallback'], isTrue);
  });

  test('missing endpoint stays empty and does not invent a model', () {
    final resolved = WebContextService.textEndpointResolutionForTest(
      configured: '',
      environment: ' ',
      visionEndpoint: '',
    );
    expect(resolved['endpoint'], isEmpty);
    expect(resolved['source'], '未配置');
    expect(resolved['usesVisionFallback'], isFalse);
  });

  test('closed endpoint error identifies remote issue without guessing cause',
      () {
    final diagnostic = WebContextService.closedTextEndpointDiagnosticForTest(
      jsonEncode({
        'error': {
          'code': 'InvalidEndpoint.ClosedEndpoint',
          'message':
              'The request targeted an endpoint that is currently closed',
        },
      }),
      endpoint: 'ep-closed-test',
    );
    expect(diagnostic, contains('ep-closed-test'));
    expect(diagnostic, contains('服务端已关闭或暂不可用'));
    expect(diagnostic, contains('ARK_TEXT_ENDPOINT'));
    expect(diagnostic, contains('不能确定'));
  });

  test('other errors are not mislabeled as closed endpoints', () {
    for (final body in [
      'ClosedEndpoint',
      'not json',
      '[]',
      '{"error": "InvalidEndpoint.ClosedEndpoint"}',
      '{"error": {"code": "AuthenticationError"}}',
      '{"error": {"message": "InvalidEndpoint.ClosedEndpoint"}}',
    ]) {
      expect(
        WebContextService.closedTextEndpointDiagnosticForTest(
          body,
          endpoint: 'ep-test',
        ),
        isNull,
        reason: body,
      );
    }
  });
}
