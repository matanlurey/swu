/// Raw data from SWU massaged into a more convenient (er, not-chaotic) format.
library;

import 'package:jsonut/jsonut.dart';
import 'package:meta/meta.dart';

@immutable
final class Card {
  const Card({
    required this.set,
    required this.number,
    required this.rarity,
    required this.title,
    required this.subTitle,
    required this.artist,
    required this.cost,
    required this.hp,
    required this.power,
    required this.aspects,
    required this.traits,
    required this.unique,
    required this.horizontal,
    required this.art,
    required this.type,
    required this.arena,
  });

  factory Card.fromJson(JsonObject json) {
    return Card(
      set: json['set'].string(),
      number: json['number'].number().toInt(),
      rarity: Rarity.fromName(json['rarity'].string()),
      title: json['title'].string(),
      subTitle: json['sub_title'].stringOrNull(),
      artist: json['artist'].string(),
      cost: json['cost'].numberOrNull()?.toInt(),
      hp: json['hp'].numberOrNull()?.toInt(),
      power: json['power'].numberOrNull()?.toInt(),
      unique: json['unique'].boolean(),
      aspects: json['aspects']
          .array()
          .map((json) => Aspect.fromName(json.string()))
          .toList(),
      traits: json['traits'].array().map((json) => json.string()).toList(),
      horizontal: json['horizontal'].boolean(),
      art: json['art']
          .array()
          .map((json) => CardArt.fromJson(json.object()))
          .toList(),
      type: CardType.fromName(json['type'].string()),
      arena:
          json['arena'].isNull ? null : Arena.fromName(json['arena'].string()),
    );
  }

  final String set;
  final int number;
  final Rarity rarity;
  final String title;
  final String? subTitle;
  final String artist;
  final int? cost;
  final int? hp;
  final int? power;
  final bool unique;
  final bool horizontal;
  final List<CardArt> art;
  final CardType type;
  final List<Aspect> aspects;
  final List<String> traits;
  final Arena? arena;

  JsonObject toJson() {
    return JsonObject({
      'set': JsonString(set),
      'number': JsonNumber(number),
      'rarity': JsonString(rarity.name),
      'type': JsonString(type.name),
      'title': JsonString(title),
      'sub_title': subTitle as JsonValue,
      'artist': JsonString(artist),
      'cost': cost as JsonValue,
      'hp': hp as JsonValue,
      'power': power as JsonValue,
      'unique': JsonBool(unique),
      if (arena != null) 'arena': JsonString(arena!.name),
      'aspects':
          JsonArray(aspects.map((aspect) => JsonString(aspect.name)).toList()),
      'traits': JsonArray(traits as List<JsonString>),
      'horizontal': JsonBool(horizontal),
      'art': JsonArray(art.map((art) => art.toJson()).toList()),
    });
  }
}

enum CardStyle {
  standard,
  hyperspace,
  showcase;

  factory CardStyle.fromName(String name) {
    return CardStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => throw StateError('Unknown card style: $name'),
    );
  }
}

@immutable
final class CardArt {
  const CardArt({
    required this.style,
    required this.front,
    required this.back,
    required this.thumbnail,
  });

  factory CardArt.fromJson(JsonObject json) {
    return CardArt(
      style: CardStyle.fromName(json['style'].string()),
      front: CardArtDetails.fromJson(json['front'].object()),
      back: json['back'].isNull
          ? null
          : CardArtDetails.fromJson(json['back'].object()),
      thumbnail: CardArtDetails.fromJson(json['thumbnail'].object()),
    );
  }

  final CardStyle style;
  final CardArtDetails front;
  final CardArtDetails? back;
  final CardArtDetails thumbnail;

  JsonObject toJson() {
    return JsonObject({
      'style': JsonString(style.name),
      'front': front.toJson(),
      if (back != null) 'back': back!.toJson(),
      'thumbnail': thumbnail.toJson(),
    });
  }
}

@immutable
final class CardArtPair {
  const CardArtPair({
    required this.full,
    required this.thumbnail,
  });

  factory CardArtPair.fromJson(JsonObject json) {
    return CardArtPair(
      full: CardArtDetails.fromJson(json['full'].object()),
      thumbnail: CardArtDetails.fromJson(json['thumbnail'].object()),
    );
  }

  final CardArtDetails full;
  final CardArtDetails thumbnail;

  JsonObject toJson() {
    return JsonObject({
      'full': full.toJson(),
      'thumbnail': thumbnail.toJson(),
    });
  }
}

@immutable
final class CardArtDetails {
  const CardArtDetails({
    required this.name,
    required this.url,
  });

  factory CardArtDetails.fromJson(JsonObject json) {
    return CardArtDetails(
      name: json['name'].string(),
      url: Uri.parse(json['url'].string()),
    );
  }

  final String name;
  final Uri url;

  JsonObject toJson() {
    return JsonObject({
      'name': JsonString(name),
      'url': JsonString(url.toString()),
    });
  }
}

enum CardType {
  base,
  event,
  leader,
  unit,
  upgrade;

  factory CardType.fromName(String name) {
    return CardType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => throw StateError('Unknown card type: $name'),
    );
  }
}

enum Aspect {
  aggression,
  command,
  cunning,
  heroism,
  villainy,
  vigilance;

  factory Aspect.fromName(String name) {
    return Aspect.values.firstWhere(
      (aspect) => aspect.name == name,
      orElse: () => throw StateError('Unknown aspect: $name'),
    );
  }
}

enum Arena {
  ground,
  space;

  factory Arena.fromName(String name) {
    return Arena.values.firstWhere(
      (arena) => arena.name == name,
      orElse: () => throw StateError('Unknown arena: $name'),
    );
  }
}

enum Rarity {
  common,
  uncommon,
  rare,
  legendary,
  special;

  factory Rarity.fromName(String name) {
    return Rarity.values.firstWhere(
      (rarity) => rarity.name == name,
      orElse: () => throw StateError('Unknown rarity: $name'),
    );
  }
}
