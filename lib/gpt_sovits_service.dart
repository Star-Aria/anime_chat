import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'path_service.dart';

/// 管理本机 GPT-SoVITS api_v2 服务。
///
/// 只在 9880 端口没有服务时启动 GPT-SoVITS；如果用户已经手动启动，
/// 则直接复用现有服务，不会再开第二个实例。
class GptSovitsService {
  static const String _host = '127.0.0.1';
  static const int _port = 9880;
  static const Duration _probeTimeout = Duration(milliseconds: 600);
  static const Duration _startupTimeout = Duration(seconds: 45);

  static Future<bool>? _startupTask;
  static int _serviceGeneration = 0;

  /// 每次检测到服务需要重新启动都会递增。
  /// API 进程重启后，即使端口恢复，之前加载的模型也不能继续视为有效。
  static int get serviceGeneration => _serviceGeneration;

  static Future<bool> ensureRunning() {
    // 只合并同时发生的启动检查；本次检查结束后必须清空缓存，
    // 这样服务在程序运行中被关闭时，下一次请求仍会重新检测并拉起。
    final activeTask = _startupTask;
    if (activeTask != null) return activeTask;

    final task = _ensureRunning();
    _startupTask = task;
    task.whenComplete(() {
      if (identical(_startupTask, task)) {
        _startupTask = null;
      }
    });
    return task;
  }

  static Future<bool> _ensureRunning() async {
    if (!Platform.isWindows) {
      debugPrint('GPT-SoVITS 自动启动仅在 Windows 下启用');
      return false;
    }

    if (await _isPortOpen()) {
      return true;
    }

    _serviceGeneration++;

    final root = AppPaths.gptSovitsRoot;
    final python = AppPaths.gptSovitsPython;
    final config = r'GPT_SoVITS/configs/tts_infer.yaml';

    if (!Directory(root).existsSync() ||
        !File(python).existsSync() ||
        !File('$root/api_v2.py').existsSync() ||
        !File('$root/$config').existsSync()) {
      debugPrint('GPT-SoVITS 自动启动跳过：未找到完整安装目录 $root。'
          '可在程序或项目目录创建 gpt_sovits_path.txt 指定位置，'
          '或设置 GPT_SOVITS_ROOT 环境变量。');
      return false;
    }

    try {
      // detached 让服务独立于 Flutter 进程运行，且不会弹出额外的控制台窗口。
      final process = await Process.start(
        python,
        ['api_v2.py', '-c', config],
        workingDirectory: root,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      debugPrint('已自动启动 GPT-SoVITS API（PID ${process.pid}），等待端口 $_port');

      final deadline = DateTime.now().add(_startupTimeout);
      while (DateTime.now().isBefore(deadline)) {
        if (await _isPortOpen()) {
          debugPrint('GPT-SoVITS API 已就绪：$_host:$_port');
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      debugPrint(
          'GPT-SoVITS API 启动超时（${_startupTimeout.inSeconds} 秒），程序仍会继续启动');
    } catch (e) {
      debugPrint('GPT-SoVITS 自动启动失败：$e');
    }
    return false;
  }

  static Future<bool> _isPortOpen() async {
    Socket? socket;
    try {
      socket = await Socket.connect(_host, _port, timeout: _probeTimeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
