// Synthetic codec benchmark. Does not open app databases or backup files.
// Run: dart run tool/backup_codec_memory_benchmark.dart --rows=20000 --detail=1024
// Each scenario uses a fresh child process so maxRss is independently measured.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final class _ByteSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> value) => bytes.add(value);
  @override
  void close() {}
}

final class _ValueSink implements Sink<Object?> {
  Object? value;
  int count = 0;
  @override
  void add(Object? next) {
    count++;
    value = next;
  }

  @override
  void close() {}
}

final class _LimitedForwardSink implements Sink<List<int>> {
  _LimitedForwardSink(this.next);
  final Sink<List<int>> next;
  int length = 0;
  @override
  void add(List<int> value) {
    length += value.length;
    if (length > 250 * 1024 * 1024) throw const FormatException('Too large');
    next.add(value);
  }

  @override
  void close() => next.close();
}

Map<String, Object?> _synthetic(int count, int detailLength) {
  final rows = <Map<String, Object?>>[];
  final ids = <String, int>{};
  for (var id = 1; id <= count; id++) {
    final text = StringBuffer();
    while (text.length < detailLength) {
      text.write('battle:$id:${text.length}:synthetic-1234567890-');
    }
    rows.add({
      'id': id,
      'created_at': 1700000000 + id,
      'rank': 'S',
      'detail_json': text.toString().substring(0, detailLength),
    });
    ids['$id'] = id;
  }
  return {
    'memberId': 1001,
    'logbookSchema': 12,
    'tables': {
      'battle_logs': rows,
      for (final name in [
        'map_resource_logs',
        'resource_logs',
        'expedition_logs',
        'pending_construction_logs',
        'construction_logs',
        'development_logs',
        'retirement_logs',
      ])
        name: <Map<String, Object?>>[],
    },
    'compositions': <Object?>[],
    'writerId': 'synthetic',
    'rowIds': {'battle_logs': ids},
  };
}

Uint8List _encode(Map<String, Object?> value, {required bool streaming}) {
  final List<int> compressed;
  if (streaming) {
    final target = _ByteSink();
    final deflater = gzip.encoder.startChunkedConversion(target);
    final jsonSink = JsonUtf8Encoder(
      null,
      null,
      16 * 1024,
    ).startChunkedConversion(deflater);
    jsonSink.add(value);
    jsonSink.close();
    compressed = target.bytes.takeBytes();
  } else {
    compressed = gzip.encode(utf8.encode(jsonEncode(value)));
  }
  final envelope = {
    'format': 'yahagi-record-backup',
    'version': 1,
    'sha256': sha256.convert(compressed).toString(),
    'payload': base64Encode(compressed),
  };
  if (streaming) return JsonUtf8Encoder().convert(envelope) as Uint8List;
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

Object? _decode(Uint8List bytes, {required bool streaming}) {
  final jsonUtf8 = utf8.decoder.fuse(json.decoder);
  final outer =
      (streaming ? jsonUtf8.convert(bytes) : jsonDecode(utf8.decode(bytes)))
          as Map<String, dynamic>;
  final compressed = base64Decode(outer['payload'] as String);
  if (sha256.convert(compressed).toString() != outer['sha256']) {
    throw StateError('Checksum mismatch');
  }
  if (streaming) {
    final value = _ValueSink();
    final inflate = gzip.decoder.startChunkedConversion(
      _LimitedForwardSink(jsonUtf8.startChunkedConversion(value)),
    );
    inflate.add(compressed);
    inflate.close();
    if (value.count != 1) throw StateError('Unexpected JSON value count');
    return value.value;
  }
  final output = _ByteSink();
  final inflate = gzip.decoder.startChunkedConversion(output);
  inflate.add(compressed);
  inflate.close();
  return jsonDecode(utf8.decode(output.bytes.takeBytes()));
}

bool _sameValue(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.entries.every(
          (entry) =>
              right.containsKey(entry.key) &&
              _sameValue(entry.value, right[entry.key]),
        );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameValue(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

Future<void> main(List<String> args) async {
  String option(String name, String fallback) => args
      .firstWhere(
        (arg) => arg.startsWith('--$name='),
        orElse: () => '--$name=$fallback',
      )
      .split('=')[1];
  final rows = int.parse(option('rows', '20000'));
  final detail = int.parse(option('detail', '1024'));
  final mode = option('child', '');
  if (mode.isEmpty) {
    for (final scenario in [
      'legacy-encode',
      'streaming-encode',
      'legacy-decode',
      'streaming-decode',
    ]) {
      final result = await Process.run(Platform.resolvedExecutable, [
        Platform.script.toFilePath(),
        '--child=$scenario',
        '--rows=$rows',
        '--detail=$detail',
      ]);
      stdout.write(result.stdout);
      if (result.exitCode != 0) {
        stderr.write(result.stderr);
        exitCode = result.exitCode;
        return;
      }
    }
    return;
  }
  final data = _synthetic(rows, detail);
  final streaming = mode.startsWith('streaming');
  final Uint8List? input = mode.endsWith('decode')
      ? _encode(data, streaming: true)
      : null;
  final beforeRss = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  final Object? result;
  final String checksum;
  final int resultLength;
  if (input == null) {
    final encoded = _encode(data, streaming: streaming);
    result = encoded;
    resultLength = encoded.length;
    checksum = sha256.convert(encoded).toString();
  } else {
    result = _decode(input, streaming: streaming);
    if (!_sameValue(data, result)) {
      throw StateError('Synthetic data did not round trip');
    }
    resultLength = input.length;
    checksum = sha256.convert(input).toString();
  }
  watch.stop();
  // Keep input/output live through the measurement; do not force GC or infer
  // retained heap from RSS. Decode compares every synthetic field in place.
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'rows': rows,
      'detailChars': detail,
      'outputBytes': resultLength,
      'archiveSha256': checksum,
      'elapsedMs': watch.elapsedMilliseconds,
      'rssBeforeBytes': beforeRss,
      'rssAfterBytes': ProcessInfo.currentRss,
      'maxRssBytes': ProcessInfo.maxRss,
      'resultType': result.runtimeType.toString(),
    }),
  );
}
