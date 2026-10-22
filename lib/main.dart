import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const ChamCongApp());

const ink = Color(0xFF162B49);
const blue = Color(0xFF3468F5);
const pale = Color(0xFFF4F7FC);
// Android emulator reaches the host computer through 10.0.2.2.
const apiBase = 'http://10.0.2.2:54512/api';
const _nfcChannel = MethodChannel('chamcong/nfc');
const _avatarChannel = MethodChannel('chamcong/avatar');
const _biometricChannel = MethodChannel('chamcong/biometrics');
const _locationChannel = MethodChannel('chamcong/location');
const _officeAttendanceCode = 'CHAMCONG:OFFICE-01';

Future<bool> _biometricTypeAvailable(
    LocalAuthentication auth, BiometricType type) async {
  final enrolled = await auth.getAvailableBiometrics();
  if (enrolled.contains(type)) return true;
  // Android's local_auth_android reports only biometric strength classes
  // (strong/weak), not the modality. Combine that with the device feature.
  try {
    final hardware = await _biometricChannel
        .invokeMapMethod<String, bool>('hardwareCapabilities');
    final modality = type == BiometricType.face ? 'face' : 'fingerprint';
    final anyEnrolled = enrolled.contains(BiometricType.strong) ||
        enrolled.contains(BiometricType.weak);
    return hardware?[modality] == true && anyEnrolled;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

Widget _accountAvatar(String? image, {double radius = 24}) {
  if (image == null || image.isEmpty) {
    return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE8EDFF),
        child: Icon(Icons.person_outline, color: blue, size: radius));
  }
  try {
    return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE8EDFF),
        child: ClipOval(
            child: Image.memory(base64Decode(image),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.person_outline, color: blue, size: radius))));
  } catch (_) {
    return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE8EDFF),
        child: Icon(Icons.person_outline, color: blue, size: radius));
  }
}

Future<String?> _pickAvatar() => _avatarChannel.invokeMethod<String>('pick');

String _apiError(String body, String fallback) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      if (decoded['message'] is String) {
        final message = decoded['message'] as String;
        final details = decoded['details'];
        if (details is String && details.trim().isNotEmpty) {
          return '$message\nChi tiết SQL: ${details.trim()}';
        }
        return message;
      }
      final errors = decoded['errors'];
      if (errors is Map<String, dynamic>) {
        final messages = errors.values
            .whereType<List<dynamic>>()
            .expand((items) => items)
            .whereType<String>()
            .toSet();
        if (messages.isNotEmpty) return messages.join('\n');
      }
      if (decoded['title'] is String) return decoded['title'] as String;
    }
  } catch (_) {}
  return fallback;
}

String _displayError(Object error) =>
    error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

String? _coordinateLabel(dynamic latitude, dynamic longitude) {
  if (latitude is! num || longitude is! num) return null;
  return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

String _weatherDescription(int code) => switch (code) {
      0 => 'Trời quang',
      1 => 'Ít mây',
      2 => 'Có mây từng đợt',
      3 => 'Nhiều mây',
      45 || 48 => 'Có sương mù',
      51 || 53 || 55 || 56 || 57 => 'Mưa phùn',
      61 || 63 || 65 || 66 || 67 => 'Có mưa',
      71 || 73 || 75 || 77 => 'Có tuyết',
      80 || 81 || 82 => 'Mưa rào',
      85 || 86 => 'Mưa tuyết',
      95 || 96 || 99 => 'Dông',
      _ => 'Chưa rõ thời tiết',
    };

String _otpStatusMessage(Map<String, dynamic> data, String fallback) {
  final message = data['message'] as String? ?? fallback;
  return message;
}

class ChamCongApp extends StatelessWidget {
  const ChamCongApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'VoTruongKha',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: pale,
          colorScheme: ColorScheme.fromSeed(seedColor: blue),
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
              backgroundColor: pale,
              foregroundColor: ink,
              centerTitle: false,
              elevation: 0,
              scrolledUnderElevation: 0),
          cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFE9EDF5)))),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF8FAFD),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE5EAF2))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE5EAF2))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: blue, width: 1.5))),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700))),
          navigationBarTheme: NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xFFE8EDFF),
              elevation: 8),
        ),
        home: const AuthGate(),
      );
}

class _Employee {
  const _Employee(
      {required this.id,
      required this.username,
      required this.email,
      required this.displayName,
      required this.department,
      required this.role,
      this.avatarBase64});
  final String id, username, email, displayName, department, role;
  final String? avatarBase64;
  factory _Employee.fromJson(Map<String, dynamic> json) => _Employee(
        id: json['id'] as String,
        username: json['username'] as String,
        email: json['email'] as String? ?? '',
        displayName: json['displayName'] as String,
        department: json['department'] as String,
        role: json['role'] as String,
        avatarBase64: json['avatarBase64'] as String?,
      );
}

class _Session {
  const _Session(this.token, this.employee);
  final String token;
  final _Employee employee;
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _Session? session;
  bool loading = true;
  bool biometricAvailable = false;
  bool supportsFaceLogin = false;
  bool supportsFingerprintLogin = false;
  bool biometricSetupRequired = false;
  _Session? pendingBiometricSession;
  String biometricSetupMessage = '';

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final auth = LocalAuthentication();
      supportsFaceLogin =
          await _biometricTypeAvailable(auth, BiometricType.face);
      supportsFingerprintLogin =
          await _biometricTypeAvailable(auth, BiometricType.fingerprint);
    } catch (_) {}
    final biometricToken = prefs.getString('biometric_token');
    final biometricEnabled = prefs.getBool('biometric_enabled') == true;
    biometricSetupRequired = prefs.getBool('biometric_setup_required') == true;
    // A biometric-enabled account must go through the email-first biometric
    // form; don't silently restore its saved session on app launch.
    final token = biometricEnabled ? null : prefs.getString('auth_token');
    biometricAvailable = biometricToken != null;
    if (token != null) {
      try {
        if (biometricEnabled) {
          final authenticated = await LocalAuthentication().authenticate(
            localizedReason: 'Xác thực để mở ứng dụng chấm công',
            options: const AuthenticationOptions(biometricOnly: true),
          );
          // Canceling biometric unlock must not erase a valid saved session.
          if (!authenticated) {
            if (mounted) setState(() => loading = false);
            return;
          }
        }
        final response = await http.get(Uri.parse('$apiBase/employees/me'),
            headers: {
              'Authorization': 'Bearer $token'
            }).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final employee = _Employee.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>);
          if (mounted)
            setState(() {
              session = _Session(token, employee);
              if (biometricSetupRequired) {
                pendingBiometricSession = session;
              }
              loading = false;
            });
          return;
        }
        // Only discard a token when the server explicitly rejects it. A network
        // timeout or server outage should not sign the user out permanently.
        if (response.statusCode == 401 || response.statusCode == 403) {
          await prefs.remove('auth_token');
          await prefs.remove('biometric_token');
          await prefs.setBool('biometric_enabled', false);
          biometricAvailable = false;
        }
      } catch (_) {
        // Keep saved credentials when the API is temporarily unreachable.
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _signedIn(_Session value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', value.token);
    await prefs.setBool('biometric_setup_required', true);
    if (mounted) setState(() => session = value);
    try {
      final auth = LocalAuthentication();
      supportsFaceLogin =
          await _biometricTypeAvailable(auth, BiometricType.face);
      supportsFingerprintLogin =
          await _biometricTypeAvailable(auth, BiometricType.fingerprint);
      if (await auth.isDeviceSupported() &&
          (supportsFaceLogin || supportsFingerprintLogin)) {
        final enable = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('Bật đăng nhập bằng sinh trắc học?'),
                  content: const Text(
                      'Dùng khuôn mặt hoặc vân tay đã đăng ký trên điện thoại để đăng nhập lần sau.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Để sau')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Bật sinh trắc học'))
                  ],
                ));
        if (enable == true &&
            await auth.authenticate(
                localizedReason: 'Xác nhận bật đăng nhập nhanh',
                options: const AuthenticationOptions(biometricOnly: true))) {
          await prefs.setString('biometric_token', value.token);
          await prefs.setBool('biometric_enabled', true);
          if (mounted) setState(() => biometricAvailable = true);
        }
      }
    } catch (_) {}
  }

  Future<void> _registered(_Session value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', value.token);
    var hasFace = false;
    var hasFingerprint = false;
    try {
      final auth = LocalAuthentication();
      if (await auth.isDeviceSupported()) {
        hasFace = await _biometricTypeAvailable(auth, BiometricType.face);
        hasFingerprint =
            await _biometricTypeAvailable(auth, BiometricType.fingerprint);
      }
    } catch (_) {
      // If capability detection fails, allow the user to continue manually.
    }
    if (!hasFace && !hasFingerprint) {
      await prefs.setBool('biometric_setup_required', false);
      if (!mounted) return;
      setState(() {
        session = value;
        pendingBiometricSession = null;
        biometricSetupRequired = false;
        supportsFaceLogin = false;
        supportsFingerprintLogin = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      pendingBiometricSession = value;
      biometricSetupRequired = true;
      biometricSetupMessage = '';
      supportsFaceLogin = hasFace;
      supportsFingerprintLogin = hasFingerprint;
    });
  }

  Future<void> _continueWithoutBiometrics() async {
    final value = pendingBiometricSession ?? session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_setup_required', false);
    if (!mounted) return;
    setState(() {
      session = value;
      pendingBiometricSession = null;
      biometricSetupRequired = false;
      biometricSetupMessage = '';
    });
  }

  Future<void> _finishBiometricSetup() async {
    final auth = LocalAuthentication();
    try {
      final hasFace = await _biometricTypeAvailable(auth, BiometricType.face);
      final hasFingerprint =
          await _biometricTypeAvailable(auth, BiometricType.fingerprint);
      if (!hasFace && !hasFingerprint) {
        await _continueWithoutBiometrics();
        return;
      }
      final verified = await auth.authenticate(
        localizedReason: 'Xác nhận sinh trắc học để bật đăng nhập và chấm công',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (!verified) return;
      final value = pendingBiometricSession;
      if (value == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('biometric_token', value.token);
      await prefs.setBool('biometric_enabled', true);
      await prefs.setBool('biometric_setup_required', false);
      if (mounted) {
        setState(() {
          supportsFaceLogin = hasFace;
          supportsFingerprintLogin = hasFingerprint;
          biometricAvailable = true;
          biometricSetupRequired = false;
          pendingBiometricSession = null;
          session = value;
        });
      }
    } catch (error) {
      if (mounted)
        setState(() => biometricSetupMessage =
            'Không thể xác thực sinh trắc học: ${_displayError(error)}');
    }
  }

  Future<void> _signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('biometric_token');
    await prefs.setBool('biometric_enabled', false);
    await prefs.setBool('biometric_setup_required', false);
    if (mounted)
      setState(() {
        session = null;
        biometricAvailable = false;
        biometricSetupRequired = false;
        pendingBiometricSession = null;
      });
    // Profile and history are pushed routes above AuthGate's home route. Clear
    // that route stack as well, otherwise the old page stays visible after the
    // session has already been signed out.
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (biometricSetupRequired) {
      return _BiometricSetupPage(
        message: biometricSetupMessage,
        onCheckAgain: _finishBiometricSetup,
        onContinueManually: _continueWithoutBiometrics,
        onLogout: _signOut,
      );
    }
    final current = session;
    if (current == null) {
      return AuthPage(
          onAuthenticated: _signedIn,
          onRegistered: _registered,
          onBiometricLogin: _biometricLogin,
          biometricAvailable: biometricAvailable,
          supportsFaceLogin: supportsFaceLogin,
          supportsFingerprintLogin: supportsFingerprintLogin);
    }
    if (current.employee.role.toLowerCase() == 'admin') {
      return AdminHome(session: current, onLogout: _signOut);
    }
    if (current.employee.role.toLowerCase() == 'employee') {
      return AttendanceHome(session: current, onLogout: _signOut);
    }
    return RoleHome(session: current, onLogout: _signOut);
  }

  Future<void> _biometricLogin(String email, bool useFace) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('biometric_token');
    try {
      final auth = LocalAuthentication();
      final normalizedEmail = email.trim().toLowerCase();
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
        await _showBiometricNotice(
            'Hãy nhập email tài khoản vào ô đăng nhập trước khi dùng sinh trắc học.');
        return;
      }
      final supported = await _biometricTypeAvailable(
          auth, useFace ? BiometricType.face : BiometricType.fingerprint);
      if (!await auth.isDeviceSupported() || !supported) {
        await _showBiometricNotice(
            'Thiết bị của bạn không hỗ trợ chức năng ${useFace ? 'đăng nhập bằng khuôn mặt' : 'đăng nhập bằng vân tay'}.');
        return;
      }
      if (token == null) {
        await _showBiometricNotice(
            'Tài khoản chưa bật đăng nhập sinh trắc học. Hãy đăng nhập bằng mật khẩu và OTP trước để thiết lập.');
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: useFace
            ? 'Xác thực khuôn mặt để đăng nhập tài khoản $normalizedEmail'
            : 'Xác thực vân tay để đăng nhập tài khoản $normalizedEmail',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (!ok) return;
      final response = await http.get(Uri.parse('$apiBase/employees/me'),
          headers: {
            'Authorization': 'Bearer $token'
          }).timeout(const Duration(seconds: 5));
      if (response.statusCode == 401 || response.statusCode == 403) {
        await prefs.remove('biometric_token');
        await prefs.remove('auth_token');
        await prefs.setBool('biometric_enabled', false);
        if (mounted) setState(() => biometricAvailable = false);
        throw Exception('Phiên đăng nhập đã hết hạn.');
      }
      if (response.statusCode != 200)
        throw Exception('Không kết nối được máy chủ.');
      final employee = _Employee.fromJson(jsonDecode(response.body));
      if (employee.email.toLowerCase() != normalizedEmail) {
        await _showBiometricNotice(
            'Email này không khớp với tài khoản đã bật đăng nhập sinh trắc học trên thiết bị.');
        return;
      }
      await prefs.setString('auth_token', token);
      if (mounted) setState(() => session = _Session(token, employee));
    } catch (error) {
      if (mounted) {
        await _showBiometricNotice(
            'Không thể đăng nhập sinh trắc học: ${_displayError(error)}');
      }
    }
  }

  Future<void> _showBiometricNotice(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thông báo thiết bị'),
        content: Text(message),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đã hiểu')),
        ],
      ),
    );
  }
}

class _BiometricSetupPage extends StatelessWidget {
  const _BiometricSetupPage(
      {required this.message,
      required this.onCheckAgain,
      required this.onContinueManually,
      required this.onLogout});
  final String message;
  final VoidCallback onCheckAgain;
  final VoidCallback onContinueManually;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Thiết lập sinh trắc học'),
          actions: [
            IconButton(onPressed: onLogout, icon: const Icon(Icons.logout))
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 38,
                      backgroundColor: Color(0xFFE8EDFF),
                      child: Icon(Icons.verified_user_outlined,
                          color: blue, size: 40),
                    ),
                    const SizedBox(height: 18),
                    const Text('Hoàn tất bảo mật tài khoản',
                        style: TextStyle(
                            color: ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    const Text(
                      'Sau khi đăng ký, hãy thiết lập khuôn mặt hoặc vân tay trên thiết bị để bật đăng nhập sinh trắc học. Thiết bị có hỗ trợ khuôn mặt có thể dùng khuôn mặt để đăng nhập và chấm công.',
                      textAlign: TextAlign.center,
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(message,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onCheckAgain,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Kiểm tra lại và bật'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onContinueManually,
                      child: const Text('Tiếp tục chấm công thủ công'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Đăng xuất'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class AuthPage extends StatefulWidget {
  const AuthPage(
      {super.key,
      required this.onAuthenticated,
      required this.onRegistered,
      required this.onBiometricLogin,
      required this.biometricAvailable,
      required this.supportsFaceLogin,
      required this.supportsFingerprintLogin});
  final ValueChanged<_Session> onAuthenticated;
  final ValueChanged<_Session> onRegistered;
  final void Function(String email, bool useFace) onBiometricLogin;
  final bool biometricAvailable;
  final bool supportsFaceLogin;
  final bool supportsFingerprintLogin;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  final email = TextEditingController();
  final otp = TextEditingController();
  final confirmPassword = TextEditingController();
  final displayName = TextEditingController();
  final department = TextEditingController(text: 'Chưa phân công');
  final adminCode = TextEditingController();
  bool registering = false, busy = false;
  String registrationRole = 'Employee';
  String? avatarBase64;
  String step = 'credentials';
  String? maskedEmail;
  String message = '';
  bool messageIsError = false;

  Future<void> submit() async {
    if ((step == 'verifyEmail' ||
            step == 'verifyLoginOtp' ||
            step == 'verifyRegistrationRole' ||
            step == 'resetPassword') &&
        !RegExp(r'^\d{6}$').hasMatch(otp.text.trim())) {
      setState(() {
        message = 'Vui lòng nhập đủ mã OTP gồm 6 chữ số.';
        messageIsError = true;
      });
      return;
    }
    if (step == 'requestPasswordReset' &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) {
      setState(() {
        message = 'Vui lòng nhập email hợp lệ đã đăng ký.';
        messageIsError = true;
      });
      return;
    }
    if (step == 'resetPassword') {
      final validationMessage = password.text.length < 8
          ? 'Mật khẩu mới cần ít nhất 8 ký tự.'
          : password.text != confirmPassword.text
              ? 'Mật khẩu xác nhận không khớp.'
              : null;
      if (validationMessage != null) {
        setState(() {
          message = validationMessage;
          messageIsError = true;
        });
        return;
      }
    }
    if (step == 'credentials' &&
        registering &&
        registrationRole == 'Admin' &&
        !RegExp(r'^\d{6}$').hasMatch(adminCode.text.trim())) {
      setState(() {
        message = 'Để đăng ký Admin, hãy nhập đúng mã Admin gồm 6 chữ số.';
        messageIsError = true;
      });
      return;
    }
    if (step == 'credentials' && registering) {
      final user = username.text.trim();
      final mail = email.text.trim();
      final name = displayName.text.trim();
      final validationMessage = user.length < 3
          ? 'Tên đăng nhập cần ít nhất 3 ký tự.'
          : !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)
              ? 'Vui lòng nhập địa chỉ email hợp lệ.'
              : name.isEmpty
                  ? 'Vui lòng nhập họ và tên.'
                  : avatarBase64 == null
                      ? 'Vui lòng chọn ảnh đại diện.'
                      : password.text.length < 8
                          ? 'Mật khẩu cần ít nhất 8 ký tự.'
                          : null;
      if (validationMessage != null) {
        setState(() {
          message = validationMessage;
          messageIsError = true;
        });
        return;
      }
    }
    setState(() {
      busy = true;
      message = '';
      messageIsError = false;
    });
    try {
      String endpoint;
      Map<String, String> body;
      if (step == 'verifyEmail' ||
          step == 'verifyLoginOtp' ||
          step == 'verifyRegistrationRole') {
        endpoint = step == 'verifyEmail'
            ? 'verify-email'
            : step == 'verifyRegistrationRole'
                ? 'verify-registration-role'
                : 'verify-login-otp';
        body = {'username': username.text.trim(), 'code': otp.text.trim()};
      } else if (step == 'requestPasswordReset') {
        endpoint = 'forgot-password';
        body = {'email': email.text.trim()};
      } else if (step == 'resetPassword') {
        endpoint = 'reset-password';
        body = {
          'email': email.text.trim(),
          'code': otp.text.trim(),
          'newPassword': password.text
        };
      } else {
        endpoint = registering ? 'register' : 'login';
        body = {'username': username.text.trim(), 'password': password.text};
        if (registering) {
          body['email'] = email.text.trim();
          body['displayName'] = displayName.text.trim();
          body['department'] = department.text.trim();
          body['role'] = registrationRole;
          body['avatarBase64'] = avatarBase64!;
          if (registrationRole == 'Admin') {
            body['adminCode'] = adminCode.text.trim();
          }
        }
      }
      final response = await http
          .post(Uri.parse('$apiBase/auth/$endpoint'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      Map<String, dynamic>? decodedResponse;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) decodedResponse = decoded;
      } on FormatException {
        // Development servers can return an HTML/text error page on an
        // unhandled exception. Keep the useful API fallback below instead of
        // showing a JSON decoder FormatException to the user.
      }
      final data = decodedResponse ?? <String, dynamic>{};
      final serverMessage = data['message'] as String? ?? '';
      if (registering &&
          endpoint == 'register' &&
          response.statusCode == 409 &&
          serverMessage.toLowerCase().contains('email')) {
        final continueWithSelectedRole = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Email đã được đăng ký'),
            content: Text(
                '$serverMessage\n\nNếu tiếp tục, tài khoản đang dùng email này sẽ được chuyển sang vai trò bạn đang chọn: ${registrationRole == 'Admin' ? 'Admin' : 'Nhân viên'}. Mã OTP gửi về email sẽ xác nhận việc này. Mật khẩu và dữ liệu hiện có của tài khoản vẫn được giữ nguyên.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Đổi email')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Tiếp tục với vai trò đã chọn')),
            ],
          ),
        );
        if (!mounted) return;
        if (continueWithSelectedRole == true) {
          final continueResponse = await http
              .post(Uri.parse('$apiBase/auth/continue-registration'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'email': email.text.trim(),
                    'role': registrationRole,
                    if (registrationRole == 'Admin')
                      'adminCode': adminCode.text.trim(),
                  }))
              .timeout(const Duration(seconds: 10));
          final continueData =
              jsonDecode(continueResponse.body) as Map<String, dynamic>;
          if (continueResponse.statusCode >= 300) {
            throw Exception(_apiError(
                continueResponse.body, 'Không thể tiếp tục đăng ký.'));
          }
          username.text = email.text.trim();
          setState(() {
            step = 'verifyRegistrationRole';
            maskedEmail = continueData['email'] as String?;
            otp.clear();
            message =
                _otpStatusMessage(continueData, 'Đã gửi OTP xác nhận vai trò.');
            messageIsError = false;
          });
        } else {
          setState(() {
            message = 'Hãy nhập một email khác để đăng ký.';
            messageIsError = false;
          });
        }
        return;
      }
      if (response.statusCode >= 300) {
        throw Exception(_apiError(
            response.body,
            serverMessage.isNotEmpty
                ? serverMessage
                : registering
                    ? 'Không thể đăng ký. Hãy kiểm tra kết nối API và SQL Server.'
                    : 'Không thể đăng nhập.'));
      }
      if (decodedResponse == null) {
        throw Exception('Máy chủ trả về dữ liệu không hợp lệ. Hãy thử lại.');
      }
      if (data['token'] is String) {
        final returnedEmployee =
            _Employee.fromJson(data['employee'] as Map<String, dynamic>);
        if ((step == 'verifyEmail' || step == 'verifyRegistrationRole') &&
            registering &&
            returnedEmployee.role.toLowerCase() !=
                registrationRole.toLowerCase()) {
          throw Exception(
              'Backend trả về vai trò ${returnedEmployee.role}, khác vai trò $registrationRole vừa đăng ký. Tài khoản chưa được nâng quyền. Hãy dùng email mới hoặc nhờ Admin hiện tại đổi vai trò trong màn Quản lý tài khoản.');
        }
        final value = _Session(data['token'] as String, returnedEmployee);
        if (step == 'verifyEmail') {
          widget.onRegistered(value);
        } else {
          widget.onAuthenticated(value);
        }
      } else if (step == 'verifyEmail') {
        setState(() {
          step = 'credentials';
          registering = false;
          otp.clear();
          message = 'Email đã xác minh. Hãy đăng nhập để tiếp tục.';
          messageIsError = false;
        });
      } else if (step == 'verifyLoginOtp') {
        widget.onAuthenticated(_Session(data['token'] as String,
            _Employee.fromJson(data['employee'] as Map<String, dynamic>)));
      } else if (step == 'requestPasswordReset') {
        setState(() {
          step = 'resetPassword';
          maskedEmail = email.text.trim();
          otp.clear();
          password.clear();
          confirmPassword.clear();
          message =
              'Nếu email thuộc tài khoản đã xác minh, mã khôi phục sẽ được gửi đến hộp thư.';
          messageIsError = false;
        });
      } else if (step == 'resetPassword') {
        setState(() {
          step = 'credentials';
          registering = false;
          email.clear();
          otp.clear();
          password.clear();
          confirmPassword.clear();
          message = 'Đã đổi mật khẩu. Hãy đăng nhập bằng mật khẩu mới.';
          messageIsError = false;
        });
      } else {
        setState(() {
          step = data['requiresEmailVerification'] == true
              ? 'verifyEmail'
              : 'verifyLoginOtp';
          maskedEmail = data['email'] as String?;
          message = _otpStatusMessage(data, 'Đã gửi mã OTP qua email.');
          messageIsError = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          message = _displayError(error);
          messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resendCode() async {
    setState(() {
      busy = true;
      message = '';
      messageIsError = false;
    });
    try {
      final endpoint = step == 'verifyEmail'
          ? 'resend-email-verification'
          : step == 'verifyRegistrationRole'
              ? 'continue-registration'
              : step == 'resetPassword'
                  ? 'forgot-password'
                  : 'login';
      final body = step == 'verifyRegistrationRole'
          ? {
              'email': email.text.trim(),
              'role': registrationRole,
              if (registrationRole == 'Admin')
                'adminCode': adminCode.text.trim(),
            }
          : step == 'resetPassword'
              ? {'email': email.text.trim()}
              : {'username': username.text.trim(), 'password': password.text};
      final response = await http
          .post(Uri.parse('$apiBase/auth/$endpoint'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 300)
        throw Exception(_apiError(response.body, 'Không gửi được OTP.'));
      if (step == 'verifyLoginOtp' &&
          data['requiresEmailVerification'] == true) {
        setState(() => step = 'verifyEmail');
      }
      setState(() {
        maskedEmail = data['email'] as String? ?? maskedEmail;
        message = _otpStatusMessage(data, 'Đã gửi lại mã.');
        messageIsError = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          message = _displayError(error);
          messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    email.dispose();
    otp.dispose();
    confirmPassword.dispose();
    displayName.dispose();
    department.dispose();
    adminCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF7F9FF), Color(0xFFE8EEFF)])),
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Card(
                            elevation: 8,
                            shadowColor: const Color(0x14162B49),
                            color: Colors.white,
                            child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(28, 30, 28, 26),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                          width: 58,
                                          height: 58,
                                          margin:
                                              const EdgeInsets.only(bottom: 14),
                                          decoration: BoxDecoration(
                                              color: const Color(0xFFEAF0FF),
                                              borderRadius:
                                                  BorderRadius.circular(18)),
                                          child: const Icon(
                                              Icons.access_time_filled,
                                              color: blue,
                                              size: 30)),
                                      const Text('CHẤM CÔNG NHÂN VIÊN',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: blue,
                                              fontSize: 11,
                                              letterSpacing: 1.2,
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 8),
                                      Text(
                                          step != 'credentials'
                                              ? (step == 'verifyEmail'
                                                  ? 'Xác minh email'
                                                  : step ==
                                                          'verifyRegistrationRole'
                                                      ? 'Xác nhận vai trò'
                                                      : step == 'verifyLoginOtp'
                                                          ? 'Xác minh OTP đăng nhập'
                                                          : step ==
                                                                  'requestPasswordReset'
                                                              ? 'Khôi phục mật khẩu'
                                                              : 'Đặt lại mật khẩu')
                                              : registering
                                                  ? registrationRole == 'Admin'
                                                      ? 'Tạo tài khoản Admin'
                                                      : 'Tạo tài khoản nhân viên'
                                                  : 'Đăng nhập chấm công',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: ink)),
                                      const SizedBox(height: 22),
                                      const SizedBox(height: 16),
                                      if (step == 'credentials' &&
                                          registering) ...[
                                        Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              _accountAvatar(avatarBase64,
                                                  radius: 34),
                                              const SizedBox(width: 14),
                                              TextButton.icon(
                                                  onPressed: busy
                                                      ? null
                                                      : () async {
                                                          try {
                                                            final image =
                                                                await _pickAvatar();
                                                            if (image != null &&
                                                                mounted) {
                                                              setState(() =>
                                                                  avatarBase64 =
                                                                      image);
                                                            }
                                                          } catch (error) {
                                                            if (mounted) {
                                                              setState(() {
                                                                message =
                                                                    'Không chọn được ảnh: ${_displayError(error)}';
                                                                messageIsError =
                                                                    true;
                                                              });
                                                            }
                                                          }
                                                        },
                                                  icon: const Icon(Icons
                                                      .add_a_photo_outlined),
                                                  label: Text(avatarBase64 ==
                                                          null
                                                      ? 'Chọn ảnh đại diện *'
                                                      : 'Đổi ảnh đại diện'))
                                            ]),
                                        TextField(
                                            controller: displayName,
                                            decoration: const InputDecoration(
                                                labelText: 'Họ và tên',
                                                prefixIcon: Icon(
                                                    Icons.person_outline))),
                                        TextField(
                                            controller: department,
                                            decoration: const InputDecoration(
                                                labelText: 'Phòng ban',
                                                prefixIcon: Icon(
                                                    Icons.business_outlined))),
                                        DropdownButtonFormField<String>(
                                          initialValue: registrationRole,
                                          decoration: const InputDecoration(
                                            labelText: 'Vai trò tài khoản',
                                            prefixIcon:
                                                Icon(Icons.badge_outlined),
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'Employee',
                                              child: Text('Nhân viên'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'Admin',
                                              child: Text('Admin'),
                                            ),
                                          ],
                                          onChanged: busy
                                              ? null
                                              : (value) {
                                                  if (value == null) return;
                                                  setState(() {
                                                    registrationRole = value;
                                                    message = '';
                                                  });
                                                },
                                        ),
                                        if (registrationRole == 'Admin') ...[
                                          TextField(
                                            controller: adminCode,
                                            obscureText: true,
                                            keyboardType: TextInputType.number,
                                            maxLength: 6,
                                            decoration: const InputDecoration(
                                              labelText: 'Mã Admin (6 số)',
                                              helperText:
                                                  'Cần mã Admin để cấp quyền quản trị.',
                                              prefixIcon: Icon(Icons
                                                  .admin_panel_settings_outlined),
                                            ),
                                          ),
                                        ],
                                        TextField(
                                            controller: email,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            decoration: const InputDecoration(
                                                labelText: 'Email',
                                                prefixIcon: Icon(
                                                    Icons.email_outlined))),
                                      ],
                                      if (step == 'credentials')
                                        TextField(
                                            controller: username,
                                            textInputAction:
                                                TextInputAction.next,
                                            autocorrect: false,
                                            decoration: InputDecoration(
                                                labelText: registering
                                                    ? 'Tên đăng nhập'
                                                    : 'Tên đăng nhập hoặc email',
                                                helperText: !registering
                                                    ? 'Dùng email tại đây khi đăng nhập sinh trắc học.'
                                                    : null,
                                                prefixIcon: const Icon(Icons
                                                    .account_circle_outlined))),
                                      if (step == 'credentials')
                                        TextField(
                                            controller: password,
                                            obscureText: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Mật khẩu',
                                                prefixIcon:
                                                    Icon(Icons.lock_outline))),
                                      if (step == 'requestPasswordReset') ...[
                                        const Text(
                                            'Nhập email đã đăng ký để nhận mã OTP đặt lại mật khẩu.'),
                                        TextField(
                                            controller: email,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            decoration: const InputDecoration(
                                                labelText: 'Email',
                                                prefixIcon: Icon(
                                                    Icons.email_outlined))),
                                      ],
                                      if (step == 'verifyEmail' ||
                                          step == 'verifyLoginOtp' ||
                                          step == 'verifyRegistrationRole' ||
                                          step == 'resetPassword') ...[
                                        Text(
                                            step == 'resetPassword'
                                                ? 'Nếu email thuộc tài khoản đã xác minh, mã được gửi đến ${maskedEmail ?? 'email của bạn'}. Mã có hiệu lực trong 5 phút.'
                                                : 'Mã đã gửi đến ${maskedEmail ?? 'email của bạn'}. Mã có hiệu lực trong 5 phút.',
                                            style: const TextStyle(
                                                color: Colors.blueGrey)),
                                        TextField(
                                            controller: otp,
                                            keyboardType: TextInputType.number,
                                            textInputAction:
                                                TextInputAction.done,
                                            autofillHints: const [
                                              AutofillHints.oneTimeCode
                                            ],
                                            maxLength: 6,
                                            decoration: const InputDecoration(
                                                labelText: 'Mã OTP 6 số',
                                                prefixIcon: Icon(Icons
                                                    .verified_user_outlined))),
                                        if (step == 'resetPassword') ...[
                                          TextField(
                                              controller: password,
                                              obscureText: true,
                                              decoration: const InputDecoration(
                                                  labelText: 'Mật khẩu mới',
                                                  prefixIcon:
                                                      Icon(Icons.lock_reset))),
                                          TextField(
                                              controller: confirmPassword,
                                              obscureText: true,
                                              decoration: const InputDecoration(
                                                  labelText:
                                                      'Nhập lại mật khẩu mới',
                                                  prefixIcon: Icon(
                                                      Icons.lock_outline))),
                                        ],
                                      ],
                                      if (message.isNotEmpty)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 12),
                                            child: Text(message,
                                                style: TextStyle(
                                                    color: messageIsError
                                                        ? Colors.red
                                                        : const Color(
                                                            0xFF25815F)))),
                                      const SizedBox(height: 18),
                                      FilledButton(
                                          onPressed: busy ? null : submit,
                                          child: busy
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2))
                                              : Text(step == 'verifyEmail'
                                                  ? 'XÁC MINH EMAIL'
                                                  : step ==
                                                          'verifyRegistrationRole'
                                                      ? 'XÁC NHẬN VAI TRÒ'
                                                      : step == 'verifyLoginOtp'
                                                          ? 'XÁC NHẬN OTP'
                                                          : step ==
                                                                  'requestPasswordReset'
                                                              ? 'GỬI MÃ OTP'
                                                              : step ==
                                                                      'resetPassword'
                                                                  ? 'ĐẶT LẠI MẬT KHẨU'
                                                                  : registering
                                                                      ? 'ĐĂNG KÝ'
                                                                      : 'ĐĂNG NHẬP')),
                                      if (step == 'verifyEmail' ||
                                          step == 'verifyLoginOtp' ||
                                          step == 'verifyRegistrationRole' ||
                                          step == 'resetPassword')
                                        TextButton(
                                            onPressed: busy ? null : resendCode,
                                            child:
                                                const Text('Gửi lại mã OTP')),
                                      if (step == 'credentials' && !registering)
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => setState(() {
                                                      email.text = username.text
                                                              .contains('@')
                                                          ? username.text.trim()
                                                          : '';
                                                      step =
                                                          'requestPasswordReset';
                                                      otp.clear();
                                                      message = '';
                                                    }),
                                            child:
                                                const Text('Quên mật khẩu?')),
                                      if (step == 'requestPasswordReset' ||
                                          step == 'resetPassword')
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => setState(() {
                                                      step = 'credentials';
                                                      otp.clear();
                                                      confirmPassword.clear();
                                                      message = '';
                                                    }),
                                            child: const Text(
                                                'Quay lại đăng nhập')),
                                      if (step == 'credentials')
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => setState(() {
                                                      registering =
                                                          !registering;
                                                      message = '';
                                                    }),
                                            child: Text(registering
                                                ? 'Đã có tài khoản? Đăng nhập'
                                                : 'Chưa có tài khoản? Đăng ký')),
                                      if (step == 'credentials' && !registering)
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              widget.onBiometricLogin(
                                                  username.text, true),
                                          icon: const Icon(Icons.face),
                                          label: const Text(
                                              'Đăng nhập bằng khuôn mặt'),
                                        ),
                                      if (step == 'credentials' && !registering)
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              widget.onBiometricLogin(
                                                  username.text, false),
                                          icon: const Icon(Icons.fingerprint),
                                          label: const Text(
                                              'Đăng nhập bằng vân tay'),
                                        ),
                                    ]))))))),
      );
}

class AttendanceHome extends StatefulWidget {
  const AttendanceHome(
      {super.key, required this.session, required this.onLogout});
  final _Session session;
  final VoidCallback onLogout;
  @override
  State<AttendanceHome> createState() => _AttendanceHomeState();
}

class _AttendanceHomeState extends State<AttendanceHome> {
  bool checkedIn = false;
  String? checkInTime;
  String? checkOutTime;
  DateTime? checkInAt;
  DateTime? checkOutAt;
  final List<_Attendance> history = [];

  bool syncing = false;
  bool apiOnline = false;
  String currentLocationLabel = 'Đang lấy vị trí...';
  String currentAddressLabel = 'Đang xác định đường và thành phố...';
  String currentWeatherLabel = 'Đang tải thời tiết...';
  bool loadingLocation = false;
  Timer? _durationTicker;
  @override
  void initState() {
    super.initState();
    _syncFromApi();
    _refreshCurrentLocation();
    _durationTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && checkedIn) setState(() {});
    });
  }

  @override
  void dispose() {
    _durationTicker?.cancel();
    super.dispose();
  }

  Map<String, String> get authHeaders =>
      {'Authorization': 'Bearer ${widget.session.token}'};

  Future<void> _syncFromApi() async {
    try {
      final responses = await Future.wait([
        http
            .get(Uri.parse('$apiBase/attendance/today'), headers: authHeaders)
            .timeout(const Duration(seconds: 5)),
        http
            .get(Uri.parse('$apiBase/attendance/history?limit=1000'),
                headers: authHeaders)
            .timeout(const Duration(seconds: 5)),
      ]);
      final todayResponse = responses[0];
      final historyResponse = responses[1];
      if (todayResponse.statusCode != 200 || historyResponse.statusCode != 200)
        throw Exception('API trả về lỗi.');
      final today = jsonDecode(todayResponse.body) as Map<String, dynamic>;
      final list = (jsonDecode(historyResponse.body) as List)
          .cast<Map<String, dynamic>>();
      final record = today['record'] as Map<String, dynamic>?;
      final startAt = record == null
          ? null
          : DateTime.parse(record['checkIn'] as String).toLocal();
      final endAt = record?['checkOut'] == null
          ? null
          : DateTime.parse(record!['checkOut'] as String).toLocal();
      if (!mounted) return;
      setState(() {
        apiOnline = true;
        checkedIn = today['checkedIn'] == true;
        checkInAt = startAt;
        checkOutAt = endAt;
        checkInTime = startAt == null ? null : _time(startAt);
        checkOutTime = endAt == null ? null : _time(endAt);
        history
          ..clear()
          ..addAll(list.map((item) {
            final startedAt =
                DateTime.parse(item['checkIn'] as String).toLocal();
            final endedAt = item['checkOut'] == null
                ? null
                : DateTime.parse(item['checkOut'] as String).toLocal();
            return _Attendance(
              _formatDate(DateTime.parse(item['date'] as String)),
              _time(startedAt),
              endedAt == null ? null : _time(endedAt),
              endedAt == null ? 'Đang làm việc' : 'Đã hoàn thành',
              startedAt: startedAt,
              endedAt: endedAt,
              checkInLocation: _coordinateLabel(
                  item['checkInLatitude'], item['checkInLongitude']),
              checkOutLocation: _coordinateLabel(
                  item['checkOutLatitude'], item['checkOutLongitude']),
            );
          }));
      });
    } catch (_) {
      if (mounted) setState(() => apiOnline = false);
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  String get _today {
    final now = DateTime.now();
    const weekdays = [
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật'
    ];
    return '${weekdays[now.weekday - 1]}, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  String get _workInsight {
    if (checkInTime == null)
      return 'Chưa có giờ vào hôm nay. Chấm công trước 09:00 để bắt đầu ca đúng giờ.';
    final start = checkInAt;
    if (checkedIn &&
        start != null &&
        (start.year != DateTime.now().year ||
            start.month != DateTime.now().month ||
            start.day != DateTime.now().day)) {
      return 'Ca làm hiện tại bắt đầu ngày ${_formatDate(start)}. Hãy chấm công ra để kết thúc ca.';
    }
    final minutes =
        checkInAt == null ? 0 : checkInAt!.hour * 60 + checkInAt!.minute;
    if (minutes > 9 * 60)
      return 'Bạn vào ca muộn ${minutes - 9 * 60} phút so với mốc 09:00.';
    return 'Bạn đã bắt đầu ca đúng giờ. Chúc bạn một ngày làm việc hiệu quả!';
  }

  int get _daysThisMonth => history
      .where((entry) {
        final parts = entry.date.split('/');
        return parts.length == 3 &&
            int.tryParse(parts[1]) == DateTime.now().month &&
            int.tryParse(parts[2]) == DateTime.now().year;
      })
      .map((entry) => entry.date)
      .toSet()
      .length;

  int get _workedMinutesThisMonth {
    final now = DateTime.now();
    return history.where((entry) {
      final parts = entry.date.split('/');
      return parts.length == 3 &&
          int.tryParse(parts[1]) == now.month &&
          int.tryParse(parts[2]) == now.year;
    }).fold<int>(0, (total, entry) => total + entry.workedMinutes);
  }

  String get _workedHoursThisMonth {
    final minutes = _workedMinutesThisMonth;
    return '${minutes ~/ 60} giờ ${minutes.remainder(60)} phút';
  }

  String get _workedDuration {
    final start = checkInAt;
    if (start == null) return '0 giờ';
    final elapsed = (checkOutAt ?? DateTime.now()).difference(start);
    if (elapsed.isNegative) return '0 giờ';
    return '${elapsed.inHours} giờ ${elapsed.inMinutes.remainder(60)} phút';
  }

  void _openHistory() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          AttendanceHistoryPage(entries: List.unmodifiable(history))));

  Future<void> _refreshCurrentLocation() async {
    if (loadingLocation) return;
    setState(() {
      loadingLocation = true;
      currentLocationLabel = 'Đang cập nhật vị trí...';
      currentAddressLabel = 'Đang xác định đường và thành phố...';
      currentWeatherLabel = 'Đang tải thời tiết...';
    });
    try {
      final position = await _getCurrentAttendancePosition();
      if (!mounted) return;
      setState(() {
        currentLocationLabel =
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      });
      await _loadAddressAndWeather(position);
    } catch (error) {
      if (!mounted) return;
      setState(() => currentLocationLabel = _displayError(error));
    } finally {
      if (mounted) setState(() => loadingLocation = false);
    }
  }

  Future<void> _loadAddressAndWeather(Position position) async {
    final addressTask = () async {
      try {
        final place = await _locationChannel
            .invokeMapMethod<String, dynamic>('reverseGeocode', {
          'latitude': position.latitude,
          'longitude': position.longitude,
        });
        final street = (place?['street'] as String?)?.trim();
        final district = (place?['district'] as String?)?.trim();
        final city = (place?['city'] as String?)?.trim();
        final fullAddress = (place?['address'] as String?)?.trim();
        final namedParts = [street, district, city]
            .whereType<String>()
            .where((part) => part.isNotEmpty)
            .toList();
        final address = namedParts.isNotEmpty
            ? namedParts.toSet().join(', ')
            : (fullAddress?.isNotEmpty == true
                ? fullAddress!
                : 'Không tìm thấy địa chỉ gần đây');
        if (!mounted) return;
        setState(() => currentAddressLabel = address);
      } catch (_) {
        if (mounted) {
          setState(() => currentAddressLabel = 'Không xác định được địa chỉ');
        }
      }
    }();

    final weatherTask = () async {
      try {
        final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
          'current':
              'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code',
          'timezone': 'auto',
        });
        final response =
            await http.get(uri).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) throw Exception('weather unavailable');
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final current = payload['current'] as Map<String, dynamic>;
        final temperature = (current['temperature_2m'] as num).round();
        final feelsLike = (current['apparent_temperature'] as num).round();
        final humidity = (current['relative_humidity_2m'] as num).round();
        final description = _weatherDescription(current['weather_code'] as int);
        if (!mounted) return;
        setState(() => currentWeatherLabel =
            '$description · $temperature°C (cảm nhận $feelsLike°C) · Ẩm $humidity%');
      } catch (_) {
        if (mounted)
          setState(() => currentWeatherLabel = 'Chưa tải được thời tiết');
      }
    }();

    await Future.wait([addressTask, weatherTask]);
  }

  Future<void> _clock() async {
    if (syncing) return;
    Position position;
    try {
      position = await _getCurrentAttendancePosition();
      if (mounted) {
        setState(() {
          currentLocationLabel =
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
          currentAddressLabel = 'Đang xác định đường và thành phố...';
          currentWeatherLabel = 'Đang tải thời tiết...';
        });
        unawaited(_loadAddressAndWeather(position));
      }
    } catch (error) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Không lấy được vị trí'),
            content: Text(_displayError(error)),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Đã hiểu')),
            ],
          ),
        );
      }
      return;
    }
    final wasCheckedIn = checkedIn;
    setState(() => syncing = true);
    try {
      final action = wasCheckedIn ? 'check-out' : 'check-in';
      final response = await http
          .post(Uri.parse('$apiBase/attendance/$action'),
              headers: {
                ...authHeaders,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'latitude': position.latitude,
                'longitude': position.longitude,
              }))
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 300) {
        // Reconcile local button state when the API rejects a stale action,
        // for example if a previous check-in succeeded but its reply was lost.
        await _syncFromApi();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_apiError(response.body,
                  'Không thể chấm công (${response.statusCode}).'))));
        }
        return;
      }
      final startedAt = DateTime.parse(data['checkIn'] as String).toLocal();
      final endedAt = data['checkOut'] == null
          ? null
          : DateTime.parse(data['checkOut'] as String).toLocal();
      final date = _formatDate(DateTime.parse(data['date'] as String));
      if (mounted) {
        setState(() {
          apiOnline = true;
          checkedIn = endedAt == null;
          checkInAt = startedAt;
          checkOutAt = endedAt;
          checkInTime = _time(startedAt);
          checkOutTime = endedAt == null ? null : _time(endedAt);
          final todayIndex = history.indexWhere((entry) => entry.date == date);
          final summary = _Attendance(
              date,
              _time(startedAt),
              endedAt == null ? null : _time(endedAt),
              endedAt == null ? 'Đang làm việc' : 'Đã hoàn thành',
              startedAt: startedAt,
              endedAt: endedAt,
              checkInLocation: _coordinateLabel(
                  data['checkInLatitude'], data['checkInLongitude']),
              checkOutLocation: _coordinateLabel(
                  data['checkOutLatitude'], data['checkOutLongitude']));
          if (todayIndex == -1) {
            history.insert(0, summary);
          } else {
            history[todayIndex] = summary;
          }
        });
      }
      // Refresh from the server for the authoritative status and full history.
      await _syncFromApi();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(wasCheckedIn
                ? 'Đã chấm công ra thành công.'
                : 'Đã chấm công vào thành công.')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không gọi được API: $error')));
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<Position> _getCurrentAttendancePosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Bật dịch vụ Vị trí trên điện thoại rồi thử lại.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Cần cấp quyền vị trí để lưu vị trí chấm công.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Quyền vị trí đã bị từ chối. Hãy bật quyền này trong Cài đặt ứng dụng.');
    }
    return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
  }

  Future<void> _shareLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled())
        throw Exception('Hãy bật dịch vụ vị trí.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw Exception('Ứng dụng chưa được cấp quyền vị trí.');
      final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 20)));
      final link =
          'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      await Share.share('Vị trí của ${widget.session.employee.displayName}:\n'
          '${position.latitude}, ${position.longitude}\n$link');
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không lấy được vị trí: $error')));
    }
  }

  Future<void> _verifyBiometricForAttendance(BiometricType selected) async {
    final auth = LocalAuthentication();
    final label = selected == BiometricType.face ? 'khuôn mặt' : 'vân tay';
    try {
      final supported = await _biometricTypeAvailable(auth, selected);
      if (!await auth.isDeviceSupported() || !supported) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Thiết bị không hỗ trợ'),
            content: Text(
                'Thiết bị của bạn không hỗ trợ hoặc chưa thiết lập xác thực bằng $label.'),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Đã hiểu')),
            ],
          ),
        );
        return;
      }
      final verified = await auth.authenticate(
        localizedReason: 'Xác thực bằng $label để chấm công',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (verified) await _clock();
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Không thể xác thực'),
          content: Text(_displayError(error)),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Đã hiểu')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Chấm công',
                style: TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              IconButton(
                  tooltip: 'Đăng xuất',
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded))
            ]),
        body: SafeArea(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
              Text('Xin chào, ${widget.session.employee.displayName} 👋',
                  style: const TextStyle(
                      fontSize: 23, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 5),
              Text(_today, style: TextStyle(color: Colors.blueGrey.shade600)),
              const SizedBox(height: 22),
              Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF315FE8), Color(0xFF5688FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                            color: blue.withValues(alpha: .2),
                            blurRadius: 22,
                            offset: const Offset(0, 10))
                      ]),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.location_on_outlined,
                              color: Colors.white70, size: 19),
                          const SizedBox(width: 6),
                          Text('VĂN PHÒNG',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: .8),
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700))
                        ]),
                        const SizedBox(height: 7),
                        Text(widget.session.employee.department,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                              child:
                                  _timeTile('GIỜ VÀO', checkInTime ?? '--:--')),
                          Container(
                              width: 1, height: 43, color: Colors.white24),
                          Expanded(
                              child:
                                  _timeTile('GIỜ RA', checkOutTime ?? '--:--'))
                        ]),
                        const SizedBox(height: 14),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(14)),
                            child: Row(children: [
                              const Icon(Icons.my_location,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('VỊ TRÍ HIỆN TẠI',
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: .78),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: .7)),
                                    const SizedBox(height: 3),
                                    Text(currentAddressLabel,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 3),
                                    Text(currentLocationLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: .72),
                                            fontSize: 10)),
                                    const SizedBox(height: 9),
                                    Row(children: [
                                      const Icon(Icons.cloud_outlined,
                                          color: Colors.white, size: 16),
                                      const SizedBox(width: 5),
                                      Expanded(
                                          child: Text(currentWeatherLabel,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600)))
                                    ]),
                                    const SizedBox(height: 3),
                                    Text('Thời tiết: Open-Meteo',
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: .65),
                                            fontSize: 9))
                                  ])),
                              IconButton(
                                  tooltip: 'Cập nhật vị trí',
                                  onPressed: loadingLocation
                                      ? null
                                      : _refreshCurrentLocation,
                                  visualDensity: VisualDensity.compact,
                                  icon: loadingLocation
                                      ? const SizedBox(
                                          width: 17,
                                          height: 17,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Icon(Icons.refresh,
                                          color: Colors.white, size: 19))
                            ])),
                        const SizedBox(height: 20),
                        SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: FilledButton.icon(
                                onPressed: syncing ? null : _clock,
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: blue,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16))),
                                icon: syncing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.touch_app_outlined),
                                label: Text(
                                    syncing
                                        ? 'ĐANG GỬI...'
                                        : checkedIn
                                            ? 'CHẤM CÔNG RA'
                                            : 'CHẤM CÔNG VÀO',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .4)))),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: syncing
                                  ? null
                                  : () => _verifyBiometricForAttendance(
                                      BiometricType.face),
                              icon: const Icon(Icons.face),
                              label: const Text('Khuôn mặt'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side:
                                      const BorderSide(color: Colors.white70)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: syncing
                                  ? null
                                  : () => _verifyBiometricForAttendance(
                                      BiometricType.fingerprint),
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Vân tay'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side:
                                      const BorderSide(color: Colors.white70)),
                            ),
                          ),
                        ])
                      ])),
              const SizedBox(height: 22),
              Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEAF0FF),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.auto_awesome_outlined, color: blue),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_workInsight,
                                style:
                                    const TextStyle(color: ink, height: 1.4)))
                      ])),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _shareLocation,
                        icon: const Icon(Icons.location_on_outlined),
                        label: const Text('Chia sẻ vị trí'))),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                    child: _statCard(
                        Icons.access_time, 'Giờ làm hôm nay', _workedDuration)),
                const SizedBox(width: 12),
                Expanded(
                    child: _statCard(Icons.event_available_outlined,
                        'Ngày công tháng', '$_daysThisMonth ngày'))
              ]),
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: const Color(0xFFE9EDF5))),
                  child: Row(children: [
                    const Icon(Icons.timelapse_outlined, color: blue),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Tổng giờ công tháng này',
                              style: TextStyle(
                                  color: Colors.blueGrey.shade600,
                                  fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(_workedHoursThisMonth,
                              style: const TextStyle(
                                  color: ink,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800))
                        ]))
                  ])),
              const SizedBox(height: 27),
              Row(children: [
                const Expanded(
                    child: Text('Lịch sử gần đây',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: ink))),
                TextButton(
                    onPressed: _openHistory, child: const Text('Xem tất cả'))
              ]),
              const SizedBox(height: 8),
              if (history.isEmpty)
                _historyRow(
                    _today,
                    checkInTime ?? '--:--',
                    checkedIn ? 'Đang làm việc' : 'Chưa chấm công',
                    checkedIn ? Icons.work_history_outlined : Icons.more_time,
                    checkedIn ? const Color(0xFF2A9D72) : Colors.blueGrey)
              else
                ...history.take(5).map((entry) => _historyRow(
                    entry.date,
                    entry.start,
                    entry.status,
                    Icons.check_circle_outline,
                    const Color(0xFF2A9D72),
                    entry.end,
                    entry.checkInLocation)),
              const SizedBox(height: 18),
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: apiOnline
                          ? const Color(0xFFEAF0FF)
                          : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                            apiOnline
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            color: apiOnline ? blue : Colors.deepOrange,
                            size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                apiOnline
                                    ? 'Đã kết nối API • ${widget.session.employee.id} • ${widget.session.employee.role}'
                                    : 'Chưa kết nối API. Hãy chạy ASP.NET API để đồng bộ chấm công.',
                                style: const TextStyle(
                                    color: ink, height: 1.4, fontSize: 12)))
                      ]))
            ])),
        bottomNavigationBar: NavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (index) {
              if (index == 1) {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AttendanceHistoryPage(
                        entries: List.unmodifiable(history))));
              } else if (index == 2) {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EmployeeProfilePage(
                        session: widget.session, onLogout: widget.onLogout)));
              }
            },
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Tổng quan'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Bảng công'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline), label: 'Cá nhân')
            ]),
      );

  Widget _timeTile(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .8)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800))
      ]));
  Widget _statCard(IconData icon, String label, String value) => Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFFE9EDF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: blue),
        const SizedBox(height: 13),
        Text(value,
            style: const TextStyle(
                color: ink, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12))
      ]));
  Widget _historyRow(
          String date, String time, String status, IconData icon, Color color,
          [String? end, String? location]) =>
      Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFE9EDF5))),
          child: Row(children: [
            CircleAvatar(
                backgroundColor: color.withValues(alpha: .1),
                child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(date,
                      style: const TextStyle(
                          color: ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                      end == null
                          ? 'Giờ vào: $time'
                          : 'Vào: $time  •  Ra: $end',
                      style: TextStyle(
                          color: Colors.blueGrey.shade600, fontSize: 12)),
                  if (location != null) ...[
                    const SizedBox(height: 3),
                    Text('Vị trí vào: $location',
                        style: TextStyle(
                            color: Colors.blueGrey.shade600, fontSize: 11)),
                  ]
                ])),
            Text(status,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12))
          ]));
}

class _Attendance {
  const _Attendance(this.date, this.start, this.end, this.status,
      {this.startedAt,
      this.endedAt,
      this.checkInLocation,
      this.checkOutLocation});
  final String date, start;
  final String? end;
  final String? checkInLocation, checkOutLocation;
  final String status;
  final DateTime? startedAt, endedAt;

  int get workedMinutes {
    final start = startedAt;
    if (start == null) return 0;
    final duration = (endedAt ?? DateTime.now()).difference(start);
    return duration.isNegative ? 0 : duration.inMinutes;
  }
}

class AttendanceHistoryPage extends StatelessWidget {
  const AttendanceHistoryPage({super.key, required this.entries});
  final List<_Attendance> entries;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bảng công')),
        body: entries.isEmpty
            ? const Center(child: Text('Chưa có dữ liệu chấm công.'))
            : ListView.builder(
                padding: const EdgeInsets.all(18),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                          leading: const CircleAvatar(
                              backgroundColor: Color(0xFFEAF0FF),
                              child: Icon(Icons.event_available, color: blue)),
                          title: Text(entry.date,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              [
                                entry.end == null
                                    ? 'Giờ vào: ${entry.start}'
                                    : 'Giờ vào: ${entry.start}  •  Giờ ra: ${entry.end}',
                                if (entry.checkInLocation != null)
                                  'Vị trí vào: ${entry.checkInLocation}',
                                if (entry.checkOutLocation != null)
                                  'Vị trí ra: ${entry.checkOutLocation}',
                              ].join('\n'),
                              maxLines: 3),
                          trailing: Text(entry.status,
                              style: const TextStyle(
                                  color: Color(0xFF23936B),
                                  fontWeight: FontWeight.w700))));
                }),
      );
}

class EmployeeProfilePage extends StatefulWidget {
  const EmployeeProfilePage(
      {super.key, required this.session, required this.onLogout});
  final _Session session;
  final VoidCallback onLogout;
  @override
  State<EmployeeProfilePage> createState() => _EmployeeProfilePageState();
}

class _EmployeeProfilePageState extends State<EmployeeProfilePage> {
  Future<void> _changePassword() async {
    final headers = {
      'Authorization': 'Bearer ${widget.session.token}',
      'Content-Type': 'application/json',
    };
    try {
      final request = await http
          .post(Uri.parse('$apiBase/auth/request-password-change'),
              headers: headers, body: '{}')
          .timeout(const Duration(seconds: 12));
      if (request.statusCode >= 300) {
        throw Exception(_apiError(request.body, 'Không gửi được OTP.'));
      }
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      if (!mounted) return;
      final code = TextEditingController();
      final newPassword = TextEditingController();
      final confirmPassword = TextEditingController();
      var busy = false;
      var error = '';
      final changed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('Đổi mật khẩu'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    'Nhập mã OTP đã gửi đến ${data['email'] ?? 'email của bạn'}.'),
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'Mã OTP'),
                ),
                TextField(
                  controller: newPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Mật khẩu mới (ít nhất 8 ký tự)'),
                ),
                TextField(
                  controller: confirmPassword,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Nhập lại mật khẩu mới'),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(error, style: const TextStyle(color: Colors.red)),
                ],
              ]),
            ),
            actions: [
              TextButton(
                onPressed:
                    busy ? null : () => Navigator.pop(dialogContext, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final pass = newPassword.text;
                        if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
                          setDialog(() => error = 'Mã OTP phải gồm 6 chữ số.');
                          return;
                        }
                        if (pass.length < 8) {
                          setDialog(
                              () => error = 'Mật khẩu cần ít nhất 8 ký tự.');
                          return;
                        }
                        if (pass != confirmPassword.text) {
                          setDialog(
                              () => error = 'Mật khẩu xác nhận không khớp.');
                          return;
                        }
                        setDialog(() {
                          busy = true;
                          error = '';
                        });
                        try {
                          final response = await http
                              .post(Uri.parse('$apiBase/auth/change-password'),
                                  headers: headers,
                                  body: jsonEncode({
                                    'code': code.text.trim(),
                                    'newPassword': pass,
                                  }))
                              .timeout(const Duration(seconds: 12));
                          if (response.statusCode >= 300) {
                            throw Exception(_apiError(
                                response.body, 'Không đổi được mật khẩu.'));
                          }
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialog(() {
                              error = _displayError(e);
                              busy = false;
                            });
                          }
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Xác nhận'),
              ),
            ],
          ),
        ),
      );
      code.dispose();
      newPassword.dispose();
      confirmPassword.dispose();
      if (changed == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã đổi mật khẩu thành công.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Không thể yêu cầu OTP: ${_displayError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tài khoản của tôi')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Center(
              child: _accountAvatar(widget.session.employee.avatarBase64,
                  radius: 44)),
          const SizedBox(height: 12),
          Center(
              child: Text(widget.session.employee.displayName,
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w800, color: ink))),
          const SizedBox(height: 20),
          Card(
              child: Column(children: [
            ListTile(
                leading: const Icon(Icons.alternate_email, color: blue),
                title: const Text('Tên đăng nhập'),
                subtitle: Text(widget.session.employee.username)),
            const Divider(height: 1),
            ListTile(
                leading: const Icon(Icons.business_outlined, color: blue),
                title: const Text('Phòng ban'),
                subtitle: Text(widget.session.employee.department)),
            const Divider(height: 1),
            ListTile(
                leading: const Icon(Icons.badge_outlined, color: blue),
                title: const Text('Vai trò'),
                subtitle:
                    Text(switch (widget.session.employee.role.toLowerCase()) {
                  'admin' => 'Quản trị viên',
                  'employee' => 'Nhân viên',
                  _ => 'Vai trò chưa hỗ trợ',
                })),
          ])),
          const SizedBox(height: 20),
          OutlinedButton.icon(
              onPressed: _changePassword,
              icon: const Icon(Icons.lock_reset_outlined),
              label: const Text('Đổi mật khẩu qua OTP email')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Đăng xuất')),
        ]),
      );
}

class AttendanceNfcPage extends StatefulWidget {
  const AttendanceNfcPage({super.key});

  @override
  State<AttendanceNfcPage> createState() => _AttendanceNfcPageState();
}

class _AttendanceNfcPageState extends State<AttendanceNfcPage> {
  bool scanning = false;
  String? error;

  @override
  void dispose() {
    _nfcChannel.invokeMethod<void>('cancel');
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    if (!mounted) return;
    setState(() {
      scanning = true;
      error = null;
    });
    try {
      final value = await _nfcChannel
          .invokeMethod<String>('scan')
          .timeout(const Duration(seconds: 45));
      if (mounted && value != null) {
        Navigator.pop(context, value);
      } else if (mounted) {
        setState(() => error = 'Thẻ không có nội dung NDEF có thể đọc.');
      }
    } on TimeoutException {
      await _nfcChannel.invokeMethod<void>('cancel');
      if (mounted)
        setState(() => error = 'Không tìm thấy thẻ NFC. Hãy thử lại.');
    } on PlatformException catch (exception) {
      if (mounted) {
        setState(() => error = exception.message ?? 'Không thể quét NFC.');
      }
    } catch (exception) {
      if (mounted) setState(() => error = 'Không thể quét NFC: $exception');
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await _nfcChannel.invokeMethod<void>('cancel');
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Quét thẻ NFC')),
        body: Center(
            child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.contactless, size: 88, color: blue),
            const SizedBox(height: 20),
            Text(
                scanning
                    ? 'Đưa điện thoại lại gần thẻ chấm công'
                    : 'Sẵn sàng quét thẻ NFC',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ink, fontSize: 20, fontWeight: FontWeight.w700)),
            if (scanning) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator()
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red))
            ],
            const SizedBox(height: 24),
            if (!scanning)
              FilledButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại')),
            TextButton(onPressed: _cancel, child: const Text('Hủy'))
          ]),
        )),
      );
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.session, required this.onLogout});
  final _Session session;
  final VoidCallback onLogout;
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  List<Map<String, dynamic>> employees = [];
  List<Map<String, dynamic>> attendance = [];
  final searchController = TextEditingController();
  final _adminScrollController = ScrollController();
  final _attendanceSectionKey = GlobalKey();
  String accountFilter = 'Tất cả';
  int _adminSection = 0;
  bool loading = true;
  String? error;
  Map<String, String> get headers => {
        'Authorization': 'Bearer ${widget.session.token}',
        'Content-Type': 'application/json'
      };

  List<Map<String, dynamic>> get visibleEmployees {
    final query = searchController.text.trim().toLowerCase();
    return employees.where((employee) {
      final roleMatches = accountFilter == 'Tất cả' ||
          (accountFilter == 'Admin'
              ? employee['role'] == 'Admin'
              : employee['role'] == 'Employee');
      final text = [
        employee['displayName'],
        employee['username'],
        employee['email'],
        employee['department'],
      ].join(' ').toLowerCase();
      return roleMatches && (query.isEmpty || text.contains(query));
    }).toList();
  }

  List<Map<String, dynamic>> get visibleAttendance {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) return attendance;
    return attendance
        .where((row) => '${row['employeeName']} ${row['username']}'
            .toLowerCase()
            .contains(query))
        .toList();
  }

  Widget _metric(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9EDF5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 19, color: blue),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: ink, fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 11)),
        ]),
      );

  @override
  void dispose() {
    searchController.dispose();
    _adminScrollController.dispose();
    super.dispose();
  }

  void _selectAdminSection(int index) {
    setState(() => _adminSection = index);
    if (index == 0) {
      if (_adminScrollController.hasClients) {
        _adminScrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } else if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _attendanceSectionKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(target,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              alignment: 0.04);
        }
      });
    } else if (index == 2) {
      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => EmployeeProfilePage(
                  session: widget.session, onLogout: widget.onLogout)))
          .then((_) {
        if (mounted) setState(() => _adminSection = 0);
      });
    }
  }

  Future<void> _openOwnAttendance() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AttendanceHome(
              session: widget.session,
              onLogout: widget.onLogout,
            )));
    if (mounted) _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await http
          .get(Uri.parse('$apiBase/employees'), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200)
        throw Exception(
            'Không tải được danh sách nhân viên (${response.statusCode}).');
      final data =
          (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => employees = data);
      final attendanceResponse = await http
          .get(Uri.parse('$apiBase/attendance/admin/history?limit=500'),
              headers: headers)
          .timeout(const Duration(seconds: 12));
      if (attendanceResponse.statusCode == 200 && mounted) {
        setState(() => attendance =
            (jsonDecode(attendanceResponse.body) as List)
                .cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _edit({Map<String, dynamic>? employee}) async {
    final name = TextEditingController(text: employee?['displayName'] ?? '');
    final email = TextEditingController(text: employee?['email'] ?? '');
    final department =
        TextEditingController(text: employee?['department'] ?? '');
    final username = TextEditingController();
    final password = TextEditingController();
    var role = employee?['role'] == 'Admin' ? 'Admin' : 'Employee';
    String? avatarBase64 = employee?['avatarBase64'] as String?;
    final editingOwnAccount = employee?['id'] == widget.session.employee.id;
    var saving = false;
    var showPassword = false;
    var dialogClosed = false;
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialog) => AlertDialog(
                  title: Text(employee == null
                      ? 'Thêm nhân viên'
                      : 'Cập nhật nhân viên'),
                  content: SizedBox(
                      width: 420,
                      child: Form(
                          key: formKey,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                if (employee == null)
                                  TextFormField(
                                      controller: username,
                                      decoration: const InputDecoration(
                                          labelText: 'Tên đăng nhập'),
                                      validator: (v) =>
                                          (v == null || v.trim().length < 3)
                                              ? 'Nhập ít nhất 3 ký tự'
                                              : null),
                                Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _accountAvatar(avatarBase64, radius: 32),
                                      const SizedBox(width: 12),
                                      TextButton.icon(
                                          onPressed: saving
                                              ? null
                                              : () async {
                                                  try {
                                                    final image =
                                                        await _pickAvatar();
                                                    if (image != null &&
                                                        dialogContext.mounted) {
                                                      setDialog(() =>
                                                          avatarBase64 = image);
                                                    }
                                                  } catch (error) {
                                                    if (dialogContext.mounted) {
                                                      ScaffoldMessenger.of(
                                                              this.context)
                                                          .showSnackBar(SnackBar(
                                                              content: Text(
                                                                  'Không chọn được ảnh: ${_displayError(error)}')));
                                                    }
                                                  }
                                                },
                                          icon: const Icon(
                                              Icons.add_a_photo_outlined),
                                          label: Text(avatarBase64 == null
                                              ? 'Chọn ảnh *'
                                              : 'Đổi ảnh'))
                                    ]),
                                TextFormField(
                                    controller: name,
                                    decoration: const InputDecoration(
                                        labelText: 'Họ và tên'),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                            ? 'Bắt buộc'
                                            : null),
                                TextFormField(
                                    controller: email,
                                    decoration: const InputDecoration(
                                        labelText: 'Email'),
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) => (v == null ||
                                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                                .hasMatch(v.trim()))
                                        ? 'Email chưa hợp lệ'
                                        : null),
                                TextFormField(
                                    controller: department,
                                    decoration: const InputDecoration(
                                        labelText: 'Phòng ban')),
                                TextFormField(
                                    controller: password,
                                    decoration: InputDecoration(
                                        labelText: employee == null
                                            ? 'Mật khẩu tạm thời'
                                            : 'Mật khẩu mới (để trống nếu giữ nguyên)',
                                        helperText: employee == null
                                            ? 'Admin đặt mật khẩu ban đầu cho tài khoản.'
                                            : 'Admin có thể đặt mật khẩu mới trực tiếp khi lưu.',
                                        suffixIcon: IconButton(
                                            tooltip: showPassword
                                                ? 'Ẩn mật khẩu'
                                                : 'Hiện mật khẩu mới',
                                            onPressed: () => setDialog(() =>
                                                showPassword = !showPassword),
                                            icon: Icon(showPassword
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined))),
                                    obscureText: !showPassword,
                                    validator: (v) {
                                      final value = v ?? '';
                                      if (employee == null && value.length < 8)
                                        return 'Mật khẩu cần ít nhất 8 ký tự';
                                      if (value.isNotEmpty && value.length < 8)
                                        return 'Mật khẩu mới cần ít nhất 8 ký tự';
                                      return null;
                                    }),
                                DropdownButtonFormField<String>(
                                    initialValue: role,
                                    decoration: const InputDecoration(
                                        labelText: 'Quyền'),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'Employee',
                                          child: Text('Nhân viên')),
                                      DropdownMenuItem(
                                          value: 'Admin',
                                          child: Text('Quản trị viên'))
                                    ],
                                    onChanged: (v) => setDialog(
                                        () => role = v ?? 'Employee')),
                              ])))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Hủy')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setDialog(() => saving = true);
                                try {
                                  final body = employee == null
                                      ? {
                                          'username': username.text.trim(),
                                          'password': password.text,
                                          'displayName': name.text.trim(),
                                          'email': email.text.trim(),
                                          'department': department.text.trim(),
                                          'role': role,
                                          'avatarBase64': avatarBase64
                                        }
                                      : {
                                          'displayName': name.text.trim(),
                                          'email': email.text.trim(),
                                          'department': department.text.trim(),
                                          'role': role,
                                          'avatarBase64': avatarBase64,
                                          'password': password.text.isEmpty
                                              ? null
                                              : password.text
                                        };
                                  final uri = employee == null
                                      ? Uri.parse('$apiBase/employees')
                                      : Uri.parse(
                                          '$apiBase/employees/${employee['id']}');
                                  final response = employee == null
                                      ? await http
                                          .post(uri,
                                              headers: headers,
                                              body: jsonEncode(body))
                                          .timeout(const Duration(seconds: 12))
                                      : await http
                                          .put(uri,
                                              headers: headers,
                                              body: jsonEncode(body))
                                          .timeout(const Duration(seconds: 12));
                                  if (response.statusCode >= 300) {
                                    if (dialogContext.mounted) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(SnackBar(
                                              content: Text(_apiError(
                                                  response.body,
                                                  'Không thể lưu nhân viên.'))));
                                    }
                                    return;
                                  }
                                  if (dialogContext.mounted) {
                                    dialogClosed = true;
                                    Navigator.pop(dialogContext, true);
                                  }
                                } catch (error) {
                                  if (dialogContext.mounted) {
                                    ScaffoldMessenger.of(this.context)
                                        .showSnackBar(SnackBar(
                                            content: Text(
                                                'Không lưu được: ${_displayError(error)}')));
                                  }
                                } finally {
                                  if (dialogContext.mounted && !dialogClosed) {
                                    setDialog(() => saving = false);
                                  }
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(editingOwnAccount && role == 'Employee'
                                ? 'Lưu và đăng xuất'
                                : 'Lưu'))
                  ],
                )));
    name.dispose();
    email.dispose();
    department.dispose();
    username.dispose();
    password.dispose();
    if (saved == true) {
      if (editingOwnAccount && role == 'Employee') {
        widget.onLogout();
      } else {
        await _load();
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> employee) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Xóa nhân viên?'),
                content: Text(
                    'Tài khoản ${employee['username']} sẽ bị xóa cùng lịch sử liên quan.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Hủy')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Xóa'))
                ]));
    if (yes != true) return;
    try {
      final response = await http
          .delete(Uri.parse('$apiBase/employees/${employee['id']}'),
              headers: headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 300) {
        throw Exception(_apiError(response.body, 'Không thể xóa tài khoản.'));
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không xóa được: ${_displayError(error)}')));
      }
    }
  }

  Future<DateTime?> _chooseAttendanceTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _editAttendance(Map<String, dynamic> row) async {
    var checkIn = DateTime.parse(row['checkIn'] as String).toLocal();
    var checkOut = row['checkOut'] == null
        ? null
        : DateTime.parse(row['checkOut'] as String).toLocal();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Sửa giờ chấm công'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Giờ vào'),
              subtitle: Text(_formatAttendanceTime(checkIn.toIso8601String())),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final value = await _chooseAttendanceTime(checkIn);
                if (value != null) setDialog(() => checkIn = value);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Giờ ra'),
              subtitle: Text(checkOut == null
                  ? 'Chưa chấm công ra'
                  : _formatAttendanceTime(checkOut!.toIso8601String())),
              trailing: Wrap(spacing: 4, children: [
                IconButton(
                  tooltip: 'Chọn giờ ra',
                  onPressed: () async {
                    final value =
                        await _chooseAttendanceTime(checkOut ?? checkIn);
                    if (value != null) setDialog(() => checkOut = value);
                  },
                  icon: const Icon(Icons.edit_calendar),
                ),
                if (checkOut != null)
                  IconButton(
                    tooltip: 'Xóa giờ ra',
                    onPressed: () => setDialog(() => checkOut = null),
                    icon: const Icon(Icons.clear),
                  ),
              ]),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                if (checkOut != null && !checkOut!.isAfter(checkIn)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Giờ ra phải sau giờ vào.')));
                  return;
                }
                try {
                  final response = await http
                      .put(
                        Uri.parse('$apiBase/attendance/${row['id']}'),
                        headers: headers,
                        body: jsonEncode({
                          'checkIn': _toDateTimeOffsetIso(checkIn),
                          'checkOut': checkOut == null
                              ? null
                              : _toDateTimeOffsetIso(checkOut!),
                        }),
                      )
                      .timeout(const Duration(seconds: 12));
                  if (response.statusCode >= 300)
                    throw Exception(_apiError(
                        response.body, 'Không thể sửa giờ chấm công.'));
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (dialogContext.mounted)
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(_displayError(error))));
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteAttendance(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa bản ghi chấm công?'),
        content: Text('Xóa bản ghi của ${row['employeeName']}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final response = await http
          .delete(
            Uri.parse('$apiBase/attendance/${row['id']}'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 300)
        throw Exception(
            _apiError(response.body, 'Không thể xóa bản ghi chấm công.'));
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_displayError(error))));
    }
  }

  void _showNfcSetup() => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: const Text('Cấu hình thẻ NFC chấm công'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              const Text('Ghi nội dung này vào thẻ NFC của văn phòng:'),
              const SizedBox(height: 10),
              SelectableText(_officeAttendanceCode,
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, color: ink)),
              TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        const ClipboardData(text: _officeAttendanceCode));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Đã sao chép mã NFC.')));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Sao chép mã NFC')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Đóng'))
            ],
          ));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Quản trị nhân viên',
                style: TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              IconButton(
                  tooltip: 'Làm mới',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh)),
              IconButton(
                  tooltip: 'Cấu hình thẻ NFC',
                  onPressed: _showNfcSetup,
                  icon: const Icon(Icons.nfc)),
              IconButton(
                  tooltip: 'Đăng xuất',
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout))
            ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Thêm nhân viên')),
        body: SafeArea(
            child: ListView(
                controller: _adminScrollController,
                padding: const EdgeInsets.all(20),
                children: [
              Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF244FC7), Color(0xFF5886F7)]),
                      borderRadius: BorderRadius.circular(24)),
                  child: Row(children: [
                    const Icon(Icons.admin_panel_settings,
                        color: Colors.white, size: 42),
                    const SizedBox(width: 15),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              'Xin chào, ${widget.session.employee.displayName}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold)),
                        ]))
                  ])),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openOwnAttendance,
                  icon: const Icon(Icons.how_to_reg),
                  label: const Text('Chấm công của tôi'),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: _metric('Tài khoản', '${employees.length}',
                        Icons.people_outline)),
                const SizedBox(width: 10),
                Expanded(
                    child: _metric(
                        'Quản trị',
                        '${employees.where((e) => e['role'] == 'Admin').length}',
                        Icons.shield_outlined)),
                const SizedBox(width: 10),
                Expanded(
                    child: _metric('Bản ghi', '${attendance.length}',
                        Icons.schedule_outlined)),
              ]),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(
                    child: Text('Danh sách tài khoản',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: ink))),
                Chip(
                    label: Text(
                        '${visibleEmployees.length} / ${employees.length}'))
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Tìm theo tên, tài khoản, email hoặc phòng ban',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final filter in ['Tất cả', 'Admin', 'Employee'])
                  ChoiceChip(
                    label: Text(switch (filter) {
                      'Admin' => 'Quản trị viên',
                      'Employee' => 'Nhân viên',
                      _ => filter,
                    }),
                    selected: accountFilter == filter,
                    onSelected: (_) => setState(() => accountFilter = filter),
                  ),
              ]),
              if (loading)
                const Padding(
                    padding: EdgeInsets.all(35),
                    child: Center(child: CircularProgressIndicator())),
              if (error != null)
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.cloud_off,
                            color: Colors.deepOrange),
                        title: const Text('Không tải được dữ liệu'),
                        subtitle: Text(error!),
                        trailing: IconButton(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh)))),
              if (!loading && visibleEmployees.isEmpty)
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.search_off),
                        title: Text('Không tìm thấy tài khoản phù hợp'))),
              ...visibleEmployees.map((e) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () => _edit(employee: e),
                    leading: _accountAvatar(e['avatarBase64'] as String?),
                    title: Text('${e['displayName']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${e['username']} · ${e['department']}\n${e['email']}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _edit(employee: e);
                          if (v == 'delete') _delete(e);
                        },
                        itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'edit', child: Text('Sửa')),
                              if (e['id'] != widget.session.employee.id)
                                const PopupMenuItem(
                                    value: 'delete', child: Text('Xóa')),
                            ]),
                  ))),
              const SizedBox(height: 20),
              Text('Lịch sử chấm công',
                  key: _attendanceSectionKey,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 10),
              if (attendance.isEmpty && !loading)
                const Card(
                    child: ListTile(title: Text('Chưa có bản ghi chấm công'))),
              ...visibleAttendance.map((record) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                          '${record['employeeName']} · ${record['username']}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${_formatAttendanceTime(record['checkIn'])}  →  ${record['checkOut'] == null ? 'Chưa chấm ra' : _formatAttendanceTime(record['checkOut'])}'
                          '${_coordinateLabel(record['checkInLatitude'], record['checkInLongitude']) == null ? '' : '\nVị trí vào: ${_coordinateLabel(record['checkInLatitude'], record['checkInLongitude'])}'}'
                          '${_coordinateLabel(record['checkOutLatitude'], record['checkOutLongitude']) == null ? '' : '\nVị trí ra: ${_coordinateLabel(record['checkOutLatitude'], record['checkOutLongitude'])}'}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') _editAttendance(record);
                          if (value == 'delete') _deleteAttendance(record);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Sửa giờ')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Xóa bản ghi')),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 80),
            ])),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _adminSection,
          onDestinationSelected: _selectAdminSection,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.manage_accounts_outlined),
                selectedIcon: Icon(Icons.manage_accounts),
                label: 'Nhân viên'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Bảng công'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Cá nhân'),
          ],
        ),
      );
}

String _formatAttendanceTime(dynamic value) {
  final time = DateTime.parse(value as String).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)}';
}

String _toDateTimeOffsetIso(DateTime value) {
  if (value.isUtc) return value.toIso8601String();
  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final hours = absolute.inHours.toString().padLeft(2, '0');
  final minutes = absolute.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${value.toIso8601String()}$sign$hours:$minutes';
}

class RoleHome extends StatelessWidget {
  const RoleHome({super.key, required this.session, required this.onLogout});
  final _Session session;
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Không gian tài khoản'), actions: [
        IconButton(
            tooltip: 'Đăng xuất',
            onPressed: onLogout,
            icon: const Icon(Icons.logout))
      ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(
                        radius: 38,
                        backgroundColor: const Color(0xFFE8EDFF),
                        child: const Icon(Icons.person_outline,
                            size: 38, color: blue)),
                    const SizedBox(height: 18),
                    Text('Xin chào, ${session.employee.displayName}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: ink)),
                    const SizedBox(height: 8),
                    Text(
                        'Vai trò tài khoản chưa được hỗ trợ. Vui lòng liên hệ quản trị viên.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.blueGrey.shade700, height: 1.5))
                  ])))),
    );
  }
}
