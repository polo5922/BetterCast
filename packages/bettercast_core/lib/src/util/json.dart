import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef Json = Map<String, dynamic>;

/// Stable identifier derived from arbitrary strings (feed URL, guid...).
///
/// Client and server compute the same ids without a round-trip.
String stableId(List<String> parts) =>
    sha1.convert(utf8.encode(parts.join('\u0000'))).toString().substring(0, 24);

DateTime? parseDate(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

String? dateToJson(DateTime? d) => d?.toUtc().toIso8601String();

List<T> parseList<T>(Object? v, T Function(Json) f) =>
    v is List ? v.whereType<Map>().map((e) => f(e.cast<String, dynamic>())).toList() : <T>[];
