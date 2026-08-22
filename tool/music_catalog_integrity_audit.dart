import 'dart:convert';
import 'dart:io';

void main() {
  final catalogFile = File('music/music_catalog.json');
  if (!catalogFile.existsSync()) {
    stderr.writeln('ERROR catalog is missing: ${catalogFile.path}');
    exitCode = 1;
    return;
  }

  final decoded = jsonDecode(catalogFile.readAsStringSync());
  if (decoded is! List) {
    stderr.writeln('ERROR catalog root must be a JSON array');
    exitCode = 1;
    return;
  }

  final entries = decoded.whereType<Map<String, dynamic>>().toList();
  final errors = <String>[];
  final notices = <String>[];
  final ids = <String>{};
  final titles = <String>{};
  final referencedAudio = <String>{};
  final emptyAudioDirectories = <String>{};

  for (final entry in entries) {
    final id = '${entry['id'] ?? ''}'.trim();
    final title = '${entry['title'] ?? ''}'.trim();
    final band = '${entry['band'] ?? ''}'.trim();
    final lyricsPath = '${entry['lyricsPath'] ?? ''}'.trim();
    final audioPath = '${entry['localAudioPath'] ?? ''}'.trim();

    if (id.isEmpty || !ids.add(id)) {
      errors.add('invalid or duplicate id: $id');
    }
    if (title.isEmpty || !titles.add(title)) {
      errors.add('invalid or duplicate title: $title');
    }

    if (lyricsPath.isEmpty) {
      errors.add('$title has no lyricsPath');
    } else {
      final lyricsFile = File(lyricsPath);
      if (!lyricsFile.existsSync()) {
        errors.add('$title lyrics file is missing: $lyricsPath');
      } else {
        final lyrics = lyricsFile.readAsStringSync().trim();
        if (band == 'Ave Mujica' && lyrics.isEmpty) {
          errors.add('$title Ave Mujica lyrics file is empty: $lyricsPath');
        }
        if (band == 'Ave Mujica' &&
            lyrics.isNotEmpty &&
            (!lyrics.contains('【日文原词】') || !lyrics.contains('【中文翻译】'))) {
          errors.add('$title lyrics file is missing bilingual headings');
        }
      }
    }

    if (band == 'Ave Mujica' &&
        '${entry['description'] ?? ''}'.trim().isEmpty) {
      errors.add('$title Ave Mujica description is empty');
    }

    if (audioPath.isEmpty) continue;
    final absoluteAudioPath = File(audioPath).absolute.path;
    referencedAudio.add(_pathKey(absoluteAudioPath));

    final audioFile = File(audioPath);
    final parent = audioFile.parent;
    if (!parent.existsSync()) {
      notices.add('$title audio directory is not present yet: ${parent.path}');
      continue;
    }

    final actualNames = parent
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp3'))
        .map((file) => file.uri.pathSegments.last)
        .toSet();
    if (actualNames.isEmpty) {
      emptyAudioDirectories.add(parent.path);
      continue;
    }
    final configuredName = audioFile.uri.pathSegments.last;
    if (!actualNames.contains(configuredName)) {
      errors.add('$title audio filename does not match disk: $audioPath');
    }
  }

  final musicDirectory = Directory('music');
  if (musicDirectory.existsSync()) {
    for (final file
        in musicDirectory.listSync(recursive: true).whereType<File>()) {
      if (!file.path.toLowerCase().endsWith('.mp3')) continue;
      if (!referencedAudio.contains(_pathKey(file.absolute.path))) {
        errors.add('unreferenced audio file: ${file.path}');
      }
    }
  }

  stdout.writeln(
    'Catalog entries: ${entries.length}; errors: ${errors.length}; '
    'notices: ${notices.length + emptyAudioDirectories.length}',
  );
  for (final directory in emptyAudioDirectories) {
    stdout.writeln('NOTICE audio directory has no MP3 files yet: $directory');
  }
  for (final notice in notices.toSet()) {
    stdout.writeln('NOTICE $notice');
  }
  for (final error in errors) {
    stderr.writeln('ERROR $error');
  }

  if (errors.isNotEmpty) exitCode = 1;
}

String _pathKey(String path) =>
    Platform.isWindows ? path.replaceAll('/', r'\').toLowerCase() : path;
