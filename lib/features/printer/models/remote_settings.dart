class RemoteSettings {
  final String serverBaseUrl;
  final String restaurantSlug;
  final bool wsEnabled;

  const RemoteSettings({
    this.serverBaseUrl = 'https://api.kinzo.vn',
    this.restaurantSlug = '',
    this.wsEnabled = false,
  });

  RemoteSettings copyWith({
    String? serverBaseUrl,
    String? restaurantSlug,
    bool? wsEnabled,
  }) => RemoteSettings(
    serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
    restaurantSlug: restaurantSlug ?? this.restaurantSlug,
    wsEnabled: wsEnabled ?? this.wsEnabled,
  );

  bool get isConfigured => serverBaseUrl.isNotEmpty && restaurantSlug.isNotEmpty;

  String get wsUrl {
    if (!isConfigured) return '';
    final base = serverBaseUrl
        .replaceFirst(RegExp(r'^https://'), 'wss://')
        .replaceFirst(RegExp(r'^http://'), 'ws://')
        .replaceFirst(RegExp(r'/$'), '');
    return '$base/ws/printer?slug=$restaurantSlug';
  }
}
