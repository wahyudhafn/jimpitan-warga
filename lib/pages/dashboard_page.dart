
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data_warga_page.dart';
import 'data_petugas_page.dart';
import 'jimpitan_page.dart';
import 'keuangan_page.dart';
import 'laporan_page.dart';
import 'setting_page.dart';

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
  final supabase = Supabase.instance.client;

  int totalWarga = 0;

  double totalPemasukan = 0;
  double totalPengeluaran = 0;

  bool isLoading = true;
  String? dashboardError;

  bool get isAdmin => widget.role.toLowerCase() == 'admin';
  bool get isOfficer => widget.role.toLowerCase() == 'officer';

  double get saldo => totalPemasukan - totalPengeluaran;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  // =====================================================
  // FORMAT RUPIAH
  // =====================================================

  String _formatRupiah(num value) {
    final text = value.toStringAsFixed(0);

    final formatted = text.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => '.',
    );

    return 'Rp$formatted';
  }

  // =====================================================
  // MUAT RINGKASAN DASHBOARD
  // =====================================================

  Future<void> _loadDashboard() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      dashboardError = null;
    });

    try {
      final residentResponse = await supabase
          .from('residents')
          .select('id')
          .eq('is_active', true);

      double pemasukan = 0;
      double pengeluaran = 0;

      if (isAdmin) {
        final transactionResponse = await supabase
            .from('transactions')
            .select('transaction_type, amount');

        for (final item in transactionResponse) {
          final amount =
              (item['amount'] as num?)?.toDouble() ?? 0;

          if (item['transaction_type'] == 'income') {
            pemasukan += amount;
          } else if (item['transaction_type'] == 'expense') {
            pengeluaran += amount;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        totalWarga = residentResponse.length;
        totalPemasukan = pemasukan;
        totalPengeluaran = pengeluaran;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        dashboardError = e.toString();
        isLoading = false;
      });
    }
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
      await supabase.auth.signOut();
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
      await _loadDashboard();
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
      await _loadDashboard();
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
      await _loadDashboard();
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
      await _loadDashboard();
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
      await _loadDashboard();
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
      await _loadDashboard();
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
  // KARTU MENU
  // =====================================================

  Widget _buildMenu({
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openFeature(title),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 25,
                color: const Color(0xFF256B50),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // RINGKASAN WARGA
  // =====================================================

  Widget _buildResidentSummary() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Warga Aktif',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Jumlah warga terdaftar',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            else
              Text(
                '$totalWarga',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF256B50),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // KARTU RINGKASAN KEUANGAN
  // =====================================================

  Widget _buildFinanceSummary({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: color,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isLoading)
              const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatRupiah(amount),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // RINGKASAN KEUANGAN
  // =====================================================

  Widget _buildFinanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ringkasan Keuangan',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (dashboardError != null && !isLoading)
          Card(
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Ringkasan keuangan gagal dimuat.',
                    ),
                  ),
                  IconButton(
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _buildFinanceSummary(
                  title: 'Pemasukan',
                  amount: totalPemasukan,
                  color: const Color(0xFF218653),
                  icon: Icons.trending_up,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFinanceSummary(
                  title: 'Pengeluaran',
                  amount: totalPengeluaran,
                  color: const Color(0xFFD04B45),
                  icon: Icons.trending_down,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            color: const Color(0xFFEAF3EE),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo Keuangan',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Pemasukan dikurangi pengeluaran',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isLoading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  else
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _formatRupiah(saldo),
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: saldo < 0
                                ? Colors.red.shade700
                                : const Color(0xFF256B50),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _openFeature('Keuangan'),
            child: const Text('Buka Keuangan'),
          ),
        ),
      ],
    );
  }

  // =====================================================
  // TAMPILAN UTAMA
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'jimpitan',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Color(0xFF26352D),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: isLoading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Keluar',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboard,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Selamat datang,',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.name,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF26352D),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                isAdmin
                    ? 'Administrator'
                    : isOfficer
                        ? 'Petugas Jimpitan'
                        : 'Warga',
                style: const TextStyle(
                  color: Color(0xFF256B50),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 25),

              const Text(
                'Ringkasan',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),

              _buildResidentSummary(),

              if (isAdmin) ...[
                const SizedBox(height: 20),
                _buildFinanceSection(),
              ],

              if (dashboardError != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Gagal memuat sebagian data: $dashboardError',
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loadDashboard,
                    child: const Text('Coba lagi'),
                  ),
                ),
              ],

              const SizedBox(height: 25),

              const Text(
                'Menu Utama',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),

              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= 600 ? 3 : 2;

                  return GridView.count(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.15,
                    children: [
                      if (isAdmin)
                        _buildMenu(
                          title: 'Data Warga',
                          description: 'Kelola data warga',
                          icon: Icons.people_outline,
                        ),

                      if (isAdmin)
                        _buildMenu(
                          title: 'Data Petugas',
                          description: 'Kelola petugas',
                          icon: Icons.badge_outlined,
                        ),

                      if (isAdmin || isOfficer)
                        _buildMenu(
                          title: 'Jimpitan',
                          description: 'Catat pengumpulan',
                          icon: Icons.assignment_outlined,
                        ),

                      if (isAdmin)
                        _buildMenu(
                          title: 'Keuangan',
                          description:
                              'Pemasukan dan pengeluaran',
                          icon: Icons.account_balance_wallet_outlined,
                        ),

                      _buildMenu(
                        title: 'Laporan',
                        description: 'Lihat laporan jimpitan',
                        icon: Icons.bar_chart_outlined,
                      ),

                      if (isAdmin)
                        _buildMenu(
                          title: 'Pengaturan',
                          description: 'Pengaturan aplikasi',
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
    );
  }
}
