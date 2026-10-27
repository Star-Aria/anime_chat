import 'dart:io';

import 'package:anime_chat_app/path_service.dart';

/// 本地只读诊断：不启动推理服务，也不调用远程 API。
void main() {
  final root = AppPaths.gptSovitsRoot;
  stdout.writeln('GPT-SoVITS: $root');
  var missing = false;
  final paths = <String>[
    AppPaths.gptSovitsPython,
    AppPaths.gptSovitsFfmpeg,
    '$root/api_v2.py',
    '$root/GPT_SoVITS/configs/tts_infer.yaml',
  ];

  // 从现有角色配置读取模型路径，避免维护第二份容易遗漏的模型清单。
  final characterConfig = File('lib/character_config.dart').readAsStringSync();
  final modelPaths = RegExp(r"r'(GPT-SoVITS\\[^']+\.(?:ckpt|pth))'")
      .allMatches(characterConfig)
      .map((match) => match.group(1)!)
      .toSet();
  for (final modelPath in modelPaths) {
    paths.add(AppPaths.resolve(modelPath));
  }
  for (final path in paths) {
    final exists = File(path).existsSync();
    stdout.writeln('${exists ? 'OK' : 'MISSING'}: $path');
    missing = missing || !exists;
  }
  stdout.writeln('Checked ${modelPaths.length} character model paths.');
  exitCode = missing ? 1 : 0;
}
