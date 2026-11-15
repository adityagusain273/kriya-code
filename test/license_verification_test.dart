import 'package:b_code/monetization/license_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LicenseVerifier', () {
    const generalKey =
        'BCODE.cHJvOnRlc3RAYmNvZGUuZGV2.nDrKf-Gmzu0BvXSHzMlS4PGd_ARgXRAMjn8OXiFO-P99-PIJDN0xtz794tmVtg22w-BnVofpwjA7r1J15Onx9BuquoHtGxoU-yjAZOY7vz7pyXj-KrSG6Y8PQ6sA7tBs5j_PRQNdbJyuxX--WXpZfsiUGnZUP5aMYyInx4IiCwqHwRgNuAhzUD8hOSUITI21EIdOwVGknGKFzErzYtPLoWjHVTU8SooALET62mKK8C0jbIzl_EscGSaQdi5SMw8FT0PUGRcSAniYfibDJz8rKZFstxfoAyX34kztL_hKif9ZeA9cMnlPL9iOFwj9tWIY0oME4v3sGezu64Z1UkYouQ';

    const deviceBoundKey =
        'BCODE.cHJvOkJDT0RFLUE4RjIzOTAx.5FeOMsl2yYY2N5vQsjqW0RQkm6ojCME-jmT6aUrxjh_4eyrrVEfJgSqBmN9wk97npoJOkv5e0lub3Zt-2o9v9OtgstqRAqHsu8jMQlGltzNFHWFWcfVXo9DRCQQugYuCRNSZ59qw_mzEpB6UMJ_lyJK1t5oSUQCOOCdPzy2fuicdzJZHTSEqI1b-qI5dtrAKpca6Ml9DwKMUc0PzwtwWbnpPSGuPX60clwjFlBnwAwJ8Hnd8vfqmJlj18RUWm3Yh4Saqts5pkhpPWHatH85ekkOHmvh8PA5hc70nWrpMbBGaGleg33PNhPPoDFF6tbqFUXbn-atcMSiUk6tXHisPeA';

    final verifier = LicenseVerifier();

    test('verifies valid non-device-locked license key on any device', () {
      final res = verifier.validate(generalKey, currentDeviceId: 'BCODE-ANY-DEVICE');
      expect(res.isValid, isTrue);
      expect(res.deviceId, 'test@bcode.dev');
    });

    test('verifies device-bound license key on the matching device', () {
      final res = verifier.validate(deviceBoundKey, currentDeviceId: 'BCODE-A8F23901');
      expect(res.isValid, isTrue);
      expect(res.deviceId, 'BCODE-A8F23901');
    });

    test('rejects device-bound license key on a different device', () {
      final res = verifier.validate(deviceBoundKey, currentDeviceId: 'BCODE-441188AA');
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('locked to device BCODE-A8F23901'));
    });

    test('rejects tampered payload', () {
      final tampered = deviceBoundKey.replaceFirst('cHJvOk', 'cHJvZZ');
      expect(verifier.verify(tampered), isFalse);
    });

    test('rejects tampered signature', () {
      final tampered = '${deviceBoundKey.substring(0, deviceBoundKey.length - 2)}aa';
      expect(verifier.verify(tampered), isFalse);
    });

    test('rejects malformed and empty keys', () {
      expect(verifier.verify(''), isFalse);
      expect(verifier.verify('BCODE.garbage'), isFalse);
      expect(verifier.verify('NOTBCODE.payload.sig'), isFalse);
    });
  });
}
