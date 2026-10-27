import 'dart:io';

/// 查找本机整合包，不依赖固定盘符，也不递归扫描整块硬盘。
class GptSovitsPaths {
  GptSovitsPaths({
    String? appDirectory,
    String? workingDirectory,
    Map<String, String>? environment,
    List<String>? driveRoots,
  })  : _appDirectory =
            appDirectory ?? File(Platform.resolvedExecutable).parent.path,
        _workingDirectory = workingDirectory ?? Directory.current.path,
        _environment = environment ?? Platform.environment,
        _driveRoots = driveRoots ??
            (Platform.isWindows
                ? List.generate(
                    26, (index) => '${String.fromCharCode(65 + index)}:\\')
                : const <String>[]);

  final String _appDirectory;
  final String _workingDirectory;
  final Map<String, String> _environment;
  final List<String> _driveRoots;
  String? _cachedRoot;

  static const pathFileName = 'gpt_sovits_path.txt';

  String get root {
    final cached = _cachedRoot;
    if (cached != null && _isInstallation(cached)) return cached;
    final found = locate();
    _cachedRoot = found;
    // 未找到时返回可读的预期位置，由启动层报告错误，不影响其他功能。
    return found ?? _join(_appDirectory, 'GPT-SoVITS');
  }

  String? locate() {
    final override = _environment['GPT_SOVITS_ROOT']?.trim();
    if (override != null && override.isNotEmpty) {
      final candidate = _relativeTo(_appDirectory, _unquote(override));
      if (_isInstallation(candidate)) return candidate;
    }

    final bases = <String>{
      ..._ancestors(_appDirectory),
      ..._ancestors(_workingDirectory),
    };

    // 路径文件中的相对路径，以文件自身的位置为基准，不受启动目录影响。
    for (final base in bases) {
      final config = File(_join(base, pathFileName));
      try {
        if (!config.existsSync()) continue;
        final value = _unquote(config.readAsStringSync().trim());
        if (value.isEmpty) continue;
        final candidate = _relativeTo(base, value);
        if (_isInstallation(candidate)) return candidate;
      } on FileSystemException {
        // 无权限的目录或失效的旧配置不阻断后续自动查找。
      }
    }

    for (final base in {...bases, ..._driveRoots}) {
      if (_isInstallation(base)) return base;
      final conventional = _join(base, 'GPT-SoVITS');
      if (_isInstallation(conventional)) return conventional;

      // 只检查这一层的 GPT-SoVITS* 文件夹；支持不同版本的整合包名称。
      try {
        final names = Directory(base)
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where((entry) =>
                RegExp(r'^GPT-SoVITS(?:-|$)', caseSensitive: false).hasMatch(
                    entry.uri.pathSegments.where((s) => s.isNotEmpty).last))
            .map((entry) => entry.path)
            .toList()
          ..sort();
        for (final candidate in names) {
          if (_isInstallation(candidate)) return candidate;
        }
      } on FileSystemException {
        // 未就绪的盘符和无权限目录直接跳过。
      }
    }
    return null;
  }

  /// 引擎会把 API 收到的模型路径写回 YAML；内部模型必须传相对路径，
  /// 否则下一次移动整合包后，YAML 又会留下失效的绝对路径。
  String modelPathForApi(String absolutePath) {
    final normalized = absolutePath.replaceAll('\\', '/');
    final prefix =
        '${root.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '')}/';
    if (normalized.toLowerCase().startsWith(prefix.toLowerCase())) {
      return normalized.substring(prefix.length);
    }
    // 用户指定在整合包之外的模型时，仍保留其原始路径。
    return absolutePath;
  }

  static bool _isInstallation(String root) =>
      File(_join(root, 'api_v2.py')).existsSync() &&
      File(_join(root, 'runtime/python.exe')).existsSync() &&
      File(_join(root, 'GPT_SoVITS/configs/tts_infer.yaml')).existsSync();

  static Iterable<String> _ancestors(String path) sync* {
    var directory = Directory(path).absolute;
    while (directory.parent.path != directory.path) {
      yield directory.path;
      directory = directory.parent;
    }
  }

  static String _unquote(String value) => value
      .replaceFirst(RegExp(r'^\uFEFF'), '')
      .replaceAll(RegExp(r'^"|"$'), '');

  static String _relativeTo(String base, String path) {
    final normalized =
        path.replaceAll(RegExp(r'[\\/]'), Platform.pathSeparator);
    final absolute =
        File(normalized).isAbsolute ? normalized : _join(base, normalized);
    return File(absolute).absolute.uri.normalizePath().toFilePath();
  }

  static String _join(String left, String right) {
    final separator = Platform.pathSeparator;
    final base = left.endsWith(separator) ? left : '$left$separator';
    return '$base${right.replaceAll(RegExp(r'[\\/]'), separator)}';
  }
}
