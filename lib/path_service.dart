import 'dart:io';

class AppPaths {
  static final String _exeDir = File(Platform.resolvedExecutable).parent.path;
  static final String _cwd = Directory.current.path;

  static const String _legacyGptSovitsRoot =
      r'C:\GPT-SoVITS-v2pro-20250604-nvidia50';
  static const String _legacyReferenceAudioRoot = r'D:\AI model';
  static const String _legacyAveMujicaRoot = r'C:\AveMujica模型（V2pro版本）';
  static const String _legacyAppAssetRoot = r'C:\anime_chat';

  static String resolve(String path) {
    if (path.isEmpty || _isAbsolute(path)) return path;

    final normalized = path.replaceAll('/', r'\');
    final candidates = <String>[
      _join(_cwd, normalized),
      _join(_exeDir, normalized),
      _join(_parentOf(_exeDir), normalized),
      ..._legacyCandidates(normalized),
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
        return candidate;
      }
    }

    // 打包后的默认结构：整合包根目录/app/程序.exe，资源在 app 的同级目录。
    return _join(_parentOf(_exeDir), normalized);
  }

  static bool _isAbsolute(String path) =>
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');

  static List<String> _legacyCandidates(String path) {
    const gptPrefix = r'GPT-SoVITS\';
    const audioPrefix = r'reference_audio\';
    const avePrefix = r'AveMujica\';
    const assetsPrefix = r'assets\';

    if (path.startsWith(gptPrefix)) {
      return [_join(_legacyGptSovitsRoot, path.substring(gptPrefix.length))];
    }
    if (path.startsWith(audioPrefix)) {
      return [
        _join(_legacyReferenceAudioRoot, path.substring(audioPrefix.length))
      ];
    }
    if (path.startsWith(avePrefix)) {
      return [_join(_legacyAveMujicaRoot, path.substring(avePrefix.length))];
    }
    if (path.startsWith(assetsPrefix)) {
      return [_join(_legacyAppAssetRoot, path.substring(assetsPrefix.length))];
    }
    return const [];
  }

  static String _join(String left, String right) {
    if (left.endsWith(r'\') || left.endsWith('/')) return '$left$right';
    return '$left\\$right';
  }

  static String _parentOf(String path) => File(path).parent.path;
}
