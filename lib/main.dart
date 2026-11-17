
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/data_warga_page.dart';
import 'pages/data_petugas_page.dart';
import 'pages/jimpitan_page.dart';
import 'pages/keuangan_page.dart';
import 'pages/laporan_page.dart';
import 'pages/setting_page.dart';

const String supabaseUrl =
    'https://zrtsqxrghrrilrrqsmjw.supabase.co';

const String supabasePublishableKey =
    'sb_publishable_SD2II1CIHe1Shgynl19xrA_LExZ43Iq';

const Color primaryColor = Color(0xFF176B52);
const Color headingColor = Color(0xFF174D3C);
const Color backgroundColor = Color(0xFFF6F8F6);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  runApp(const JimpitanApp());
}

class JimpitanApp extends StatelessWidget {
  const JimpitanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jimpitan Warga',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: Color(0xFFDDE4DF),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: Color(0xFFDDE4DF),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: primaryColor,
              width: 1.5,
            ),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// =====================================================
// AUTH GATE
// =====================================================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.hasData
            ? snapshot.data!.session
            : auth.currentSession;

        if (session == null) {
          return const LoginPage();
        }

        return RoleGate(
          key: ValueKey(session.user.id),
        );
      },
    );
  }
}

// =====================================================
// ROLE GATE
// =====================================================

class RoleGate extends StatefulWidget {
  const RoleGate({super.key});

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  late Future<Map<String, dynamic>> profileFuture;

  @override
  void initState() {
    super.initState();
    profileFuture = loadProfile();
  }

  Future<Map<String, dynamic>> loadProfile() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      throw Exception('Sesi pengguna tidak ditemukan.');
    }

    final profile = await client
        .from('profiles')
        .select('full_name, role, is_active, must_change_password')
        .eq('id', user.id)
        .single();

    if (profile['is_active'] != true) {
      await client.auth.signOut();
      throw Exception('Akun tidak aktif.');
    }

    return Map<String, dynamic>.from(profile);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage(
            message: 'Memuat akun...',
          );
        }

        if (snapshot.hasError) {
          return ErrorPage(
            message: 'Tidak dapat memuat data akun.',
            onRetry: () {
              setState(() {
                profileFuture = loadProfile();
              });
            },
          );
        }

        final profile = snapshot.data!;
        final role = profile['role'].toString().toLowerCase();
        final name = profile['full_name']?.toString() ?? '';

        if (profile['must_change_password'] == true) {
          return ChangePasswordNoticePage(
            name: name,
          );
        }

        switch (role) {
          case 'admin':
          case 'officer':
          case 'resident':
            return DashboardPage(
              role: role,
              name: name,
            );

          default:
            return const ErrorPage(
              message: 'Role akun tidak dikenali.',
            );
        }
      },
    );
  }
}

// =====================================================
// LOGIN PAGE
// =====================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  bool obscurePassword = true;
  bool loading = false;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final username =
        usernameController.text.trim().toLowerCase();

    final password = passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      showMessage('Username dan password wajib diisi.');
      return;
    }

    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,29}$')
        .hasMatch(username)) {
      showMessage('Format username tidak valid.');
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final response =
          await Supabase.instance.client.functions.invoke(
        'login-username',
        body: {
          'username': username,
          'password': password,
        },
      );

      final data = response.data;

      if (response.status < 200 || response.status >= 300) {
        throw Exception('Login gagal.');
      }

      if (data is! Map ||
          data['success'] != true ||
          data['access_token'] == null ||
          data['refresh_token'] == null) {
        throw Exception('Respons login tidak valid.');
      }

      await Supabase.instance.client.auth.setSession(
        data['refresh_token'].toString(),
      );

      if (!mounted) return;

      passwordController.clear();

      showMessage(
        'Login berhasil.',
        success: true,
      );
        } on FunctionException catch (e) {
      debugPrint('LOGIN FUNCTION STATUS: ${e.status}');
      debugPrint('LOGIN FUNCTION REASON: ${e.reasonPhrase}');
      debugPrint('LOGIN FUNCTION DETAILS: ${e.details}');

      if (!mounted) return;

      final details = e.details;
      String message = 'Login gagal. HTTP ${e.status}.';

      if (details is Map && details['error'] is String) {
        message = details['error'] as String;
      } else if (details is String && details.isNotEmpty) {
        message = details;
      }

      showMessage(message);
    } catch (e) {
      if (!mounted) return;

      showMessage(
        'Login gagal. Periksa koneksi atau konfigurasi server.',
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void showMessage(
    String message, {
    bool success = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? primaryColor : Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 25,
              vertical: 30,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 35),
                  const Text(
                    'Jimpitan Warga',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                      color: headingColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sistem pencatatan jimpitan warga',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF777777),
                    ),
                  ),
                  const SizedBox(height: 55),
                  const Text(
                    'Selamat Datang',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF222222),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Silakan masuk menggunakan akun Anda.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF777777),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Username',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: usernameController,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      hintText: 'Masukkan username',
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Password',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    onSubmitted: (_) {
                      if (!loading) login();
                    },
                    decoration: InputDecoration(
                      hintText: 'Masukkan password',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.black45,
                          size: 21,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: loading ? null : login,
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            const Color(0xFF8DA99D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 21,
                              height: 21,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'MASUK',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 23),
                  const Text(
                    'Lupa password? Hubungi admin RT.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF777777),
                    ),
                  ),
                  const SizedBox(height: 55),
                  const Text(
                    'Jimpitan Warga',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFAAAAAA),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// DASHBOARD
// =====================================================

class DashboardPage extends StatefulWidget {
  final String role;
  final String name;

  const DashboardPage({
    super.key,
    required this.role,
    required this.name,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, dynamic>> _dashboardSummary;

  bool get isAdmin => widget.role.toLowerCase() == 'admin';
  bool get isOfficer => widget.role.toLowerCase() == 'officer';

  @override
  void initState() {
    super.initState();
    _dashboardSummary = _loadDashboardSummary();
  }

  // =====================================================
  // MUAT RINGKASAN DASHBOARD
  // =====================================================

  Future<Map<String, dynamic>> _loadDashboardSummary() async {
    final supabase = Supabase.instance.client;

    final residents = await supabase
        .from('residents')
        .select('id');

    num totalIncome = 0;
    num totalExpense = 0;

    // Ringkasan keuangan hanya ditampilkan untuk admin.
    if (isAdmin) {
      final transactions = await supabase
          .from('transactions')
          .select('transaction_type, amount');

      for (final transaction in transactions) {
        final amount = num.tryParse(
              transaction['amount'].toString(),
            ) ??
            0;

        final type =
            transaction['transaction_type']?.toString();

        if (type == 'income') {
          totalIncome += amount;
        } else if (type == 'expense') {
          totalExpense += amount;
        }
      }
    }

    return {
      'total_warga': residents.length,
      'pemasukan': totalIncome,
      'pengeluaran': totalExpense,
    };
  }

  Future<void> _refreshDashboard() async {
    setState(() {
      _dashboardSummary = _loadDashboardSummary();
    });

    await _dashboardSummary;
  }

  String _formatRupiah(num amount) {
    final value = amount.round().toString();
    final buffer = StringBuffer();

    for (int i = 0; i < value.length; i++) {
      buffer.write(value[i]);

      final remaining = value.length - i - 1;

      if (remaining > 0 && remaining % 3 == 0) {
        buffer.write('.');
      }
    }

    return 'Rp${buffer.toString()}';
  }

  // =====================================================
  // LOGOUT
  // =====================================================

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar aplikasi?'),
        content: const Text(
          'Apakah Anda yakin ingin keluar dari akun ini?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal keluar: $e')),
      );
    }
  }

  // =====================================================
  // NAVIGASI MENU
  // =====================================================

  Future<void> _openFeature(String feature) async {
    if (feature == 'Data Warga') {
      if (!isAdmin) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DataWargaPage(),
        ),
      );

      if (!mounted) return;
      await _refreshDashboard();
      return;
    }

    if (feature == 'Data Petugas') {
      if (!isAdmin) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DataPetugasPage(),
        ),
      );

      if (!mounted) return;
      await _refreshDashboard();
      return;
    }

    if (feature == 'Jimpitan') {
      if (!isAdmin && !isOfficer) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const JimpitanPage(),
        ),
      );

      if (!mounted) return;
      await _refreshDashboard();
      return;
    }

    if (feature == 'Keuangan') {
      if (!isAdmin) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const KeuanganPage(),
        ),
      );

      if (!mounted) return;
      await _refreshDashboard();
      return;
    }

    if (feature == 'Laporan') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LaporanPage(
            role: widget.role,
          ),
        ),
      );

      if (!mounted) return;
      await _refreshDashboard();
      return;
    }

    if (feature == 'Pengaturan') {
      if (!isAdmin) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SettingPage(),
        ),
      );

      if (!mounted) return;
      await _refreshDashboard();
      return;
    }

    _showComingSoon(feature);
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$feature akan dibuat pada tahap berikutnya.',
        ),
      ),
    );
  }

  // =====================================================
  // KARTU RINGKASAN
  // =====================================================

  Widget _summaryCard({
    required String title,
    required Widget value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE6EAE8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: primaryColor,
            size: 23,
          ),
          const SizedBox(height: 15),
          Text(
            title,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 7),
          value,
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _dashboardSummary,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 25),
            child: Center(
              child: CircularProgressIndicator(
                color: primaryColor,
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE6EAE8),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'Gagal memuat ringkasan dashboard.',
                  style: TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _refreshDashboard,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba lagi'),
                ),
              ],
            ),
          );
        }

        final data = snapshot.data ?? {};

        final totalWarga =
            data['total_warga'] as int? ?? 0;

        final pemasukan =
            data['pemasukan'] as num? ?? 0;

        final pengeluaran =
            data['pengeluaran'] as num? ?? 0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth < 500 ? 2 : 3;

            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _summaryCard(
                  title: 'Total Warga',
                  icon: Icons.people_outline,
                  value: Text(
                    '$totalWarga',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: headingColor,
                    ),
                  ),
                ),
                if (isAdmin)
                  _summaryCard(
                    title: 'Pemasukan',
                    icon: Icons.trending_up,
                    value: Text(
                      _formatRupiah(pemasukan),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: headingColor,
                      ),
                    ),
                  ),
                if (isAdmin)
                  _summaryCard(
                    title: 'Pengeluaran',
                    icon: Icons.trending_down,
                    value: Text(
                      _formatRupiah(pengeluaran),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: headingColor,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // =====================================================
  // KARTU MENU
  // =====================================================

  Widget _menuCard({
    required String title,
    required String description,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () => _openFeature(title),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFE6EAE8),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: primaryColor,
              size: 25,
            ),
            const SizedBox(height: 13),
            Text(
              title,
              style: const TextStyle(
                color: headingColor,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // BUILD DASHBOARD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Jimpitan Warga',
          style: TextStyle(
            color: headingColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _logout,
            child: const Text(
              'Keluar',
              style: TextStyle(color: primaryColor),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshDashboard,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selamat datang, ${widget.name}',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: headingColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAdmin
                          ? 'Administrator'
                          : isOfficer
                              ? 'Petugas Jimpitan'
                              : 'Warga',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 25),
                    const Text(
                      'Ringkasan',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: headingColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryCards(),
                    const SizedBox(height: 28),
                    const Text(
                      'Menu Utama',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: headingColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns =
                            constraints.maxWidth < 500 ? 2 : 3;

                        return GridView.count(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.35,
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(),
                          children: [
                            if (isAdmin)
                              _menuCard(
                                title: 'Data Warga',
                                description: 'Kelola data warga',
                                icon: Icons.people_outline,
                              ),
                            if (isAdmin)
                              _menuCard(
                                title: 'Data Petugas',
                                description: 'Kelola akun petugas',
                                icon: Icons.badge_outlined,
                              ),
                            if (isAdmin || isOfficer)
                              _menuCard(
                                title: 'Jimpitan',
                                description: 'Atur dan catat setoran',
                                icon: Icons.receipt_long_outlined,
                              ),
                            if (isAdmin)
                              _menuCard(
                                title: 'Keuangan',
                                description:
                                    'Pemasukan dan pengeluaran',
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                            _menuCard(
                              title: 'Laporan',
                              description: 'Lihat rekap jimpitan',
                              icon: Icons.assessment_outlined,
                            ),
                            if (isAdmin)
                              _menuCard(
                                title: 'Pengaturan',
                                description: 'Atur aplikasi',
                                icon: Icons.settings_outlined,
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// PEMBERITAHUAN GANTI PASSWORD
// =====================================================

class ChangePasswordNoticePage extends StatefulWidget {
  final String name;

  const ChangePasswordNoticePage({
    super.key,
    required this.name,
  });

  @override
  State<ChangePasswordNoticePage> createState() =>
      _ChangePasswordNoticePageState();
}

class _ChangePasswordNoticePageState
    extends State<ChangePasswordNoticePage> {
  final _formKey = GlobalKey<FormState>();

  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      enabled: !_isLoading,
      validator: validator ??
          (value) {
            if (value == null || value.isEmpty) {
              return '$label wajib diisi.';
            }
            return null;
          },
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
          ),
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    final oldPassword = _oldPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konfirmasi password baru tidak sama.'),
        ),
      );
      return;
    }

    if (oldPassword == newPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password baru harus berbeda dari password lama.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response =
          await Supabase.instance.client.functions.invoke(
        'change-password',
        body: {
          'old_password': oldPassword,
          'new_password': newPassword,
        },
      );

      final data = response.data;

      if (data is! Map || data['success'] != true) {
        final message = data is Map && data['error'] is String
            ? data['error'] as String
            : 'Password gagal diperbarui.';

        throw Exception(message);
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Password Berhasil Diganti'),
            content: const Text(
              'Password akun Anda sudah diperbarui. '
              'Silakan login kembali menggunakan password baru.',
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await Supabase.instance.client.auth.signOut();
                },
                child: const Text('Kembali ke Login'),
              ),
            ],
          );
        },
      );
    } on FunctionException catch (error) {
      if (!mounted) return;

      String message =
          'Terjadi kesalahan saat menghubungi server.';

      final details = error.details;
      if (details is Map && details['error'] is String) {
        message = details['error'] as String;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;

      final message =
          error.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Ganti Password',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                      color: headingColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Halo ${widget.name}. Silakan ganti password awal '
                    'sebelum menggunakan aplikasi.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 30),
                  _passwordField(
                    label: 'Password Lama',
                    controller: _oldPasswordController,
                    obscure: _obscureOld,
                    onToggle: () {
                      setState(() => _obscureOld = !_obscureOld);
                    },
                  ),
                  const SizedBox(height: 16),
                  _passwordField(
                    label: 'Password Baru',
                    controller: _newPasswordController,
                    obscure: _obscureNew,
                    onToggle: () {
                      setState(() => _obscureNew = !_obscureNew);
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password baru wajib diisi.';
                      }
                      if (value.length < 8) {
                        return 'Password minimal 8 karakter.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _passwordField(
                    label: 'Ulangi Password Baru',
                    controller: _confirmPasswordController,
                    obscure: _obscureConfirm,
                    onToggle: () {
                      setState(
                        () => _obscureConfirm = !_obscureConfirm,
                      );
                    },
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed:
                          _isLoading ? null : _changePassword,
                      child: _isLoading
                          ? const SizedBox(
                              width: 21,
                              height: 21,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Simpan Password Baru'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Supabase.instance.client.auth.signOut();
                          },
                    child: const Text('Keluar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// LOADING PAGE
// =====================================================

class LoadingPage extends StatelessWidget {
  final String message;

  const LoadingPage({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: primaryColor,
            ),
            const SizedBox(height: 18),
            Text(
              message,
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// ERROR PAGE
// =====================================================

class ErrorPage extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorPage({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Coba Lagi'),
                ),
              ],
              const SizedBox(height: 15),
              TextButton(
                onPressed: () {
                  Supabase.instance.client.auth.signOut();
                },
                child: const Text('Keluar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
