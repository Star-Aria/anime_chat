import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'path_service.dart';

typedef ReferenceAudioProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

/// 让程序使用与 GPT-SoVITS WebUI 相同的参考音频输入格式。
///
/// WebUI 会先把上传的 MP3 解码为 44.1 kHz、16-bit、双声道 PCM WAV；
/// 直接把 MP3 路径交给推理器时，部分模型会因解码细微差异产生明显的发音偏差。
class ReferenceAudioPreprocessor {
  ReferenceAudioPreprocessor({
    String? ffmpegPath,
    Directory? cacheDirectory,
    ReferenceAudioProcessRunner? processRunner,
  })  : _ffmpegPath = ffmpegPath ?? AppPaths.gptSovitsFfmpeg,
        _cacheDirectory = cacheDirectory ??
            Directory(
              '${Directory.systemTemp.path}'
              '${Platform.pathSeparator}anime_chat_app_reference_audio',
            ),
        _processRunner = processRunner ?? _runProcess;

  static final ReferenceAudioPreprocessor shared = ReferenceAudioPreprocessor();

  final String _ffmpegPath;
  final Directory _cacheDirectory;
  final ReferenceAudioProcessRunner _processRunner;
  final Map<String, Future<String>> _pendingConversions = {};

  Future<String> prepareForTts(String sourcePath) async {
    if (!_isMp3(sourcePath)) return sourcePath;

    final source = File(sourcePath);
    if (!await source.exists()) return sourcePath;
    if (!await File(_ffmpegPath).exists()) {
      debugPrint('参考音频预处理跳过：未找到 FFmpeg $_ffmpegPath');
      return sourcePath;
    }

    final stat = await source.stat();
    final cachePath = _buildCachePath(source, stat);
    final cached = File(cachePath);
    if (await _isUsableWav(cached)) return cachePath;

    final activeTask = _pendingConversions[cachePath];
    if (activeTask != null) return activeTask;

    final task = _convertToWebUiWav(source, cached);
    _pendingConversions[cachePath] = task;
    try {
      return await task;
    } finally {
      if (identical(_pendingConversions[cachePath], task)) {
        _pendingConversions.remove(cachePath);
      }
    }
  }

  Future<String> _convertToWebUiWav(File source, File output) async {
    await _cacheDirectory.create(recursive: true);

    final partial = File(
      '${output.path}.${pid}_${DateTime.now().microsecondsSinceEpoch}.tmp.wav',
    );

    try {
      final result = await _processRunner(
        _ffmpegPath,
        [
          '-hide_banner',
          '-loglevel',
          'error',
          '-y',
          '-i',
          source.path,
          '-vn',
          '-ar',
          '44100',
          '-ac',
          '2',
          '-c:a',
          'pcm_s16le',
          partial.path,
        ],
        workingDirectory: AppPaths.gptSovitsRoot,
        runInShell: false,
      );

      if (result.exitCode != 0 || !await _isUsableWav(partial)) {
        final error = result.stderr.toString().trim();
        debugPrint(
          '参考音频转为 PCM WAV 失败（exitCode=${result.exitCode}）'
          '${error.isEmpty ? '' : '：$error'}',
        );
        return source.path;
      }

      if (await output.exists()) await output.delete();
      await partial.rename(output.path);
      debugPrint('参考音频已转换为 WebUI PCM WAV：${source.path} -> ${output.path}');
      return output.path;
    } catch (e) {
      debugPrint('参考音频转为 PCM WAV 失败：$e');
      return source.path;
    } finally {
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  String _buildCachePath(File source, FileStat stat) {
    final filename = source.uri.pathSegments.isEmpty
        ? 'reference_audio'
        : source.uri.pathSegments.last;
    var stem = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
    stem = stem.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (stem.length > 48) stem = stem.substring(0, 48);

    final normalizedPath = source.absolute.path.toLowerCase();
    final pathHash = _fnv1a32(normalizedPath).toRadixString(16).padLeft(8, '0');
    final version = '${stat.modified.millisecondsSinceEpoch}_${stat.size}';
    return '${_cacheDirectory.path}${Platform.pathSeparator}'
        '${stem}_${pathHash}_$version.wav';
  }

  static bool _isMp3(String path) => path.toLowerCase().endsWith('.mp3');

  static Future<bool> _isUsableWav(File file) async {
    if (!await file.exists()) return false;
    return await file.length() > 44;
  }

  static int _fnv1a32(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }
}
