import 'package:b_code/monetization/license_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LicenseVerifier', () {
    const generalKey =
        'BCODE.cHJvOnRlc3RAYmNvZGUuZGV2.nDrKf-Gmzu0BvXSHzMlS4PGd_ARgXRAMjn8OXiFO-P99-PIJDN0xtz794tmVtg22w-BnVofpwjA7r1J15Onx9BuquoHtGxoU-yjAZOY7vz7pyXj-KrSG6Y8PQ6sA7tBs5j_PRQNdbJyuxX--WXpZfsiUGnZUP5aMYyInx4IiCwqHwRgNuAhzUD8hOSUITI21EIdOwVGknGKFzErzYtPLoWjHVTU8SooALET62mKK8C0jbIzl_EscGSaQdi5SMw8FT0PUGRcSAniYfibDJz8rKZFstxfoAyX34kztL_hKif9ZeA9cMnlPL9iOFwj9tWIY0oME4v3sGezu64Z1UkYouQ';

    const deviceBoundKey =
        'BCODE.cHJvOkJDT0RFLUE4RjIzOTAx.5FeOMsl2yYY2N5vQsjqW0RQkm6ojCME-jmT6aUrxjh_4eyrrVEfJgSqBmN9wk97npoJOkv5e0lub3Zt-2o9v9OtgstqRAqHsu8jMQlGltzNFHWFWcfVXo9DRCQQugYuCRNSZ59qw_mzEpB6UMJ_lyJK1t5oSUQCOOCdPzy2fuicdzJZHTSEqI1b-qI5dtrAKpca6Ml9DwKMUc0PzwtwWbnpPSGuPX60clwjFlBnwAwJ8Hnd8vfqmJlj18RUWm3Yh4Saqts5pkhpPWHatH85ekkOHmvh8PA5hc70nWrpMbBGaGleg33PNhPPoDFF6tbqFUXbn-atcMSiUk6tXHisPeA';

    const unexpiredSemesterKey =
        'BCODE.cHJvOkJDT0RFLVZBTElEMDAxOjI1MDAwMDAwMDA.yx5pr6hWTFvK8lvWISXqpKv42RmzWjWtVxYd0APvo4upBvrI-bmSNSlSFs_nkNIBfLG21qAM_euOwnvduD92FkSfzNSKKmHHoRKxON_cj4s2vozgcryOzqIf_QjcvfotQA2LJ-nvLVjdOaGFq-y-SqXf52BBMt3tKbHWkux3BqV1E_gY7S5ZBYy5j-UmLKZrPdz1z016GrKW-PIWvdJ4RObKPa4b2Gyk_kYZlI640VTABt9lZPjFPTjc0sqBAI241s1_WA4mEb6DqNw7FmtbbgFEDRY_tNjT1yVkOnJ6eYz2q8va4SL7l1tbAC7-kIEg1rXxRZbWUBkvRiBObahFEA';

    const expiredSemesterKey =
        'BCODE.cHJvOkJDT0RFLUVYUElSRUQxOjE2MDAwMDAwMDA.5uS1iuh0a2fsOhjd7NNRkduzvPGdiWLESRf63CtZe3YkXEsidCeNDwUDSdTszmg7W1ZYObif_vDWxw9_HScmHnAQ4Zxmq0WtByq3uzUuJjv-R2RBFayXvFrzFbOt6RPkXJ742dJIllvwc3ShFIe3WiTX9rpvjbhmTmrcuh7zNttGdH1U3WtF1Qud3mMqIt8PXitDVZMo-WamGE6k-MlnwOoDdrY7ROKfGewflN6HEIHG48WKOcT9mgr_iNsjKAfWkUO2dDDd4bkc6E9Pmy97sHNmo-CCGNnfAiigQYidyO_5QmQQletNjjiWaYeczT9EsZQH9nQbF2M9bXQ4PZZFdg';

    const lifetimePassKey =
        'BCODE.cHJvOkJDT0RFLUxJRkVUSU1F.WmuD9O74I2gJRl8zDjNl-O_NabWUemxAU63mhuDg25n-O1hhblFPoNqammCSBdSgAq9aS5G-DAE7bln7EgQozKV9r2_A5c7fzkouV7oPYQeTjRu6w0MkGdRolk9kD1LdpwIy70dBop7UccVyviB7imoxCPQfMum20aKhp_q6ICwCIwdiMnHNHUK04Q-KRoDHu0gjfoT9FUoXzkMzxOBbBjbxlWfHHi8_qtNDbfHC0_IY6FcQBjoAapkmp2i4PY95m2_wvjjejRMFS9CzlPQTjs9g2oyo3B_jqYNrzHmPt8mHyGCaI1AHMpWdqsvAxDQq6E8wC84RD51UbIwW4jdkXA';

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

    test('verifies unexpired 6-month semester pass license key', () {
      final res = verifier.validate(unexpiredSemesterKey, currentDeviceId: 'BCODE-VALID001');
      expect(res.isValid, isTrue);
      expect(res.deviceId, 'BCODE-VALID001');
      expect(res.expiryDate, DateTime.fromMillisecondsSinceEpoch(2500000000 * 1000, isUtc: true));
      expect(res.errorMessage, isNull);
    });

    test('rejects expired 6-month semester pass and verifies error message', () {
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(1600000000 * 1000, isUtc: true);
      final formattedDate = expiryDate.toLocal().toString().split(' ')[0];
      final res = verifier.validate(expiredSemesterKey, currentDeviceId: 'BCODE-EXPIRED1');
      expect(res.isValid, isFalse);
      expect(res.deviceId, 'BCODE-EXPIRED1');
      expect(res.expiryDate, expiryDate);
      expect(
        res.errorMessage,
        'Your 6-Month Semester Pass expired on $formattedDate. Renew to continue enjoying Pro features.',
      );
    });

    test('verifies backward-compatible lifetime pass without expiry', () {
      final res = verifier.validate(lifetimePassKey, currentDeviceId: 'BCODE-LIFETIME');
      expect(res.isValid, isTrue);
      expect(res.deviceId, 'BCODE-LIFETIME');
      expect(res.expiryDate, isNull);
      expect(res.errorMessage, isNull);
    });
  });
}
