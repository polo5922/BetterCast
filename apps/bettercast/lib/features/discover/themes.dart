import 'package:flutter/material.dart';

/// Discovery themes, mapped to Apple Podcasts genre ids.
class PodcastTheme {
  const PodcastTheme(this.genre, this.label, this.icon, this.color);
  final String genre;
  final String label;
  final IconData icon;
  final Color color;

  static PodcastTheme? byGenre(String genre) =>
      all.where((t) => t.genre == genre).firstOrNull;

  static const all = [
    PodcastTheme('1489', 'Actualités', Icons.newspaper, Color(0xFF1E88E5)),
    PodcastTheme('1309', 'Cinéma & séries', Icons.movie_outlined, Color(0xFFE53935)),
    PodcastTheme('1303', 'Humour', Icons.sentiment_very_satisfied, Color(0xFFFB8C00)),
    PodcastTheme('1324', 'Société & culture', Icons.groups_outlined, Color(0xFF8E24AA)),
    PodcastTheme('1487', 'Histoire', Icons.history_edu, Color(0xFF6D4C41)),
    PodcastTheme('1533', 'Sciences', Icons.science_outlined, Color(0xFF00897B)),
    PodcastTheme('1318', 'Technologie', Icons.memory, Color(0xFF3949AB)),
    PodcastTheme('1502', 'Loisirs & jeux vidéo', Icons.sports_esports_outlined, Color(0xFF43A047)),
    PodcastTheme('1545', 'Sport', Icons.sports_soccer, Color(0xFF00ACC1)),
    PodcastTheme('1488', 'Faits divers', Icons.fingerprint, Color(0xFF546E7A)),
    PodcastTheme('1483', 'Fiction', Icons.auto_stories_outlined, Color(0xFFD81B60)),
    PodcastTheme('1321', 'Business', Icons.business_center_outlined, Color(0xFF5E35B1)),
    PodcastTheme('1512', 'Santé & bien-être', Icons.spa_outlined, Color(0xFF7CB342)),
    PodcastTheme('1301', 'Arts', Icons.palette_outlined, Color(0xFFF4511E)),
    PodcastTheme('1310', 'Musique', Icons.music_note_outlined, Color(0xFFC0CA33)),
    PodcastTheme('1304', 'Éducation', Icons.school_outlined, Color(0xFF039BE5)),
    PodcastTheme('1305', 'Enfants & famille', Icons.child_care, Color(0xFFFFB300)),
  ];
}

class ThemeCard extends StatelessWidget {
  const ThemeCard(this.theme, {super.key, required this.onTap});
  final PodcastTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = theme.color;
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c, Color.lerp(c, Colors.black, 0.35)!],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            Positioned(
              right: -8,
              bottom: -8,
              child: Icon(theme.icon, size: 64, color: Colors.white.withValues(alpha: 0.25)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                theme.label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
