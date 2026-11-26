import '../util/json.dart';

enum MediaKind { audio, video }

/// One playable rendition of an episode (an `<enclosure>` or a
/// `podcast:alternateEnclosure`). An episode may expose an audio and a video
/// variant, which is what lets the player switch between them.
class MediaVariant {
  const MediaVariant({
    required this.url,
    required this.mimeType,
    this.length,
    this.bitrate,
    this.height,
    this.title,
    this.isDefault = false,
  });

  final String url;
  final String mimeType;
  final int? length;
  final double? bitrate;
  final int? height;
  final String? title;
  final bool isDefault;

  MediaKind get kind => kindForMime(mimeType, url);

  static MediaKind kindForMime(String mime, [String? url]) {
    final m = mime.toLowerCase();
    if (m.startsWith('video/')) {
      return MediaKind.video;
    }
    if (m.isEmpty || m == 'application/octet-stream') {
      return _videoExt(url) ? MediaKind.video : MediaKind.audio;
    }
    return MediaKind.audio;
  }

  static bool _videoExt(String? url) {
    if (url == null) return false;
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return const ['.mp4', '.m4v', '.mov', '.webm', '.mkv'].any(path.endsWith);
  }

  Json toJson() => {
        'url': url,
        'mimeType': mimeType,
        if (length != null) 'length': length,
        if (bitrate != null) 'bitrate': bitrate,
        if (height != null) 'height': height,
        if (title != null) 'title': title,
        'isDefault': isDefault,
      };

  factory MediaVariant.fromJson(Json j) => MediaVariant(
        url: j['url'] as String,
        mimeType: j['mimeType'] as String? ?? '',
        length: (j['length'] as num?)?.toInt(),
        bitrate: (j['bitrate'] as num?)?.toDouble(),
        height: (j['height'] as num?)?.toInt(),
        title: j['title'] as String?,
        isDefault: j['isDefault'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaVariant && other.url == url && other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(url, mimeType);
}
