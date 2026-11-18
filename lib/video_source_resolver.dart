import 'package:dio/dio.dart';

class VideoSource {
  final String url;
  final String label;
  final String type;

  const VideoSource({
    required this.url,
    required this.label,
    required this.type,
  });

  factory VideoSource.fromJson(Map<String, dynamic> json) {
    final url = (json['url'] ?? '').toString().trim();

    final parsedUri = Uri.tryParse(url);

    if (parsedUri == null ||
        !parsedUri.hasAuthority ||
        !['http', 'https'].contains(parsedUri.scheme)) {
      throw const FormatException('Invalid video source URL.');
    }

    return VideoSource(
      url: url,
      label: (json['label'] ??
              json['quality'] ??
              'Auto')
          .toString(),
      type: (json['type'] ??
              _detectType(url))
          .toString()
          .toLowerCase(),
    );
  }

  static String _detectType(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';

    if (path.endsWith('.m3u8')) return 'hls';
    if (path.endsWith('.mp4')) return 'mp4';

    return 'unknown';
  }

  bool get isHls => type == 'hls';

  bool get isMp4 => type == 'mp4';
}

class VideoResolutionResult {
  final List<VideoSource> sources;

  const VideoResolutionResult({
    required this.sources,
  });

  bool get hasSources => sources.isNotEmpty;
}

class VideoSourceResolver {
  VideoSourceResolver({
    required String endpoint,
    Dio? dio,
  })  : _endpoint = endpoint,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
                headers: {
                  'Accept': 'application/json',
                },
              ),
            );

  final String _endpoint;
  final Dio _dio;

  /// Resolves video sources using an authorized resolver endpoint.
  ///
  /// Expected request:
  /// GET endpoint?animeSession=...&episodeSession=...
  ///
  /// Expected response:
  /// {
  ///   "sources": [
  ///     {
  ///       "url": "https://example.com/video/master.m3u8",
  ///       "label": "1080p",
  ///       "type": "hls"
  ///     }
  ///   ]
  /// }
  Future<VideoResolutionResult> resolve({
    required String animeSession,
    required String episodeSession,
    required int episode,
    required String title,
    CancelToken? cancelToken,
  }) async {
    if (_endpoint.trim().isEmpty) {
      throw const VideoResolverException(
        'Video resolver endpoint is not configured.',
      );
    }

    if (animeSession.trim().isEmpty ||
        episodeSession.trim().isEmpty) {
      throw const VideoResolverException(
        'Anime or episode session is missing.',
      );
    }

    if (episode <= 0) {
      throw const VideoResolverException(
        'Invalid episode number.',
      );
    }

    try {
      final response = await _dio.get(
        _endpoint,
        queryParameters: {
          'animeSession': animeSession,
          'episodeSession': episodeSession,
          'episode': episode,
          'title': title,
        },
        cancelToken: cancelToken,
      );

      final List<dynamic> rawSources;

      if (response.data is List) {
        rawSources = response.data as List;
      } else if (response.data is Map) {
        final data = Map<String, dynamic>.from(
          response.data as Map,
        );

        if (data['sources'] is! List) {
          throw const FormatException(
            'Resolver response does not contain a sources list.',
          );
        }

        rawSources = data['sources'] as List;
      } else {
        throw const FormatException(
          'Unexpected resolver response format.',
        );
      }

      final sources = <VideoSource>[];

      for (final item in rawSources) {
        if (item is! Map) continue;

        try {
          sources.add(
            VideoSource.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        } on FormatException {
          // Ignore malformed source entries.
          continue;
        }
      }

      if (sources.isEmpty) {
        throw const VideoResolverException(
          'No valid video sources were returned.',
        );
      }

      return VideoResolutionResult(
        sources: sources,
      );
    } on DioException catch (error) {
      throw VideoResolverException(
        'Video resolution failed: '
        '${error.message ?? error.type.name}',
        statusCode: error.response?.statusCode,
      );
    }
  }

  void dispose() {
    _dio.close();
  }
}

class VideoResolverException implements Exception {
  final String message;
  final int? statusCode;

  const VideoResolverException(
    this.message, {
    this.statusCode,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return '$message (HTTP $statusCode)';
    }

    return message;
  }
}
