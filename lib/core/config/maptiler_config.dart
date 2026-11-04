/// The MapTiler API key, given at build time:
/// `flutter run --dart-define=MAPTILER_KEY=your_key`.
class MapTilerConfig {
  MapTilerConfig._();

  static const String apiKey = String.fromEnvironment('MAPTILER_KEY');

  static bool get isConfigured => apiKey.trim().isNotEmpty;

  static const String missingKeyMessage =
      'MapTiler key missing, so MapTiler map tiles are off. Start the app '
      'with --dart-define=MAPTILER_KEY=your_key (see the README).';
}
