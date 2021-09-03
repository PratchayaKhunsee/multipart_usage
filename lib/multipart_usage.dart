library multipart_usage;

import 'dart:convert';
import 'dart:typed_data';

class _Field {
  String name;
  Uint8List value;
  String? fileName;
  String? contentType;
  bool isFile;
  _Field(
    this.name,
    this.value, [
    this.fileName,
    this.contentType,
    this.isFile = false,
  ]);
}

class MultipartBuilder {
  String boundary;
  final List<_Field> _fields;
  MultipartBuilder([String? boundary])
      : boundary = boundary ?? 'boundary',
        _fields = [];

  void append(String name, String value) {
    _fields.add(_Field(name, Uint8List.fromList(utf8.encode(value))));
  }

  void appendFile(
    String name,
    Uint8List value,
    String fileName, [
    String? contentType,
  ]) {
    _fields.add(_Field(
      name,
      value,
      fileName,
      contentType,
      true,
    ));
  }

  Uint8List toBytes() {
    List<int> bytes = [];
    for (var f in _fields) {
      bytes.addAll(utf8.encode("--$boundary\r\n"));
      bytes.addAll(utf8.encode(
          "Content-Disposition: form-data; name=\"${f.name}\"${f.fileName != null ? "filename=\"${f.fileName}\"" : ""}\r\n"));
      if (f.isFile) {
        bytes.addAll(utf8.encode(
            "Content-Type: ${f.contentType ?? 'application/octet-stream'}\r\n"));
      }
      bytes.addAll(utf8.encode("\r\n"));
      bytes.addAll(f.value);
      bytes.addAll(utf8.encode("\r\n"));
    }

    if (bytes.isNotEmpty) {
      bytes.addAll(utf8.encode("--$boundary--\r\n"));
    }
    return Uint8List.fromList(bytes);
  }

  String toUtf8String() {
    return utf8.decode(toBytes(), allowMalformed: true);
  }
}

class MultipartField {
  final String name;
  final Uint8List value;
  final String? fileName;
  final Map<String, String> headers;

  MultipartField({
    required this.name,
    required this.value,
    this.fileName,
    this.headers = const {},
  });
}

class MultipartReader {
  late final List<MultipartField> _fields;
  MultipartReader(List<int> stream) {
    List<MultipartField> fields = [];

    int phase = 0;

    /// The current line as a byte list.
    List<int> currentLine = [];
    bool isFirstLine = true;
    late List<int> boundary;
    String? fileName;
    String? fieldName;
    List<int> content = [];
    Map<String, String> headers = {};

    bool isHeaderReadingPhase() => phase == 0;
    bool isBodyReadingPhase() => phase == 1;

    void createField() {
      fields.add(MultipartField(
        name: fieldName!,
        value: Uint8List.fromList(content),
        fileName: fileName,
        headers: headers,
      ));
    }

    bool isConsideredBoundary(List<int> currentLine) {
      List<int> b = utf8.encode('--');
      return currentLine[0] == b[0] && currentLine[1] == b[1];
    }

    bool isBoundary(List<int> currentLine, List<int> boundary) {
      List<int> b = utf8.encode('--').toList();
      b.addAll(boundary);
      if (currentLine.length != b.length) return false;
      for (var i = 0; i < b.length; i++) {
        if (b[i] != currentLine[i]) return false;
      }
      return true;
    }

    bool isEndOfMultipartBoundary(List<int> currentLine, List<int> boundary) {
      List<int> b = utf8.encode('--').toList();
      b.addAll(boundary);
      b.addAll(utf8.encode('--'));
      if (currentLine.length != b.length) return false;
      for (var i = 0; i < b.length; i++) {
        if (b[i] != currentLine[i]) return false;
      }

      return true;
    }

    for (int i = 0; i < stream.length; i++) {
      if (stream[i] == 0x0d && stream[i + 1] == 0x0a) {
        if (isFirstLine) {
          if (!isConsideredBoundary(currentLine)) break;

          boundary = currentLine.sublist(2);
        }

        // Go to form field's information reading phase.
        else if (isBoundary(currentLine, boundary)) {
          createField();
          phase = 0;
          fileName = fieldName = null;
          headers = {};
          content = [];
        }
        // End the entire reading process, and put the remaining form field.
        else if (isEndOfMultipartBoundary(currentLine, boundary)) {
          createField();
          break;
        }
        // Read the content from each line of payload.
        else if (isBodyReadingPhase()) {
          if (content.isNotEmpty) {
            content.addAll([0x0d, 0x0a]);
          }
          content.addAll(currentLine);
        } else if (isHeaderReadingPhase()) {
          String lineString = utf8.decode(currentLine, allowMalformed: true);

          if (lineString.isEmpty) {
            phase = 1;

            if (fieldName == null) {
              break;
            }
          }
          // Get form field's name and file name.
          else if (lineString.contains(RegExp(
            "Content-Disposition\\s*:\\s*form-data.+?name\\s*=\\s*\".*\"",
          ))) {
            List<String> n = lineString.split(
              RegExp("Content-Disposition\\s*:.+?name\\s*=\\s*\""),
            );

            List<String> fn = lineString.split(
              RegExp("Content-Disposition\\s*:.+?filename\\s*=\\s*\""),
            );

            if (n.length < 2) break;

            fieldName = n[1].replaceAll(RegExp("\".*\$"), "");

            fileName =
                fn.length < 2 ? null : fn[1].replaceAll(RegExp("\".*\$"), "");
          } else {
            List<String> p = lineString.split(RegExp(":(?=\\s*.+)"));

            if (p.length < 2) {
              break;
            }

            String attr = p[0];
            String val = "";

            for (int i = 1; i < p.length; i++) {
              val = val + p[i];
            }

            headers[attr] = val;
          }
        }

        ++i;
        isFirstLine = false;
        currentLine = [];
      } else {
        currentLine.add(stream[i]);
      }
    }

    // End the entire reading process, and put the remaining form field.
    if (isEndOfMultipartBoundary(currentLine, boundary)) {
      createField();
    }

    _fields = fields;
  }

  ///
  List<MultipartField> get([String? name]) {
    return name == null
        ? _fields.toList()
        : _fields.where((e) => e.name == name).toList();
  }
}
