import 'dart:convert';
import 'dart:math';

String generatePkceVerifier({Random? random}) {
  final secureRandom = random ?? Random.secure();
  final bytes = List<int>.generate(
    64,
    (_) => secureRandom.nextInt(256),
    growable: false,
  );
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String createPkceChallenge(String verifier) {
  if (verifier.length < 43 || verifier.length > 128) {
    throw ArgumentError('PKCE verifier must contain 43-128 characters');
  }
  return base64UrlEncode(_sha256(ascii.encode(verifier))).replaceAll('=', '');
}

String sha256HexBytes(List<int> input) =>
    _sha256(input).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

List<int> _sha256(List<int> input) {
  const initial = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  const constants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  final message = List<int>.from(input)..add(0x80);
  while (message.length % 64 != 56) {
    message.add(0);
  }
  final bitLength = input.length * 8;
  for (var shift = 56; shift >= 0; shift -= 8) {
    message.add((bitLength >> shift) & 0xff);
  }

  final hash = List<int>.from(initial);
  final words = List<int>.filled(64, 0);
  for (var offset = 0; offset < message.length; offset += 64) {
    for (var index = 0; index < 16; index++) {
      final base = offset + index * 4;
      words[index] =
          ((message[base] << 24) |
              (message[base + 1] << 16) |
              (message[base + 2] << 8) |
              message[base + 3]) &
          0xffffffff;
    }
    for (var index = 16; index < 64; index++) {
      final x = words[index - 15];
      final y = words[index - 2];
      final s0 = _rotateRight(x, 7) ^ _rotateRight(x, 18) ^ (x >> 3);
      final s1 = _rotateRight(y, 17) ^ _rotateRight(y, 19) ^ (y >> 10);
      words[index] =
          (words[index - 16] + s0 + words[index - 7] + s1) & 0xffffffff;
    }

    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];

    for (var index = 0; index < 64; index++) {
      final sum1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final choice = (e & f) ^ ((~e) & g);
      final temporary1 =
          (h + sum1 + choice + constants[index] + words[index]) & 0xffffffff;
      final sum0 =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temporary2 = (sum0 + majority) & 0xffffffff;

      h = g;
      g = f;
      f = e;
      e = (d + temporary1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) & 0xffffffff;
    }

    hash[0] = (hash[0] + a) & 0xffffffff;
    hash[1] = (hash[1] + b) & 0xffffffff;
    hash[2] = (hash[2] + c) & 0xffffffff;
    hash[3] = (hash[3] + d) & 0xffffffff;
    hash[4] = (hash[4] + e) & 0xffffffff;
    hash[5] = (hash[5] + f) & 0xffffffff;
    hash[6] = (hash[6] + g) & 0xffffffff;
    hash[7] = (hash[7] + h) & 0xffffffff;
  }

  return [
    for (final word in hash)
      for (final shift in const [24, 16, 8, 0]) (word >> shift) & 0xff,
  ];
}

int _rotateRight(int value, int count) =>
    ((value >> count) | (value << (32 - count))) & 0xffffffff;
