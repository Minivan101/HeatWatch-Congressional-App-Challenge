enum RoutePreference {
  balanced('Balanced', 'A practical mix of walking time and predicted shade.'),
  mostShade('Most Shade', 'The highest predicted shaded share of the walk.'),
  fastest('Fastest', 'Shortest estimated walking time.');

  const RoutePreference(this.label, this.description);
  final String label, description;
}
