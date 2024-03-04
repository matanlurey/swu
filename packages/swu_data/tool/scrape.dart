#!/usr/bin/env dart

import 'dart:convert' as convert;
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:jsonut/jsonut.dart';
import 'package:path/path.dart' as path;

import 'src/data.dart';

/// Scrapes <https://starwarsunlimited.com/cards>'s unofficial API for cards.
///
/// Star Wars Unlimited does not have an official API, so this script scrapes
/// the internal API used by the website to get the card data, and performs
/// some normalization on the data to make it easier to use.
///
/// The resulting data is written to `tool/cards.json` for further processing.
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
      negatable: false,
      help: 'Prints usage information.',
    )
    ..addFlag(
      'cache',
      abbr: 'c',
      // Enable automatically if the working directory is the root.
      defaultsTo: path.canonicalize('.') == path.canonicalize(root),
      help: 'Store and use cached responses for faster development.',
    )
    ..addOption(
      'endpoint',
      abbr: 'e',
      help: 'The URL to make GET requests to for the card data.',
      defaultsTo: 'https://admin.starwarsunlimited.com/api/cards',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'The .json file to write the card data to.',
      defaultsTo: path.join(root, 'tool', 'cards.json'),
    );

  // Before parsing, check if the user just wants help.
  if (args.any((arg) => arg == '--help' || arg == '-h')) {
    io.stdout.writeln(parser.usage);
    return;
  }

  final results = parser.parse(args);

  // Get the endpoint and validate it's a URL.
  final Uri endpoint;
  try {
    endpoint = Uri.parse(results['endpoint'] as String);
  } on FormatException catch (e) {
    io.stderr.writeln('Invalid endpoint URL: ${e.source}');
    return;
  }

  // Check if we're using the cache (in .dart_tool/swu_data).
  final client = results['cache'] == true
      ? _CachedHttpClient(
          http.Client(),
          path.join(root, '.dart_tool', 'swu_data'),
        )
      : http.Client();

  try {
    io.stderr.writeln('Fetching cards from $endpoint');
    final cards = <Card>[];

    await for (final card in _fetchRawCards(client, endpoint)) {
      final attributes = card['attributes'].object();

      // If it's a variant, skip it.
      final variantOf = attributes['variantOf'].object()['data'];
      if (!variantOf.isNull) {
        continue;
      }

      final data = attributes['expansion'].object()['data'];
      if (data.isNull) {
        continue;
      }
      final set = data.object()['attributes'].object()['code'].string();
      final title = attributes['title'].string();
      final number = attributes['cardNumber'].number();
      final count = attributes['cardCount'].number();
      io.stderr.writeln(
        '$set #${'$number'.padLeft('$count'.length, '0')}/$count: $title',
      );

      CardArtDetails? parseArtDetails(JsonObject json) {
        final data = json['data'];
        if (data.isNull) {
          return null;
        }
        final formats =
            data.object()['attributes'].object()['formats'].object();
        final JsonObject fields;
        if (formats.containsKey('card')) {
          fields = formats['card'].object();
        } else if (formats.containsKey('xxsmall')) {
          fields = formats['xxsmall'].object();
        } else {
          throw ArgumentError('Unknown art format: ${formats.keys.toList()}');
        }

        return CardArtDetails(
          url: Uri.parse(fields['url'].string()),
          name: fields['name'].string(),
        );
      }

      CardArt parseArt(JsonObject json) {
        return CardArt(
          front: parseArtDetails(json['artFront'].object())!,
          back: parseArtDetails(json['artBack'].object()),
          style: json['showcase'].boolean()
              ? CardStyle.showcase
              : json['hyperspace'].boolean()
                  ? CardStyle.hyperspace
                  : CardStyle.standard,
          thumbnail: parseArtDetails(json['artThumbnail'].object())!,
        );
      }

      final type = attributes['type']
          .object()['data']
          .object()['attributes']
          .object()['value']
          .string()
          .toLowerCase();

      final aspects = <Aspect>[];
      for (final aspect in [
        ...attributes['aspects'].object()['data'].array(),
        ...attributes['aspectDuplicates'].object()['data'].array(),
      ]) {
        aspects.add(
          Aspect.fromName(
            aspect
                .object()['attributes']
                .object()['name']
                .string()
                .toLowerCase(),
          ),
        );
      }

      final traits = <String>[];
      for (final trait in attributes['traits'].object()['data'].array()) {
        traits.add(
          trait.object()['attributes'].object()['name'].string().toLowerCase(),
        );
      }

      Arena? arena;
      {
        final data = attributes['arenas'].object()['data'].array();
        for (final item in data) {
          final attributes = item.object()['attributes'].object();
          final name = attributes['name'].string();
          arena = Arena.fromName(name.toLowerCase());
          break;
        }
      }

      final Rarity rarity;
      {
        final data = attributes['rarity']
            .object()['data']
            .object()['attributes']
            .object();
        final name = data['name'].string();
        rarity = Rarity.fromName(name.toLowerCase());
      }

      cards.add(
        Card(
          set: set.toLowerCase(),
          number: number.toInt(),
          type: CardType.fromName(type),
          rarity: rarity,
          title: title,
          subTitle: attributes['subtitle'].stringOrNull(),
          artist: attributes['artist'].string(),
          cost: attributes['cost'].numberOrNull()?.toInt(),
          hp: attributes['hp'].numberOrNull()?.toInt(),
          power: attributes['power'].numberOrNull()?.toInt(),
          aspects: aspects,
          traits: traits,
          arena: arena,
          unique: attributes['unique'].boolean(),
          horizontal: attributes['artFrontHorizontal'].boolean(),
          art: [
            parseArt(attributes),
            // And for each variant...
            for (final variant
                in attributes['variants'].object()['data'].array())
              parseArt(variant.object()['attributes'].object()),
          ],
        ),
      );
    }

    // Write the cards to the output file.
    final output = results['output'] as String;
    final file = io.File(output);
    await file.writeAsString(
      const convert.JsonEncoder.withIndent('  ').convert(
        cards.map((card) => card.toJson()).toList(),
      ),
    );
  } finally {
    client.close();
  }
}

/// Given a directory, stores and returns `GET` JSON responses.
///
/// For example, if the directory is `cache`, and the URL is
/// `https://example.com/api`, the response will be stored in
/// `cache/https/example.com/api.json`.
///
/// For requests with query parameters, the query parameters are included in
/// the file name. For example, if the URL ends with `?a=1&b=2`, the response
/// will be stored in `cache/https/example.com/api?a=1&b=2.json`.
///
/// If the response is already cached, the cached response is returned.
///
/// If the response is not cached, the response is fetched and stored.
final class _CachedHttpClient extends http.BaseClient {
  _CachedHttpClient(this._base, this._cacheDir);

  final http.Client _base;
  final String _cacheDir;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // If it's not a GET request, just pass it through.
    if (request.method != 'GET') {
      return _base.send(request);
    }

    final url = request.url;
    final cachePath = path.joinAll([
      'cache',
      url.scheme,
      url.host,
      ...url.pathSegments,
      if (url.query.isNotEmpty) '?${url.query}',
    ]);

    final file = io.File(path.join(_cacheDir, '$cachePath.json'));
    if (!file.existsSync()) {
      final response = await _base.send(request);
      // If the request was not successful, throw an error.
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Failed to fetch $url: ${response.reasonPhrase}',
          request.url,
        );
      }

      await file.create(recursive: true);

      // Write with pretty JSON formatting.
      final json = await response.stream.bytesToString();
      await file.writeAsString(
        const convert.JsonEncoder.withIndent('  ').convert(
          convert.json.decode(json),
        ),
      );
    }

    return http.StreamedResponse(
      file.openRead(),
      200,
      contentLength: await file.length(),
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

/// Fetches the cards from the given [endpoint].
///
/// This function is a generator that yields each card.
Stream<JsonObject> _fetchRawCards(
  http.Client client,
  Uri endpoint, {
  int fetchPerPage = 50,
}) async* {
  // Always start at page 1.
  var page = 1;

  // Add the default query parameters to the endpoint.
  endpoint = endpoint.replace(
    queryParameters: {
      'locale': 'en',
      'sort[0]': 'type.sortValue:asc,cardNumber:asc',
      'pagination[pageSize]': '$fetchPerPage',
    },
  );

  while (true) {
    final url = endpoint.replace(
      queryParameters: {
        ...endpoint.queryParameters,
        'pagination[page]': '$page',
      },
    );
    final response = await client.get(url);

    // Decode the JSON response.
    final json = JsonObject.parse(response.body);
    final meta = json['meta'].object();
    final count = meta['pagination'].object()['pageCount'].number().toInt();
    final cards = json['data'].array();
    io.stderr.writeln(
      'Fetched page $page of $count: got ${cards.length} cards',
    );

    // Yield each card.
    for (final card in cards) {
      yield card.object();
    }

    // If there are no more pages, stop.
    if (page >= count) {
      break;
    }

    // Otherwise, request the next page.
    page++;
  }
}
