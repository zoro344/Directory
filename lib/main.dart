import 'package:flutter/material.dart';
import 'animepahe_scraper.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ScraperTestPage(),
  ));
}

class ScraperTestPage extends StatefulWidget {
  const ScraperTestPage({super.key});

  @override
  State<ScraperTestPage> createState() => _ScraperTestPageState();
}

class _ScraperTestPageState extends State<ScraperTestPage> {
  final scraper = AnimePaheScraper();
  final controller = TextEditingController();

  List<AnimeResult> results = [];
  List<AnimeEpisode> episodes = [];

  bool loading = false;
  String message = '';

  Future<void> search() async {
    setState(() {
      loading = true;
      message = '';
      episodes = [];
    });

    try {
      final result = await scraper.search(
        query: controller.text,
      );

      setState(() {
        results = result.items;
        message = '${result.items.length} anime found';
      });
    } catch (e) {
      setState(() => message = 'Search error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> loadEpisodes(AnimeResult anime) async {
    setState(() {
      loading = true;
      episodes = [];
      message = 'Loading episodes...';
    });

    try {
      final result = await scraper.getAllEpisodes(
        animeSession: anime.session,
      );

      setState(() {
        episodes = result;
        message = '${result.length} episodes found';
      });
    } catch (e) {
      setState(() => message = 'Episode error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    scraper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AnimePahe Scraper Test')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Search anime...',
                    ),
                    onSubmitted: (_) => search(),
                  ),
                ),
                IconButton(
                  onPressed: loading ? null : search,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(message),
          ),
          Expanded(
            child: ListView(
              children: [
                ...results.map((anime) => ListTile(
                  leading: anime.poster.isEmpty
                      ? const Icon(Icons.movie)
                      : Image.network(
                          anime.poster,
                          width: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.movie),
                        ),
                  title: Text(anime.title),
                  subtitle: Text(
                    '${anime.type} • ${anime.episodes} episodes • ${anime.year}',
                  ),
                  onTap: () => loadEpisodes(anime),
                )),
                ...episodes.map((episode) => ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text('Episode ${episode.number}'),
                  subtitle: Text(
                    'Session: ${episode.session}',
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
