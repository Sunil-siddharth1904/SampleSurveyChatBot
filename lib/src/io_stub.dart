class File {
  final String path;
  File(this.path);
  Future<void> writeAsString(String _) async {}
}

class Directory {
  final String path;
  Directory(this.path);
}
