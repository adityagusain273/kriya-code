import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class LicenseVerifier {
  final BigInt modulus;
  final BigInt exponent;

  LicenseVerifier({required this.modulus, BigInt? exponent})
      : exponent = exponent ?? BigInt.from(65537);

  static const List<int> _sha256Asn1Header = [
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
    0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];

  bool verify(String keyString) {
    try {
      final clean = keyString.trim();
      final parts = clean.split('.');
      if (parts.length != 3 || parts[0] != 'BCODE') {
        return false;
      }
      final payloadBytes = base64Url.decode(base64.normalize(parts[1]));
      final sigBytes = base64Url.decode(base64.normalize(parts[2]));
      if (sigBytes.length != 256) return false;

      BigInt sigInt = BigInt.zero;
      for (final byte in sigBytes) {
        sigInt = (sigInt << 8) | BigInt.from(byte);
      }

      final emInt = sigInt.modPow(exponent, modulus);

      final emBytes = Uint8List(256);
      var temp = emInt;
      for (var i = 255; i >= 0; i--) {
        emBytes[i] = (temp & BigInt.from(0xff)).toInt();
        temp = temp >> 8;
      }

      if (emBytes[0] != 0x00 || emBytes[1] != 0x01) return false;

      var i = 2;
      while (i < 256 && emBytes[i] == 0xff) {
        i++;
      }
      if (i >= 256 || emBytes[i] != 0x00) return false;
      i++;

      if (256 - i != _sha256Asn1Header.length + 32) return false;

      for (var j = 0; j < _sha256Asn1Header.length; j++) {
        if (emBytes[i + j] != _sha256Asn1Header[j]) return false;
      }

      final expectedHash = sha256.convert(payloadBytes).bytes;
      for (var j = 0; j < 32; j++) {
        if (emBytes[i + _sha256Asn1Header.length + j] != expectedHash[j]) {
          return false;
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}

void main() {
  test('verifies valid RSA-2048 PKCS#1 v1.5 license key', () {
    final nHex = 'e630093dcd218577ed1a3bb36168635a18bd242cefd0ea5fd55920265dbae9b59c744cc3f5e1917708da88c9cf6c505164546405754bfb5c7036e9a30a28537f0b1b0d917c31347327a38aa631f84174b849d435f6328c10fadf0b8a37bb22dd2ae9a6f5a4f110ce213e21e41bd774da6b387f9a65d0741a112da40ece606c82d065a6a56fbf3329e02186ff2f7d0d1be2733328de81fd70f50ecb78c8f33d9644f1a866a0fc8a65d623c4551ec3bce75f472a63670e6e23c11e0a963a239f9f3d1702cb1072103a7476daf54d68ff287de63ead00d91e49c955610e631f0288272e84ff1c21e8badd83e7b132370e1b132a568913a76b5e95115215207c52bd';
    final sampleKey = 'BCODE.dXNlckBleGFtcGxlLmNvbTpwcm8.XJ5sakO0NVACBu1Y0-Q2BZTdlJ2w8DLWWIp1-DvyYvAYyVCVLrKCr7EIM2a-VHwIASbvmQjc33F4Fw6NvpGJBgWyUHz6tyZbrTLInFxzZAKSED0QMiTIFBOufzcPu2l6HGY5wPGWBH8CtI9F8t8alQqlt4K-PjOETTxvWHJo6tzxf25sxbguEmrWPaSsTtf11IKiS4FHowamyl81n0FLZeFzQ4ekvjdLsWeNIemqe1We8wND4WOsljKqVnSHFDTHQZ3SCx4yJwJvfAyTBbtozsLNJDnW-vS-o3yElFKYJfFPLOjqqBwBGM0nP3aKOwmxsFUVqn3ivmZ1xPikCey8jg';

    final verifier = LicenseVerifier(modulus: BigInt.parse(nHex, radix: 16));
    expect(verifier.verify(sampleKey), isTrue);

    // Tampered payload
    final tamperedKey = sampleKey.replaceFirst('dXNlck', 'ZZNlck');
    expect(verifier.verify(tamperedKey), isFalse);

    // Tampered signature
    final tamperedSig = '${sampleKey.substring(0, sampleKey.length - 2)}aa';
    expect(verifier.verify(tamperedSig), isFalse);

    // Garbage key
    expect(verifier.verify('BCODE.random.garbage'), isFalse);
    expect(verifier.verify(''), isFalse);
  });
}
