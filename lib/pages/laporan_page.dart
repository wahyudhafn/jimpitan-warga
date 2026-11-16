
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:public_file_saver/public_file_saver.dart';

class LaporanPage extends StatefulWidget {
  final String role;

  const LaporanPage({
    super.key,
    required this.role,
  });

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  bool isExporting = false;

  String? errorMessage;
  String? selectedPeriodId;

  List<Map<String, dynamic>> periods = [];
  List<Map<String, dynamic>> records = [];
  List<Map<String, dynamic>> transactions = [];

  Map<String, Map<String, dynamic>> residents = {};

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  // =====================================================
  // MEMUAT DATA
  // =====================================================

  Future<void> _loadReport() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Sesi login tidak ditemukan.');
      }

      final periodResponse = await supabase
          .from('collection_periods')
          .select(
            'id, period_name, period_start, period_end, status',
          )
          .order('period_start', ascending: false);

      periods = List<Map<String, dynamic>>.from(periodResponse);

      List<String>? allowedResidentIds;

      if (widget.role == 'resident') {
        final resident = await supabase
            .from('residents')
            .select('id')
            .eq('profile_id', user.id)
            .maybeSingle();

        if (resident == null) {
          throw Exception(
            'Data warga untuk akun ini tidak ditemukan.',
          );
        }

        allowedResidentIds = [resident['id'].toString()];
      } else if (widget.role == 'officer') {
        final officer = await supabase
            .from('officers')
            .select('id')
            .eq('profile_id', user.id)
            .maybeSingle();

        if (officer == null) {
          throw Exception('Data petugas tidak ditemukan.');
        }

        final assignments = await supabase
            .from('officer_resident_assignments')
            .select('resident_id')
            .eq('officer_id', officer['id']);

        allowedResidentIds = assignments
            .map<String>(
              (item) => item['resident_id'].toString(),
            )
            .toList();
      } else if (widget.role != 'admin') {
        throw Exception('Role akun tidak dikenali.');
      }

      // -------------------------------------------------
      // DATA JIMPITAN
      // -------------------------------------------------

      if (allowedResidentIds != null &&
          allowedResidentIds.isEmpty) {
        records = [];
      } else {
        var query = supabase
            .from('collection_records')
            .select(
              'id, period_id, resident_id, officer_id, status, '
              'amount_collected, collected_at, notes',
            );

        if (allowedResidentIds != null) {
          query = query.inFilter(
            'resident_id',
            allowedResidentIds,
          );
        }

        final response = await query;

        records = List<Map<String, dynamic>>.from(response);
      }

      // -------------------------------------------------
      // DATA TRANSAKSI KEUANGAN
      // -------------------------------------------------

      final transactionResponse = await supabase
          .from('transactions')
          .select(
            'id, transaction_type, resident_id, amount, '
            'transaction_date, description, recorded_by, created_at',
          )
          .order('transaction_date', ascending: false);

      transactions =
          List<Map<String, dynamic>>.from(transactionResponse);

      // -------------------------------------------------
      // MEMUAT DATA WARGA
      // -------------------------------------------------

      final residentIds = <String>{};

      for (final record in records) {
        if (record['resident_id'] != null) {
          residentIds.add(record['resident_id'].toString());
        }
      }

      for (final transaction in transactions) {
        if (transaction['resident_id'] != null) {
          residentIds.add(
            transaction['resident_id'].toString(),
          );
        }
      }

      residents = {};

      if (residentIds.isNotEmpty) {
        final residentResponse = await supabase
            .from('residents')
            .select('id, resident_name, address')
            .inFilter('id', residentIds.toList());

        for (final item in residentResponse) {
          residents[item['id'].toString()] =
              Map<String, dynamic>.from(item);
        }
      }

      if (selectedPeriodId != null &&
          !periods.any(
            (item) =>
                item['id'].toString() == selectedPeriodId,
          )) {
        selectedPeriodId = null;
      }

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = e
              .toString()
              .replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // =====================================================
  // FILTER PERIODE
  // =====================================================

  List<Map<String, dynamic>> get filteredRecords {
    if (selectedPeriodId == null) {
      return List<Map<String, dynamic>>.from(records);
    }

    return records.where((item) {
      return item['period_id'].toString() ==
          selectedPeriodId;
    }).toList();
  }

  List<Map<String, dynamic>> get filteredTransactions {
    if (selectedPeriodId == null) {
      return List<Map<String, dynamic>>.from(transactions);
    }

    final period = periods.firstWhere(
      (item) => item['id'].toString() == selectedPeriodId,
    );

    final startDate = _dateOnly(period['period_start']);
    final endDate = _dateOnly(period['period_end']);

    return transactions.where((item) {
      final transactionDate =
          _dateOnly(item['transaction_date']);

      if (transactionDate == null) return false;

      if (startDate != null &&
          transactionDate.compareTo(startDate) < 0) {
        return false;
      }

      if (endDate != null &&
          transactionDate.compareTo(endDate) > 0) {
        return false;
      }

      return true;
    }).toList();
  }

  String? _dateOnly(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return null;
    }

    final date = DateTime.tryParse(value.toString());

    if (date == null) return null;

    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // =====================================================
  // PERHITUNGAN JIMPITAN
  // =====================================================

  double get totalCollected {
    return filteredRecords
        .where((item) => item['status'] == 'collected')
        .fold<double>(
          0,
          (total, item) =>
              total + _toDouble(item['amount_collected']),
        );
  }

  int get collectedCount {
    return filteredRecords
        .where((item) => item['status'] == 'collected')
        .length;
  }

  int get pendingCount {
    return filteredRecords
        .where((item) => item['status'] == 'pending')
        .length;
  }

  int get notHomeCount {
    return filteredRecords
        .where((item) => item['status'] == 'not_home')
        .length;
  }

  int get refusedCount {
    return filteredRecords
        .where((item) => item['status'] == 'refused')
        .length;
  }

  int get skippedCount {
    return filteredRecords
        .where((item) => item['status'] == 'skipped')
        .length;
  }

  // =====================================================
  // PERHITUNGAN KEUANGAN
  // =====================================================

  double get totalIncome {
    return filteredTransactions
        .where((item) => item['transaction_type'] == 'income')
        .fold<double>(
          0,
          (total, item) => total + _toDouble(item['amount']),
        );
  }

  double get totalExpense {
    return filteredTransactions
        .where((item) => item['transaction_type'] == 'expense')
        .fold<double>(
          0,
          (total, item) => total + _toDouble(item['amount']),
        );
  }

  double get balance {
    return totalIncome - totalExpense;
  }

  // =====================================================
  // FORMAT DATA
  // =====================================================

  double _toDouble(dynamic value) {
    if (value == null) return 0;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatRupiah(num value) {
    final number = value.toInt().toString();
    final result = StringBuffer();

    for (int i = 0; i < number.length; i++) {
      result.write(number[i]);

      final remaining = number.length - i - 1;

      if (remaining > 0 && remaining % 3 == 0) {
        result.write('.');
      }
    }

    return 'Rp$result';
  }

  String _formatDate(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return '-';
    }

    final date = DateTime.tryParse(value.toString());

    if (date == null) return '-';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'collected':
        return 'Terkumpul';
      case 'pending':
        return 'Belum dikunjungi';
      case 'not_home':
        return 'Tidak di rumah';
      case 'refused':
        return 'Menolak';
      case 'skipped':
        return 'Dilewati';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'collected':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'not_home':
        return Colors.blue;
      case 'refused':
        return Colors.red;
      case 'skipped':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _transactionLabel(String type) {
    switch (type) {
      case 'income':
        return 'Pemasukan';
      case 'expense':
        return 'Pengeluaran';
      default:
        return type;
    }
  }

  String _periodName(dynamic periodId) {
    final period = periods.where(
      (item) =>
          item['id'].toString() == periodId.toString(),
    );

    if (period.isEmpty) {
      return 'Periode tidak ditemukan';
    }

    return period.first['period_name']?.toString() ?? '-';
  }

  String _residentName(dynamic residentId) {
    if (residentId == null) return '-';

    return residents[residentId.toString()]
            ?['resident_name']
        ?.toString() ??
        '-';
  }

  // =====================================================
  // EXPORT EXCEL
  // =====================================================

  Future<void> _exportExcel() async {
    if (isExporting) return;

    if (filteredRecords.isEmpty &&
        filteredTransactions.isEmpty) {
      _showMessage('Tidak ada data untuk diekspor.');
      return;
    }

    setState(() {
      isExporting = true;
    });

    try {
      final excel = Excel.createExcel();

      // =================================================
      // SHEET LAPORAN JIMPITAN
      // =================================================

      final jimpitanSheet = excel['Laporan Jimpitan'];

      final periodTitle = selectedPeriodId == null
          ? 'Semua Periode'
          : _periodName(selectedPeriodId);

      jimpitanSheet.appendRow([
        TextCellValue('LAPORAN JIMPITAN WARGA'),
      ]);

      jimpitanSheet.appendRow([
        TextCellValue('Periode'),
        TextCellValue(periodTitle),
      ]);

      jimpitanSheet.appendRow([
        TextCellValue('Tanggal Ekspor'),
        TextCellValue(
          _formatDate(DateTime.now().toIso8601String()),
        ),
      ]);

      jimpitanSheet.appendRow([
        TextCellValue('Total Jimpitan Terkumpul'),
        DoubleCellValue(totalCollected),
      ]);

      jimpitanSheet.appendRow([
        TextCellValue('Jumlah Terkumpul'),
        IntCellValue(collectedCount),
      ]);

      jimpitanSheet.appendRow([
        TextCellValue('Belum Dikunjungi'),
        IntCellValue(pendingCount),
      ]);

      jimpitanSheet.appendRow([
        TextCellValue('Tidak di Rumah'),
        IntCellValue(notHomeCount),
      ]);

      jimpitanSheet.appendRow([
        TextCellValue('Menolak'),
        IntCellValue(refusedCount),
      ]);

      jimpitanSheet.appendRow([
        TextCellValue('Dilewati'),
        IntCellValue(skippedCount),
      ]);

      jimpitanSheet.appendRow([]);

      jimpitanSheet.appendRow([
        TextCellValue('No'),
        TextCellValue('Nama Warga'),
        TextCellValue('Alamat'),
        TextCellValue('Periode'),
        TextCellValue('Status'),
        TextCellValue('Nominal'),
        TextCellValue('Tanggal Setoran'),
        TextCellValue('Catatan'),
      ]);

      final jimpitanData = filteredRecords;

      jimpitanData.sort((a, b) {
        return _residentName(a['resident_id'])
            .compareTo(_residentName(b['resident_id']));
      });

      for (int i = 0; i < jimpitanData.length; i++) {
        final record = jimpitanData[i];

        final resident =
            residents[record['resident_id'].toString()];

        jimpitanSheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(
            resident?['resident_name']?.toString() ?? 'Warga',
          ),
          TextCellValue(
            resident?['address']?.toString() ?? '-',
          ),
          TextCellValue(
            _periodName(record['period_id']),
          ),
          TextCellValue(
            _statusLabel(record['status']?.toString() ?? '-'),
          ),
          DoubleCellValue(
            _toDouble(record['amount_collected']),
          ),
          TextCellValue(
            _formatDate(record['collected_at']),
          ),
          TextCellValue(
            record['notes']?.toString() ?? '',
          ),
        ]);
      }

      // =================================================
      // SHEET LAPORAN KEUANGAN
      // =================================================

      final financeSheet = excel['Keuangan'];

      financeSheet.appendRow([
        TextCellValue('LAPORAN KEUANGAN JIMPITAN WARGA'),
      ]);

      financeSheet.appendRow([
        TextCellValue('Periode'),
        TextCellValue(periodTitle),
      ]);

      financeSheet.appendRow([
        TextCellValue('Tanggal Ekspor'),
        TextCellValue(
          _formatDate(DateTime.now().toIso8601String()),
        ),
      ]);

      financeSheet.appendRow([
        TextCellValue('Total Pemasukan'),
        DoubleCellValue(totalIncome),
      ]);

      financeSheet.appendRow([
        TextCellValue('Total Pengeluaran'),
        DoubleCellValue(totalExpense),
      ]);

      financeSheet.appendRow([
        TextCellValue('Saldo'),
        DoubleCellValue(balance),
      ]);

      financeSheet.appendRow([]);

      financeSheet.appendRow([
        TextCellValue('No'),
        TextCellValue('Jenis Transaksi'),
        TextCellValue('Tanggal'),
        TextCellValue('Nama Warga'),
        TextCellValue('Keterangan'),
        TextCellValue('Nominal'),
      ]);

      final financeData = filteredTransactions;

      financeData.sort((a, b) {
        final dateA =
            a['transaction_date']?.toString() ?? '';
        final dateB =
            b['transaction_date']?.toString() ?? '';

        return dateA.compareTo(dateB);
      });

      for (int i = 0; i < financeData.length; i++) {
        final transaction = financeData[i];

        final type =
            transaction['transaction_type']?.toString() ?? '-';

        financeSheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(_transactionLabel(type)),
          TextCellValue(
            _formatDate(transaction['transaction_date']),
          ),
          TextCellValue(
            _residentName(transaction['resident_id']),
          ),
          TextCellValue(
            transaction['description']?.toString() ?? '-',
          ),
          DoubleCellValue(
            _toDouble(transaction['amount']),
          ),
        ]);
      }

      // =================================================
      // SIMPAN FILE EXCEL
      // =================================================

      final List<int>? excelBytes = excel.encode();

      if (excelBytes == null || excelBytes.isEmpty) {
        throw Exception('Gagal membuat file Excel.');
      }

      final now = DateTime.now();

      final timestamp =
          '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';

      final fileName = 'Laporan_Jimpitan_$timestamp.xlsx';

      final result = await PublicFileSaver().save(
        bytes: Uint8List.fromList(excelBytes),
        fileName: fileName,
        useDialog: true,
      );

      if (!mounted) return;

      if (result == null) {
        _showMessage('Penyimpanan file dibatalkan atau gagal.');
      } else {
        _showMessage(
          'File Excel berhasil disimpan: ${result.fileName}',
          success: true,
        );
      }
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Gagal membuat Excel: '
        '${e.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) {
        setState(() {
          isExporting = false;
        });
      }
    }
  }

  // =====================================================
  // PESAN
  // =====================================================

  void _showMessage(
    String message, {
    bool success = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          IconButton(
            onPressed: isLoading ? null : _loadReport,
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
          ),
          IconButton(
            onPressed:
                isLoading || isExporting ? null : _exportExcel,
            icon: isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: 'Download Excel',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 42,
                color: Colors.red,
              ),
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadReport,
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReport,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPeriodFilter(),
          const SizedBox(height: 12),
          _buildExportButton(),

          const SizedBox(height: 24),
          _sectionTitle('Laporan Jimpitan'),
          const SizedBox(height: 12),
          _buildCollectionSummary(),
          const SizedBox(height: 16),
          _buildSummaryGrid(),
          const SizedBox(height: 16),
          _buildRecordList(),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),

          _sectionTitle('Laporan Keuangan'),
          const SizedBox(height: 12),
          _buildFinanceSummary(),
          const SizedBox(height: 16),
          _buildTransactionList(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // =====================================================
  // FILTER PERIODE
  // =====================================================

  Widget _buildPeriodFilter() {
    return DropdownButtonFormField<String?>(
      initialValue: selectedPeriodId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Pilih Periode',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.calendar_month),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Semua Periode'),
        ),
        ...periods.map((period) {
          return DropdownMenuItem<String?>(
            value: period['id'].toString(),
            child: Text(
              period['period_name']?.toString() ?? '-',
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ],
      onChanged: (value) {
        setState(() {
          selectedPeriodId = value;
        });
      },
    );
  }

  // =====================================================
  // TOMBOL EXPORT
  // =====================================================

  Widget _buildExportButton() {
    final hasData = filteredRecords.isNotEmpty ||
        filteredTransactions.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed:
            isExporting || !hasData ? null : _exportExcel,
        icon: isExporting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.download_outlined),
        label: Text(
          isExporting
              ? 'Membuat file Excel...'
              : 'Download Laporan Excel',
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF176B52),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // RINGKASAN JIMPITAN
  // =====================================================

  Widget _buildCollectionSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Jimpitan Terkumpul',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatRupiah(totalCollected),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$collectedCount catatan berhasil dikumpulkan',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: [
        _summaryItem(
          'Belum dikunjungi',
          pendingCount,
          Colors.orange,
        ),
        _summaryItem(
          'Tidak di rumah',
          notHomeCount,
          Colors.blue,
        ),
        _summaryItem(
          'Menolak',
          refusedCount,
          Colors.red,
        ),
        _summaryItem(
          'Dilewati',
          skippedCount,
          Colors.grey,
        ),
      ],
    );
  }

  Widget _summaryItem(
    String title,
    int count,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // RINCIAN JIMPITAN
  // =====================================================

  Widget _buildRecordList() {
    final data = filteredRecords;

    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('Belum ada data jimpitan.'),
        ),
      );
    }

    data.sort((a, b) {
      final dateA = a['collected_at']?.toString() ?? '';
      final dateB = b['collected_at']?.toString() ?? '';
      return dateB.compareTo(dateA);
    });

    return Column(
      children: data.map((record) {
        final resident =
            residents[record['resident_id'].toString()];

        final residentName =
            resident?['resident_name']?.toString() ?? 'Warga';

        final address =
            resident?['address']?.toString() ?? '-';

        final status =
            record['status']?.toString() ?? '-';

        final amount =
            _toDouble(record['amount_collected']);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            residentName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            address,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _periodName(record['period_id']),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      _formatRupiah(amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Tanggal setoran: '
                  '${_formatDate(record['collected_at'])}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
                if (record['notes'] != null &&
                    record['notes'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Catatan: ${record['notes']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // =====================================================
  // RINGKASAN KEUANGAN
  // =====================================================

  Widget _buildFinanceSummary() {
    return Column(
      children: [
        _financeSummaryItem(
          title: 'Total Pemasukan',
          amount: totalIncome,
          color: Colors.green,
        ),
        const SizedBox(height: 10),
        _financeSummaryItem(
          title: 'Total Pengeluaran',
          amount: totalExpense,
          color: Colors.red,
        ),
        const SizedBox(height: 10),
        _financeSummaryItem(
          title: 'Saldo',
          amount: balance,
          color: balance >= 0 ? Colors.blue : Colors.red,
        ),
      ],
    );
  }

  Widget _financeSummaryItem({
    required String title,
    required double amount,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            _formatRupiah(amount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // RINCIAN TRANSAKSI
  // =====================================================

  Widget _buildTransactionList() {
    final data = filteredTransactions;

    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('Belum ada transaksi keuangan.'),
        ),
      );
    }

    data.sort((a, b) {
      final dateA =
          a['transaction_date']?.toString() ?? '';
      final dateB =
          b['transaction_date']?.toString() ?? '';

      return dateB.compareTo(dateA);
    });

    return Column(
      children: data.map((transaction) {
        final type =
            transaction['transaction_type']?.toString() ?? '';

        final isIncome = type == 'income';

        final amount =
            _toDouble(transaction['amount']);

        final description =
            transaction['description']?.toString().trim() ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _transactionLabel(type),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isIncome
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                    Text(
                      '${isIncome ? '+' : '-'}${_formatRupiah(amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isIncome
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Tanggal: '
                  '${_formatDate(transaction['transaction_date'])}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
                if (transaction['resident_id'] != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Warga: '
                    '${_residentName(transaction['resident_id'])}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  'Keterangan: '
                  '${description.isEmpty ? '-' : description}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
