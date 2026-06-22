class ApiConfig {
  // Injected at Flutter build time via --dart-define=API_BASE_URL=https://your-domain.com
  // Falls back to localhost for local development.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
