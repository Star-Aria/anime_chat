import 'dart:convert';
import 'dart:io';

import 'package:anime_chat_app/gpt_sovits_paths.dart';
import 'package:flutter_test/flutter_test.dart';

String join(String base, String path) => '$base${Platform.pathSeparator}'
    '${path.replaceAll('/', Platform.pathSeparator)}';

Directory installation(String path) {
  final directory = Directory(path)..createSync(recursive: true);
  for (final name in [
    'api_v2.py',
    'runtime/python.exe',
    'GPT_SoVITS/configs/tts_infer.yaml',
  ]) {
    final file = File(join(path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('');
  }
  return directory;
}

void main() {
  late Directory sandbox;
  late String app;
  late String cwd;
  late String driveA;
  late String driveB;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('gpt_sovits_paths_');
    app = join(sandbox.path, 'bundle/app');
    cwd = join(sandbox.path, 'unrelated');
    driveA = join(sandbox.path, 'drive_a');
    driveB = join(sandbox.path, 'drive_b');
    for (final path in [app, cwd, driveA, driveB]) {
      Directory(path).createSync(recursive: true);
    }
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  GptSovitsPaths locator({Map<String, String> environment = const {}}) =>
      GptSovitsPaths(
        appDirectory: app,
        workingDirectory: cwd,
        environment: environment,
        driveRoots: [driveA, driveB],
      );

  test('valid environment override takes priority over local installations',
      () {
    installation(join(app, 'GPT-SoVITS'));
    final custom = installation(join(sandbox.path, 'custom engine'));
    expect(
      locator(environment: {'GPT_SOVITS_ROOT': custom.path}).root,
      custom.path,
    );
  });

  test('relative UTF-8 path file is based on its own directory, not cwd', () {
    final engine = installation(join(sandbox.path, 'bundle/语音引擎 空格'));
    File(join(app, GptSovitsPaths.pathFileName))
        .writeAsStringSync('\uFEFF"../语音引擎 空格"\n');
    expect(locator().root, engine.path);
  });

  test('executable-relative installation wins over an unrelated working dir',
      () {
    final nearby = installation(join(app, 'GPT-SoVITS'));
    installation(join(cwd, 'GPT-SoVITS'));
    expect(locator().root, nearby.path);
  });

  test('versioned bundle is found alongside a project ancestor', () {
    final engine = installation(
      join(sandbox.path, 'bundle/GPT-SoVITS-v2pro-20250604-nvidia50'),
    );
    app = join(app, 'build/windows/x64/runner/Release');
    Directory(app).createSync(recursive: true);
    expect(locator().root, engine.path);
  });

  test('stale overrides and incomplete bundles fall back to a drive root', () {
    File(join(app, GptSovitsPaths.pathFileName)).writeAsStringSync('missing');
    Directory(join(driveA, 'GPT-SoVITS-broken')).createSync();
    final engine = installation(join(driveB, 'GPT-SoVITS-new-version'));
    expect(
      locator(environment: {'GPT_SOVITS_ROOT': 'missing'}).root,
      engine.path,
    );
  });

  test('cached discovery recovers when the engine changes drives', () {
    final original = installation(join(driveA, 'GPT-SoVITS-portable'));
    final paths = locator();
    expect(paths.root, original.path);
    final moved = original.renameSync(join(driveB, 'GPT-SoVITS-portable'));
    expect(paths.root, moved.path);
  });

  test('moving the complete bundle preserves relative discovery', () {
    installation(join(sandbox.path, 'bundle/GPT-SoVITS'));
    expect(locator().root, join(sandbox.path, 'bundle/GPT-SoVITS'));
    final moved = Directory(join(sandbox.path, 'bundle'))
        .renameSync(join(sandbox.path, 'moved bundle'));
    app = join(moved.path, 'app');
    expect(locator().root, join(moved.path, 'GPT-SoVITS'));
  });

  test('API model paths stay portable; external paths are preserved', () {
    final engine = installation(join(app, 'GPT-SoVITS'));
    final paths = locator();
    expect(
      paths
          .modelPathForApi(join(engine.path, 'GPT_weights_v2ProPlus/高松灯.ckpt')),
      'GPT_weights_v2ProPlus/高松灯.ckpt',
    );
    final external = join(sandbox.path, 'external/voice.ckpt');
    expect(paths.modelPathForApi(external), external);
    final samePrefix = '${engine.path}-other/voice.ckpt';
    expect(paths.modelPathForApi(samePrefix), samePrefix);
  });

  test('no installation produces a safe, predictable startup error path', () {
    final paths = locator();
    expect(paths.locate(), isNull);
    expect(paths.root, join(app, 'GPT-SoVITS'));
  });

  test('Windows launcher uses the same relative path file as the app',
      () async {
    final engine = installation(join(sandbox.path, 'bundle/语音引擎 空格'));
    File(join(app, GptSovitsPaths.pathFileName))
        .writeAsStringSync('\uFEFF"../语音引擎 空格"\n');
    final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          join(Directory.current.path, 'scripts/start_gpt_sovits.ps1'),
          '-ResolveOnly',
          '-AppDirectory',
          app,
          '-WorkingDirectory',
          cwd,
          '-DriveRoots',
          driveA,
          '-RootOverride',
          'missing',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString().trim(), engine.path);
    expect(locator().root, engine.path);
  }, skip: !Platform.isWindows);
}
