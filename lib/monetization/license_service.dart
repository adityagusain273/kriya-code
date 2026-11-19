import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class LicenseValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? deviceId;
  final DateTime? expiryDate;

  const LicenseValidationResult({
    required this.isValid,
    this.errorMessage,
    this.deviceId,
    this.expiryDate,
  });

  static const valid = LicenseValidationResult(isValid: true);
  static const invalid = LicenseValidationResult(
    isValid: false,
    errorMessage: 'Invalid or corrupted license key',
  );
}

class LicenseVerifier {
  static final BigInt defaultModulus = BigInt.parse(
    'ec84d02c9e3d5c35fc2e10bbe5ab8f5003c2866d1b4038a28fc09b7db0cd2e14'
    'fa82fd9f5ba4eac376a26f5f846b1e0ec86f7dd5f80bdd6f636dcab09578aeb1'
    '189bc0bd7f9158c1d74f9d741b161f961200ca79267f336ab8ce7fac9cfd9f84'
    '3517dc62b5b30f8feb88278f86b8e06ee73318f04a312a26c2a38aebd39a4918'
    'd6cf6ca01d0a42026ef8de7d4d8a972659abdaf86d543709029d5b6544aa9101'
    'ad1f5c23abcfd24dc29d06825f64fc4707b6cb55b8b7ec2eb3fec5eaae2037e2'
    '7f0bea60ac626301f527085d29d269307be10b39e2ddcfd89e22c0402d3783e2'
    '23330ca9dced72f9511560894659aeb84ffd13785a50db37ed1ec94b1ecb4f03',
    radix: 16,
  );
  static final BigInt defaultExponent = BigInt.from(65537);

  final BigInt modulus;
  final BigInt exponent;

  LicenseVerifier({BigInt? modulus, BigInt? exponent})
      : modulus = modulus ?? defaultModulus,
        exponent = exponent ?? defaultExponent;

  static const List<int> _sha256Asn1Header = [
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
    0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];

  LicenseValidationResult validate(String keyString, {String? currentDeviceId}) {
    try {
      final clean = keyString.replaceAll(RegExp(r'\s+'), '');
      final parts = clean.split('.');
      if (parts.length != 3 || parts[0] != 'BCODE') {
        return LicenseValidationResult.invalid;
      }
      final payloadBytes = base64Url.decode(base64.normalize(parts[1]));
      final sigBytes = base64Url.decode(base64.normalize(parts[2]));
      if (sigBytes.length != 256) return LicenseValidationResult.invalid;

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

      if (emBytes[0] != 0x00 || emBytes[1] != 0x01) return LicenseValidationResult.invalid;

      var i = 2;
      while (i < 256 && emBytes[i] == 0xff) {
        i++;
      }
      if (i >= 256 || emBytes[i] != 0x00) return LicenseValidationResult.invalid;
      i++;

      if (256 - i != _sha256Asn1Header.length + 32) return LicenseValidationResult.invalid;

      for (var j = 0; j < _sha256Asn1Header.length; j++) {
        if (emBytes[i + j] != _sha256Asn1Header[j]) return LicenseValidationResult.invalid;
      }

      final expectedHash = sha256.convert(payloadBytes).bytes;
      for (var j = 0; j < 32; j++) {
        if (emBytes[i + _sha256Asn1Header.length + j] != expectedHash[j]) {
          return LicenseValidationResult.invalid;
        }
      }

      final payload = utf8.decode(payloadBytes);
      String? boundId;
      DateTime? expiryDate;

      if (payload.startsWith('pro:')) {
        final body = payload.substring(4);
        final lastColon = body.lastIndexOf(':');
        if (lastColon != -1) {
          final epochSeconds = int.tryParse(body.substring(lastColon + 1));
          if (epochSeconds != null) {
            boundId = body.substring(0, lastColon);
            expiryDate = DateTime.fromMillisecondsSinceEpoch(
              epochSeconds * 1000,
              isUtc: true,
            );
          } else {
            boundId = body;
          }
        } else {
          boundId = body;
        }
      }

      if (boundId != null && boundId.startsWith('BCODE-')) {
        if (currentDeviceId != null && currentDeviceId.isNotEmpty) {
          if (boundId != currentDeviceId) {
            return LicenseValidationResult(
              isValid: false,
              errorMessage:
                  'This license key is locked to device $boundId and cannot be used on this phone.',
              deviceId: boundId,
              expiryDate: expiryDate,
            );
          }
        }
      }

      if (expiryDate != null && DateTime.now().isAfter(expiryDate)) {
        return LicenseValidationResult(
          isValid: false,
          deviceId: boundId,
          errorMessage:
              'Your 6-Month Semester Pass expired on ${expiryDate.toLocal().toString().split(" ")[0]}. Renew to continue enjoying Pro features.',
          expiryDate: expiryDate,
        );
      }

      return LicenseValidationResult(
        isValid: true,
        deviceId: boundId,
        expiryDate: expiryDate,
      );
    } catch (_) {
      return LicenseValidationResult.invalid;
    }
  }

  bool verify(String keyString, {String? currentDeviceId}) {
    return validate(keyString, currentDeviceId: currentDeviceId).isValid;
  }
}
