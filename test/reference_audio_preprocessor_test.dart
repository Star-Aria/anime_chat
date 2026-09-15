import 'dart:io';

import 'package:anime_chat_app/reference_audio_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WAV reference audio is passed through without conversion', () async {
    var processCalled = false;
    final preprocessor = ReferenceAudioPreprocessor(
      ffmpegPath: r'C:\fake\ffmpeg.exe',
      processRunner: (
        executable,
        arguments, {
        workingDirectory,
        runInShell = false,
      }) async {
        processCalled = true;
        return ProcessResult(1, 0, '', '');
      },
    );

    const source = r'C:\reference_audio\neutral.wav';
    expect(await preprocessor.prepareForTts(source), source);
    expect(processCalled, isFalse);
  });

  test('MP3 is converted once to WebUI-compatible PCM WAV and cached',
      () async {
    final root = await Directory.systemTemp.createTemp('reference_audio_test_');
    addTearDown(() => root.delete(recursive: true));

    final source = File('${root.path}${Platform.pathSeparator}neutral.mp3');
    await source.writeAsBytes(List<int>.filled(128, 1));
    final ffmpeg = File('${root.path}${Platform.pathSeparator}ffmpeg.exe');
    await ffmpeg.writeAsBytes(const [1]);

    var processCalls = 0;
    List<String>? capturedArguments;
    final preprocessor = ReferenceAudioPreprocessor(
      ffmpegPath: ffmpeg.path,
      cacheDirectory: Directory('${root.path}${Platform.pathSeparator}cache'),
      processRunner: (
        executable,
        arguments, {
        workingDirectory,
        runInShell = false,
      }) async {
        processCalls++;
        capturedArguments = List<String>.from(arguments);
        await File(arguments.last).writeAsBytes(List<int>.filled(64, 0));
        return ProcessResult(1, 0, '', '');
      },
    );

    final first = await preprocessor.prepareForTts(source.path);
    final second = await preprocessor.prepareForTts(source.path);

    expect(first, endsWith('.wav'));
    expect(second, first);
    expect(await File(first).exists(), isTrue);
    expect(processCalls, 1);
    expect(
      capturedArguments,
      containsAllInOrder([
        '-i',
        source.path,
        '-vn',
        '-ar',
        '44100',
        '-ac',
        '2',
        '-c:a',
        'pcm_s16le',
      ]),
    );
  });
}
