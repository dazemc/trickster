class KeyValueDocument {
  const KeyValueDocument(this.values);

  final Map<String, String> values;

  static KeyValueDocument parse(String source) {
    final values = <String, String>{};
    for (final rawLine in source.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final separator = line.indexOf('=');
      if (separator <= 0) {
        throw FormatException('expected KEY=VALUE, found: $line');
      }
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key.isEmpty) {
        throw FormatException('empty key in: $line');
      }
      values[key] = value;
    }
    return KeyValueDocument(values);
  }

  String? operator [](String key) => values[key];
}
