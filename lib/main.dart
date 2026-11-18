import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'animepahe_scraper.dart';
import 'video_source_resolver.dart';

/// Configure this when you have an authorized video resolver API.
///
/// Example:
/// flutter build apk --dart-define=VIDEO_RESOLVER_URL=https://your-domain.com/resolve
const String resolverEndpoint = String.fromEnvironment(
  'VIDEO_RESOLVER_URL',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  runApp(const AnimeStreamingApp());
}

class AnimeStreamingApp extends StatelessWidget {
  const AnimeStreamingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anime Streaming App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080808),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9B6DFF),
          secondary: Color(0xFFC5A7FF),
          surface: Color(0xFF171717),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080808),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1B1B1B),
          hintStyle: const TextStyle(color: Colors.white54),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF292929),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: const AnimeHomePage(),
    );
  }
}

class AnimeHomePage extends StatefulWidget {
  const AnimeHomePage({super.key});

  @override
  State<AnimeHomePage> createState() => _AnimeHomePageState();
}

class _AnimeHomePageState extends State<AnimeHomePage> {
  final AnimePaheScraper _scraper = AnimePaheScraper();
  final TextEditingController _searchController =
      TextEditingController();

  List<AnimeResult> _results = [];
  List<AnimeEpisode> _episodes = [];

  AnimeResult? _selectedAnime;

  bool _loading = false;
  bool _loadingEpisodes = false;

  String _message = 'Search for your favourite anime';

  Future<void> _searchAnime() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      _showMessage('Enter an anime name first.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _results = [];
      _episodes = [];
      _selectedAnime = null;
      _message = 'Searching anime...';
    });

    try {
      final result = await _scraper.search(
        query: query,
        page: 1,
      );

      if (!mounted) return;

      setState(() {
        _results = result.items;
        _message = result.items.isEmpty
            ? 'No anime found.'
            : '${result.items.length} anime found';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _message = 'Search failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadEpisodes(AnimeResult anime) async {
    if (anime.session.isEmpty) {
      _showMessage('Anime session is unavailable.');
      return;
    }

    setState(() {
      _selectedAnime = anime;
      _episodes = [];
      _loadingEpisodes = true;
      _message = 'Loading episodes...';
    });

    try {
      final episodes = await _scraper.getAllEpisodes(
        animeSession: anime.session,
      );

      if (!mounted) return;

      setState(() {
        _episodes = episodes;
        _message = episodes.isEmpty
            ? 'No episodes found.'
            : '${episodes.length} episodes available';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _message = 'Could not load episodes: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingEpisodes = false;
        });
      }
    }
  }

  Future<void> _playEpisode(AnimeEpisode episode) async {
    final anime = _selectedAnime;

    if (anime == null) {
      _showMessage('Select an anime first.');
      return;
    }

    if (resolverEndpoint.isEmpty) {
      _showMessage(
        'Video resolver is not configured. '
        'Add VIDEO_RESOLVER_URL to enable playback.',
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    VideoResolutionResult? result;
    final resolver = VideoSourceResolver(
      endpoint: resolverEndpoint,
    );

    try {
      result = await resolver.resolve(
        animeSession: anime.session,
        episodeSession: episode.session,
        episode: episode.number,
        title: anime.title,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Video source error: $error');
      }
    } finally {
      resolver.dispose();

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }

    if (!mounted || result == null) return;

    final sources = result.sources;

    VideoSource? selectedSource;

    if (sources.length == 1) {
      selectedSource = sources.first;
    } else {
      selectedSource = await showModalBottomSheet<VideoSource>(
        context: context,
        backgroundColor: const Color(0xFF191919),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select video quality',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...sources.map(
                    (source) => ListTile(
                      leading: const Icon(
                        Icons.high_quality,
                        color: Color(0xFFB58AFF),
                      ),
                      title: Text(source.label),
                      subtitle: Text(
                        source.type.toUpperCase(),
                      ),
                      onTap: () {
                        Navigator.pop(context, source);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (selectedSource == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          title: anime.title,
          episode: episode.number,
          source: selectedSource!,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildAnimePoster(AnimeResult anime) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 58,
        height: 78,
        child: anime.poster.isEmpty
            ? Container(
                color: const Color(0xFF292929),
                child: const Icon(Icons.movie),
              )
            : Image.network(
                anime.poster,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    color: const Color(0xFF292929),
                    child: const Icon(Icons.movie),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildAnimeCard(AnimeResult anime) {
    final subtitle = [
      if (anime.type.isNotEmpty) anime.type,
      if (anime.episodes > 0) '${anime.episodes} episodes',
      if (anime.year > 0) anime.year.toString(),
    ].join(' • ');

    return Card(
      color: const Color(0xFF171717),
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(9),
        leading: _buildAnimePoster(anime),
        title: Text(
          anime.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            subtitle.isEmpty ? 'Anime' : subtitle,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Color(0xFFB58AFF),
        ),
        onTap: _loadingEpisodes
            ? null
            : () => _loadEpisodes(anime),
      ),
    );
  }

  Widget _buildEpisodeList() {
    if (_selectedAnime == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(
            _selectedAnime!.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_loadingEpisodes)
          const LinearProgressIndicator(
            color: Color(0xFF9B6DFF),
          ),
        ..._episodes.map(
          (episode) => Card(
            color: const Color(0xFF171717),
            margin: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF302044),
                child: Icon(
                  Icons.play_arrow,
                  color: Color(0xFFC5A7FF),
                ),
              ),
              title: Text('Episode ${episode.number}'),
              subtitle: const Text(
                'Tap to find available video sources',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                ),
              ),
              trailing: const Icon(
                Icons.play_circle_outline,
                color: Color(0xFFB58AFF),
              ),
              onTap: _loading
                  ? null
                  : () => _playEpisode(episode),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scraper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(
              Icons.play_circle_fill,
              color: Color(0xFFB58AFF),
            ),
            SizedBox(width: 9),
            Text(
              'Anime Stream',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchAnime(),
              decoration: InputDecoration(
                hintText: 'Search anime...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _loading ? null : _searchAnime,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),

          if (_loading)
            const LinearProgressIndicator(
              color: Color(0xFF9B6DFF),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 9,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _message,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (_selectedAnime != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedAnime = null;
                        _episodes = [];
                        _message = 'Select or search another anime';
                      });
                    },
                    child: const Text('Back to results'),
                  ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              children: [
                if (_selectedAnime == null)
                  ..._results.map(_buildAnimeCard),
                _buildEpisodeList(),
                if (!_loading &&
                    _results.isEmpty &&
                    _selectedAnime == null)
                  const Padding(
                    padding: EdgeInsets.all(35),
                    child: Column(
                      children: [
                        Icon(
                          Icons.movie_filter_outlined,
                          size: 55,
                          color: Colors.white24,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Search anime to get started',
                          style: TextStyle(
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VideoPlayerPage extends StatefulWidget {
  final String title;
  final int episode;
  final VideoSource source;

  const VideoPlayerPage({
    super.key,
    required this.title,
    required this.episode,
    required this.source,
  });

  @override
  State<VideoPlayerPage> createState() =>
      _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player _player;
  late final VideoController _controller;

  String? _error;

  @override
  void initState() {
    super.initState();

    _player = Player();
    _controller = VideoController(_player);

    _openVideo();
  }

  Future<void> _openVideo() async {
    try {
      await _player.open(
        Media(widget.source.url),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.title} - Episode ${widget.episode}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Playback failed:\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                        ),
                      ),
                    )
                  : Video(
                      controller: _controller,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.high_quality,
                  color: Color(0xFFB58AFF),
                ),
                const SizedBox(width: 8),
                Text(
                  'Quality: ${widget.source.label}',
                  style: const TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
