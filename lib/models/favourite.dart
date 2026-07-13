// One bookmarked transit date with a user-written memory note.
//
// Mirrors the row shape returned by /api/favourites endpoints. transitDate is
// "YYYY-MM-DD"; createdAt is whatever SQLite's CURRENT_TIMESTAMP yields
// ("YYYY-MM-DD HH:MM:SS" UTC) — kept as a plain string so we don't have to
// fight timezone parsing.
class Favourite {
  final int id;
  final String userKey;
  final String transitDate;
  final String? title;
  final String description;
  final String createdAt;

  Favourite({
    required this.id,
    required this.userKey,
    required this.transitDate,
    required this.title,
    required this.description,
    required this.createdAt,
  });

  factory Favourite.fromJson(Map<String, dynamic> json) => Favourite(
        id: json['id'] as int,
        userKey: json['userKey'] as String,
        transitDate: json['transitDate'] as String,
        title: json['title'] as String?,
        description: (json['description'] as String?) ?? '',
        createdAt: (json['createdAt'] as String?) ?? '',
      );
}
