import 'dart:io';

import 'package:bettercast_core/bettercast_core.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  const parser = FeedParser();

  group('video feed', () {
    late ParsedFeed feed;
    setUp(() => feed = parser.parse(
          fixture('video_feed.xml'),
          feedUrl: 'https://example.com/feed.xml',
        ));

    test('channel metadata', () {
      final p = feed.podcast;
      expect(p.id, Podcast.idFor('https://example.com/feed.xml'));
      expect(p.title, 'Le Podcast Vidéo');
      expect(p.author, 'Jane Doe');
      expect(p.imageUrl, 'https://example.com/cover.jpg');
      expect(p.language, 'fr');
      expect(p.categories, ['Technology', 'Podcasting']);
      expect(p.podcastGuid, '917393e3-1b1e-5cef-ace4-edaa54e1f810');
      expect(p.explicit, isFalse);
      expect(p.episodeCount, 2);
    });

    test('skips items without media and duplicate guids, newest first', () {
      expect(feed.episodes.map((e) => e.guid), ['ep-2', 'ep-1']);
    });

    test('episode with audio enclosure and video alternateEnclosures', () {
      final ep = feed.episodes.first;
      expect(ep.title, 'Épisode 2 : la vidéo');
      expect(ep.description, '<p>Notes <b>complètes</b></p>');
      expect(ep.summary, 'Résumé court');
      expect(ep.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(ep.number, 2);
      expect(ep.season, 1);
      expect(ep.imageUrl, 'https://example.com/ep2.jpg');
      expect(ep.publishedAt, DateTime.utc(2026, 11, 24, 7, 30));
      expect(ep.variants, hasLength(3));
      expect(ep.audio!.url, 'https://cdn.example.com/ep2.mp3');
      expect(ep.video!.url, 'https://cdn.example.com/ep2-1080.mp4',
          reason: 'highest resolution, ipfs source skipped');
      expect(ep.canSwitchMedia, isTrue);
      expect(ep.defaultVariant!.kind, MediaKind.audio);
      expect(ep.transcripts, hasLength(2));
      expect(ep.transcripts.first.isTimed, isTrue);
      expect(ep.transcripts.last.isTimed, isFalse);
      expect(ep.chapters!.url, 'https://example.com/ep2.json');
    });

    test('video enclosure with media:content audio fallback', () {
      final ep = feed.episodes.last;
      expect(ep.defaultVariant!.kind, MediaKind.video);
      expect(ep.audio!.url, 'https://cdn.example.com/ep1.m4a');
      expect(ep.canSwitchMedia, isTrue);
      expect(ep.imageUrl, 'https://example.com/cover.jpg',
          reason: 'falls back to the podcast cover');
    });

    test('JSON round-trip', () {
      final ep = feed.episodes.first;
      final back = Episode.fromJson(ep.toJson());
      expect(back.toJson(), ep.toJson());
      final p = Podcast.fromJson(feed.podcast.toJson());
      expect(p.toJson(), feed.podcast.toJson());
    });
  });

  group('patreon feed', () {
    test('marks episodes premium and keeps the server-provided id', () {
      final feed = parser.parse(
        fixture('patreon_feed.xml'),
        feedUrl: 'https://www.patreon.com/rss/creator?auth=SECRET',
        podcastId: 'patreon_abc',
        source: PodcastSource.patreon,
        premium: true,
      );
      expect(feed.podcast.id, 'patreon_abc');
      expect(feed.podcast.isPremium, isTrue);
      expect(feed.podcast.imageUrl,
          'https://c10.patreonusercontent.com/cover.png');
      final ep = feed.episodes.single;
      expect(ep.premium, isTrue);
      expect(ep.podcastId, 'patreon_abc');
      expect(ep.audio!.url, contains('token-hash=abc'));
      expect(ep.publishedAt, DateTime.utc(2026, 11, 25, 23));
      expect(ep.duration, const Duration(minutes: 45, seconds: 30));
    });
  });

  test('rejects non-RSS documents', () {
    expect(() => parser.parse('<html/>', feedUrl: 'x'),
        throwsA(isA<FeedParseException>()));
    expect(() => parser.parse('not xml', feedUrl: 'x'),
        throwsA(isA<FeedParseException>()));
  });

  group('helpers', () {
    test('durations', () {
      expect(parseItunesDuration('90'), const Duration(seconds: 90));
      expect(parseItunesDuration('12:05'),
          const Duration(minutes: 12, seconds: 5));
      expect(parseItunesDuration('abc'), isNull);
    });

    test('dates', () {
      expect(parseFeedDate('Sat, 07 Sep 2002 00:00:01 GMT'),
          DateTime.utc(2002, 9, 7, 0, 0, 1));
      expect(parseFeedDate('7 Sept 2026 10:00 PST'),
          DateTime.utc(2026, 9, 7, 18));
      expect(parseFeedDate('2026-11-26T10:00:00Z'),
          DateTime.utc(2026, 11, 26, 10));
      expect(parseFeedDate('garbage'), isNull);
    });

    test('feed url normalization', () {
      expect(Podcast.normalizeFeedUrl('feed://a.com/rss'), 'https://a.com/rss');
      expect(Podcast.normalizeFeedUrl(' a.com/rss '), 'https://a.com/rss');
      expect(Podcast.idFor('feed://a.com/rss'), Podcast.idFor('https://a.com/rss'));
    });

    test('OPML round-trip', () {
      final xml = buildOpml([
        const OpmlEntry(feedUrl: 'https://a.com/rss', title: 'A'),
        const OpmlEntry(feedUrl: 'https://b.com/rss'),
      ]);
      final back = parseOpml(xml);
      expect(back.map((e) => e.feedUrl), ['https://a.com/rss', 'https://b.com/rss']);
      expect(back.first.title, 'A');
    });

    test('episode state merge is last-write-wins', () {
      final a = EpisodeState(episodeId: 'e', updatedAt: DateTime.utc(2026));
      final b = a.copyWith(liked: true, updatedAt: DateTime.utc(2026, 2));
      expect(EpisodeState.merge(a, b).liked, isTrue);
      expect(EpisodeState.merge(b, a).liked, isTrue);
    });
  });
}
