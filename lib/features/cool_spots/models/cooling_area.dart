bool isLasVegasArea(Map<String, dynamic> station) {
  final address = station['address'] as String? ?? '';
  final name = station['name'] as String? ?? '';
  if ('$name $address'.toLowerCase().contains('mount charleston')) return false;
  return RegExp(r'\b891\d{2}(?:-\d{4})?\b').hasMatch(address);
}
