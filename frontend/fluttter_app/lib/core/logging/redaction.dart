/// JSON keys whose values must never appear in logs.
const Set<String> sensitiveKeys = {
  'browserToken',
  'organizerToken',
  'recoveryCode',
  'apikey',
  'authorization',
};

const String redactedPlaceholder = '***';

/// Returns a copy of [value] with every sensitive key's value replaced by
/// [redactedPlaceholder]. Walks nested maps and lists. Other values are
/// returned unchanged.
Object? redactSensitive(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): sensitiveKeys.contains(entry.key.toString())
            ? redactedPlaceholder
            : redactSensitive(entry.value),
    };
  }
  if (value is List) {
    return [for (final item in value) redactSensitive(item)];
  }
  return value;
}
