import 'dart:typed_data';

const _mask = 0xFFFFFFFF;
const _m = 0x5bd1e995;

/// 32-bit MurmurHash2 as used by CurseForge fingerprints.
int murmur2(Uint8List data, {int seed = 1}) {
  var length = data.length;
  var h = (seed ^ length) & _mask;
  var i = 0;
  while (length >= 4) {
    var k =
        data[i] |
        (data[i + 1] << 8) |
        (data[i + 2] << 16) |
        (data[i + 3] << 24);
    k = (k * _m) & _mask;
    k ^= k >>> 24;
    k = (k * _m) & _mask;
    h = (h * _m) & _mask;
    h ^= k;
    i += 4;
    length -= 4;
  }
  switch (length) {
    case 3:
      h ^= data[i + 2] << 16;
      h ^= data[i + 1] << 8;
      h ^= data[i];
      h = (h * _m) & _mask;
    case 2:
      h ^= data[i + 1] << 8;
      h ^= data[i];
      h = (h * _m) & _mask;
    case 1:
      h ^= data[i];
      h = (h * _m) & _mask;
  }
  h ^= h >>> 13;
  h = (h * _m) & _mask;
  h ^= h >>> 15;
  return h & _mask;
}

/// CurseForge file fingerprint: murmur2 over the file with whitespace bytes
/// (tab, LF, CR, space) removed.
int curseFileFingerprint(Uint8List data) {
  final out = Uint8List(data.length);
  var n = 0;
  for (final b in data) {
    if (b == 9 || b == 10 || b == 13 || b == 32) continue;
    out[n++] = b;
  }
  return murmur2(Uint8List.sublistView(out, 0, n));
}
