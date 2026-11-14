/// Resolves media paths returned by the API into absolute URLs.
///
/// Cloudinary returns full `https://…` URLs, while the local-storage fallback
/// returns server-relative paths such as `/uploads/tickets/abc.png`.
String? resolveMediaUrl(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }

  const apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.katisha.today/api',
  );
  final serverBase = apiBase.replaceAll('/api', '');
  return trimmed.startsWith('/')
      ? '$serverBase$trimmed'
      : '$serverBase/$trimmed';
}
