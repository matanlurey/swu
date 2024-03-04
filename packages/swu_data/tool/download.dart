#!/usr/bin/env dart

import 'dart:collection';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:jsonut/jsonut.dart';
import 'package:path/path.dart' as path;

import 'src/data.dart';

/// Given the images in `cards.json`, downloads them into `lib/assets/cards/`.
Future<void> main(List<String> args) async {
  // Find where this script is running from, and use the parent as the root.
  final root = path.relative(
    path.dirname(
      path.dirname(
        path.fromUri(io.Platform.script),
      ),
    ),
  );

  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Print usage information.',
      negatable: false,
    )
    ..addOption(
      'input',
      abbr: 'i',
      help: 'The input file to read from.',
      defaultsTo: path.join(root, 'tool', 'cards.json'),
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'The output directory to write to.',
      defaultsTo: path.join(root, 'lib', 'assets', 'cards'),
    )
    ..addOption(
      'concurrency',
      abbr: 'j',
      help: 'The number of concurrent downloads to allow.',
      defaultsTo: '16',
    );

  final results = parser.parse(args);
  if (results['help'] as bool) {
    io.stdout.writeln(parser.usage);
    return;
  }

  final input = results['input'] as String;
  final output = results['output'] as String;

  // Recreate directory.
  if (io.Directory(output).existsSync()) {
    io.Directory(output).deleteSync(recursive: true);
  }
  io.Directory(output).createSync(recursive: true);

  final cards = JsonArray.parse(io.File(input).readAsStringSync())
      .cast<JsonObject>()
      .map(Card.fromJson)
      .toList();

  final downloads = Queue<(Uri, String)>();
  void queue(Uri url, String filePath) {
    downloads.add((url, filePath));
  }

  for (final card in cards) {
    final name = '${card.set}-${card.number.toString().padLeft(3, '0')}';
    for (final art in card.art) {
      if (art.back case final CardArtDetails details) {
        queue(
          details.url,
          path.join(
            output,
            'back',
            art.style.name,
            '$name.png',
          ),
        );
      }
      if (art.front case final CardArtDetails details) {
        queue(
          details.url,
          path.join(
            output,
            'front',
            art.style.name,
            '$name.png',
          ),
        );
      }
      if (art.thumbnail case final CardArtDetails details) {
        queue(
          details.url,
          path.join(
            output,
            'thumb',
            art.style.name,
            '$name.png',
          ),
        );
      }
    }
  }

  // While there are still downloads to process, process them.
  // Download up to `concurrency` images at a time.
  final client = http.Client();
  final concurrency = int.parse(results['concurrency'] as String);
  final futures = <Future<void>>[];

  Future<void> onFetched(
    Uri url,
    String filePath,
    http.Response response,
  ) async {
    io.stderr.writeln(
      'Downloading... [${downloads.length} remaining]',
    );
    await Future(() {});

    // Assume it never fails.
    final file = io.File(filePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsBytesSync(response.bodyBytes);

    // If there are more downloads to process, process them.
    if (downloads.isNotEmpty) {
      final next = downloads.removeFirst();
      futures.add(
        client.get(next.$1).then((response) {
          onFetched(next.$1, next.$2, response);
        }),
      );
    } else {
      // If there are no more downloads to process, wait for all current
      // downloads to finish.
      await Future.wait(futures);
      client.close();
    }
  }

  // Download the first `concurrency` images.
  for (var i = 0; i < concurrency && downloads.isNotEmpty; i++) {
    final next = downloads.removeFirst();
    futures.add(
      client.get(next.$1).then((response) {
        onFetched(next.$1, next.$2, response);
      }),
    );
  }
}
