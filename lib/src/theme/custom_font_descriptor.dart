final class CustomFontDescriptor {
  const CustomFontDescriptor({
    required this.id,
    required this.name,
    required this.path,
  });

  factory CustomFontDescriptor.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid custom font descriptor');
    }
    final id = value['id'];
    final name = value['name'];
    final path = value['path'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        path is! String ||
        path.isEmpty ||
        !(path.startsWith('/') ||
            path.startsWith(r'\\') ||
            RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path))) {
      throw const FormatException('Invalid custom font descriptor');
    }
    return CustomFontDescriptor(id: id, name: name, path: path);
  }

  final String id;
  final String name;
  final String path;

  String get fontFamily => 'UserFont_$id';

  Map<String, String> toMap() => {'id': id, 'name': name, 'path': path};
}
