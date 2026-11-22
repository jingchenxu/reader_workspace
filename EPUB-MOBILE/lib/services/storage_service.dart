import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

class StorageService {
  Future<Directory> get rootDir async {
    final directory = await getApplicationDocumentsDirectory();
    return directory;
  }

  Future<Directory> get booksDir async {
    final directory = Directory(p.join((await rootDir).path, 'books'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> get coversDir async {
    final directory = Directory(p.join((await rootDir).path, 'covers'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> importBookFile(String sourcePath) async {
    final source = File(sourcePath);
    final sourceName = p.basename(sourcePath);
    final safeName = sourceName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final target = File(
      p.join((await booksDir).path,
          'book_${DateTime.now().millisecondsSinceEpoch}_$safeName'),
    );
    return source.copy(target.path);
  }

  Future<File> importAssetBook({
    required String assetPath,
    required String fileName,
    bool overwrite = false,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final target = File(p.join((await booksDir).path, safeName));
    if (await target.exists() && !overwrite) {
      return target;
    }

    final data = await rootBundle.load(assetPath);
    return target.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  Future<String?> extractCover(String relativeBookPath) async {
    final bookFile = File(await absolutePath(relativeBookPath));
    if (!await bookFile.exists()) return null;

    final archive = ZipDecoder().decodeBytes(await bookFile.readAsBytes());
    final container = archive.findFile('META-INF/container.xml');
    if (container == null) return null;

    final containerXml = _decodeFile(container);
    final rootFilePath = _findRootFilePath(containerXml);
    if (rootFilePath == null) return null;

    final opfFile = archive.findFile(rootFilePath);
    if (opfFile == null) return null;

    final opfXml = _decodeFile(opfFile);
    final coverHref = _findCoverHref(opfXml);
    if (coverHref == null) return null;

    final opfDir = p.posix.dirname(rootFilePath);
    final coverPath = p.posix.normalize(p.posix.join(opfDir, coverHref));
    final coverFile = archive.findFile(coverPath);
    if (coverFile == null || !coverFile.isFile) return null;

    final extension =
        p.extension(coverPath).isEmpty ? '.jpg' : p.extension(coverPath);
    final baseName = p.basenameWithoutExtension(relativeBookPath);
    final safeBaseName = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final target = File(
      p.join(
        (await coversDir).path,
        '${safeBaseName}_cover_${DateTime.now().millisecondsSinceEpoch}$extension',
      ),
    );
    await target.writeAsBytes(_fileBytes(coverFile), flush: true);
    return relativePath(target.path);
  }

  Future<String> relativePath(String absolutePath) async {
    return p.relative(absolutePath, from: (await rootDir).path);
  }

  Future<String> absolutePath(String relativePath) async {
    return p.join((await rootDir).path, relativePath);
  }

  Future<void> deleteRelativeFile(String relativePath) async {
    final file = File(await absolutePath(relativePath));
    if (await file.exists()) {
      await file.delete();
    }
  }

  String? _findRootFilePath(String containerXml) {
    final document = XmlDocument.parse(containerXml);
    final rootfile = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'rootfile')
        .firstOrNull;
    return rootfile?.getAttribute('full-path');
  }

  String? _findCoverHref(String opfXml) {
    final document = XmlDocument.parse(opfXml);
    final elements = document.descendants.whereType<XmlElement>().toList();
    final manifestItems =
        elements.where((element) => element.name.local == 'item').toList();

    for (final item in manifestItems) {
      final properties = item.getAttribute('properties') ?? '';
      if (properties.split(RegExp(r'\s+')).contains('cover-image')) {
        return item.getAttribute('href');
      }
    }

    final coverMeta = elements
        .where((element) =>
            element.name.local == 'meta' &&
            element.getAttribute('name') == 'cover')
        .firstOrNull;
    final coverId = coverMeta?.getAttribute('content');
    if (coverId != null && coverId.isNotEmpty) {
      final coverItem = manifestItems
          .where((item) => item.getAttribute('id') == coverId)
          .firstOrNull;
      final href = coverItem?.getAttribute('href');
      if (href != null && href.isNotEmpty) return href;
    }

    for (final item in manifestItems) {
      final mediaType = item.getAttribute('media-type') ?? '';
      final href = item.getAttribute('href') ?? '';
      final id = item.getAttribute('id') ?? '';
      final looksLikeCover = '$id $href'.toLowerCase().contains('cover') &&
          mediaType.startsWith('image/');
      if (looksLikeCover) return href;
    }

    return null;
  }

  String _decodeFile(ArchiveFile file) {
    return utf8.decode(_fileBytes(file), allowMalformed: true);
  }

  Uint8List _fileBytes(ArchiveFile file) {
    return file.content;
  }
}
