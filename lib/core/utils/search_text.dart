/// Minúsculas y sin tildes, para comparar texto escrito por una persona:
/// "cordoba" coincide con "Córdoba" y "pueyrredon" con "Pueyrredón".
String normalizeForSearch(String value) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().trim().runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString();
}
