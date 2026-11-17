import 'package:local_auth/local_auth.dart';

/// Thin wrapper over [LocalAuthentication] for fingerprint/biometric unlock.
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Whether the device has biometric hardware that is enrolled and usable.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Prompts for biometric authentication. Returns true on success.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
