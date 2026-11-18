import 'package:dio/dio.dart';

const String animePaheApi = 'https://animepahe.pw/api?m=';

class AnimeResult {
  final int id;
  final String title;
  final String type;
  final int episodes;
  final String status;
  final String season;
  final int year;
  final double score;
  final String poster;
  final String session;

  const AnimeResult({
    required this.id,
    required this.title,
    required this.type,
    required this.episodes,
    required this.status,
    required this.season,
    required this.year,
    required this.score,
    required this.poster,
    required this.session,
  });

  factory AnimeResult.fromJson(Map<String, dynamic> json) {
    return AnimeResult(
      id: _toInt(json['id']),
      title: json['title']?.toString() ?? 'Unknown',
      type: json['type']?.toString() ?? '',
      episodes: _toInt(json['episodes']),
      status: json['status']?.toString() ?? '',
      season: json['season']?.toString() ?? '',
      year: _toInt(json['year']),
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      poster: json['poster']?.toString() ?? '',
      session: json['session']?.toString() ?? '',
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class AnimeSearchPage {
  final List<AnimeResult> items;
  final int currentPage;
  final int totalPages;
  final int perPage;

  const AnimeSearchPage({
    required this.items,
    required this.currentPage,
    required this.totalPages,
    required this.perPage,
  });

  bool get hasNextPage => currentPage < totalPages;
}

class AnimeEpisode {
  final String session;
  final int number;

  const AnimeEpisode({
    required this.session,
    required this.number,
  });

  factory AnimeEpisode.fromJson(Map<String, dynamic> json) {
    return AnimeEpisode(
      session: json['session']?.toString() ?? '',
      number: _toInt(json['episode']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class AnimeEpisodePage {
  final List<AnimeEpisode> episodes;
  final int currentPage;
  final int totalPages;
  final int perPage;

  const AnimeEpisodePage({
    required this.episodes,
    required this.currentPage,
    required this.totalPages,
    required this.perPage,
  });

  bool get hasNextPage => currentPage < totalPages;
}

class AnimePaheScraper {
  AnimePaheScraper({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: animePaheApi,
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 25),
                headers: {
                  'Accept': 'application/json, text/plain, */*',
                  'User-Agent': 'Mozilla/5.0',
                },
              ),
            );

  final Dio _dio;

  /// Searches anime.
  ///
  /// GET /api?m=search&q=...&page=...
  Future<AnimeSearchPage> search({
    required String query,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    if (query.trim().isEmpty) {
      return const AnimeSearchPage(
        items: [],
        currentPage: 1,
        totalPages: 1,
        perPage: 0,
      );
    }

    try {
      final response = await _dio.get(
        '',
        queryParameters: {
          'q': query.trim(),
          'page': page,
        },
        cancelToken: cancelToken,
      );

      final json = _asMap(response.data);
      final rawItems = json['data'];

      if (rawItems is! List) {
        throw const FormatException(
          'AnimePahe search response has no data list.',
        );
      }

      final items = rawItems
          .whereType<Map>()
          .map(
            (item) => AnimeResult.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();

      return AnimeSearchPage(
        items: items,
        currentPage: _toInt(
          json['current_page'],
          fallback: page,
        ),
        totalPages: _toInt(
          json['total'],
          fallback: page,
        ),
        perPage: _toInt(json['per_page']),
      );
    } on DioException catch (error) {
      throw AnimePaheException(
        'Anime search failed: '
        '${error.message ?? error.type.name}',
        statusCode: error.response?.statusCode,
      );
    }
  }

  /// Retrieves one page of episodes.
  ///
  /// GET /api?m=release&id=...&sort=episode_asc&page=...
  Future<AnimeEpisodePage> getEpisodePage({
    required String animeSession,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    if (animeSession.trim().isEmpty) {
      throw ArgumentError('Anime session cannot be empty.');
    }

    try {
      final response = await _dio.get(
        '',
        queryParameters: {
          'id': animeSession,
          'sort': 'episode_asc',
          'page': page,
        },
        cancelToken: cancelToken,
      );

      final json = _asMap(response.data);
      final rawItems = json['data'];

      if (rawItems is! List) {
        throw const FormatException(
          'AnimePahe episode response has no data list.',
        );
      }

      final episodes = rawItems
          .whereType<Map>()
          .map(
            (item) => AnimeEpisode.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (episode) =>
                episode.session.isNotEmpty &&
                episode.number > 0,
          )
          .toList();

      return AnimeEpisodePage(
        episodes: episodes,
        currentPage: page,
        totalPages: _toInt(
          json['last_page'],
          fallback: page,
        ),
        perPage: _toInt(json['per_page']),
      );
    } on DioException catch (error) {
      throw AnimePaheException(
        'Episode retrieval failed: '
        '${error.message ?? error.type.name}',
        statusCode: error.response?.statusCode,
      );
    }
  }

  /// Fetches all available episode pages.
  Future<List<AnimeEpisode>> getAllEpisodes({
    required String animeSession,
    CancelToken? cancelToken,
  }) async {
    final allEpisodes = <AnimeEpisode>[];
    var page = 1;

    while (true) {
      final result = await getEpisodePage(
        animeSession: animeSession,
        page: page,
        cancelToken: cancelToken,
      );

      if (result.episodes.isEmpty) break;

      allEpisodes.addAll(result.episodes);

      if (result.perPage <= 0 ||
          result.episodes.length < result.perPage) {
        break;
      }

      page++;

      if (page > 500) {
        throw const AnimePaheException(
          'Episode pagination exceeded the safety limit.',
        );
      }
    }

    return allEpisodes;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    throw const FormatException(
      'Unexpected API response format.',
    );
  }

  static int _toInt(
    dynamic value, {
    int fallback = 0,
  }) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        fallback;
  }

  void dispose() {
    _dio.close();
  }
}

class AnimePaheException implements Exception {
  final String message;
  final int? statusCode;

  const AnimePaheException(
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
