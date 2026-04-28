class User {
  final int id;
  final String email;
  final String? name;
  final String? restaurantName;
  final String? restaurantSlug;
  final bool isAdmin;
  final bool isStaff;
  final String? logoUrl;
  final bool featureOnlineOrdering;

  const User({
    required this.id,
    required this.email,
    this.name,
    this.restaurantName,
    this.restaurantSlug,
    this.isAdmin = false,
    this.isStaff = false,
    this.logoUrl,
    this.featureOnlineOrdering = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final restaurant = json['restaurant'] as Map<String, dynamic>?;
    return User(
      id: json['id'] as int,
      email: json['email'] as String? ?? json['username'] as String? ?? '',
      name: json['name'] as String?,
      restaurantName: restaurant?['name'] as String?,
      restaurantSlug: restaurant?['slug'] as String?,
      isAdmin: json['is_admin'] as bool? ?? false,
      isStaff: json['is_staff'] as bool? ?? false,
      logoUrl: restaurant?['logo_url'] as String?,
      featureOnlineOrdering: restaurant?['feature_online_ordering'] as bool? ?? false,
    );
  }

  User copyWith({String? restaurantName, String? logoUrl}) => User(
        id: id,
        email: email,
        name: name,
        restaurantName: restaurantName ?? this.restaurantName,
        restaurantSlug: restaurantSlug,
        isAdmin: isAdmin,
        isStaff: isStaff,
        logoUrl: logoUrl ?? this.logoUrl,
        featureOnlineOrdering: featureOnlineOrdering,
      );
}
