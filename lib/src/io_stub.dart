// Mock classes for web compatibility. 
// These allow the app to compile when dart:io is not available.

enum FileMode {
  read,
  write,
  append,
  writeOnly,
  writeOnlyAppend
}

class File {
  final String path;
  File(this.path);
  
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    return this;
  }
}

class Directory {
  final String path;
  Directory(this.path);
}

