
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JimpitanPage extends StatefulWidget {
  const JimpitanPage({super.key});

  @override
  State<JimpitanPage> createState() => _JimpitanPageState();
}

class _JimpitanPageState extends State<JimpitanPage> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool saving = false;

  String role = '';
  String? officerId;
  String? selectedPeriodId;

  List<Map<String, dynamic>> periods = [];
  List<Map<String, dynamic>> residents = [];
  List<Map<String, dynamic>> records = [];

  final Map<String, Map<String, dynamic>> recordByResident = {};

  final Map<String, String> statusLabels = {
    'pending': 'Belum dicatat',
    'collected': 'Sudah diambil',
    'not_home': 'Tidak di rumah',
    'refused': 'Menolak',
    'skipped': 'Dilewati',
  };

  @override
  void initState() {
    super.initState();
    loadData();
  }

  bool get isAdmin => role == 'admin';

  String formatDate(String? value) {
    if (value == null || value.isEmpty) return '-';

    final date = DateTime.tryParse(value);
    if (date == null) return value;

    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String formatRupiah(dynamic value) {
    final amount = (value as num?)?.toDouble() ?? 0;
    final text = amount.toStringAsFixed(0);

    final result = text.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => '.',
    );

    return 'Rp$result';
  }

  Future<void> loadData() async {
    if (!mounted) return;

    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Sesi login tidak ditemukan.');
      }

      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      role = profile['role'] as String? ?? '';

      if (role != 'admin' && role != 'officer') {
        throw Exception(
          'Akses halaman ini hanya untuk admin dan petugas.',
        );
      }

      if (!isAdmin) {
        final officer = await supabase
            .from('officers')
            .select('id')
            .eq('profile_id', user.id)
            .maybeSingle();

        if (officer == null) {
          throw Exception('Data petugas tidak ditemukan.');
        }

        officerId = officer['id'].toString();
      }

      await loadPeriods();

      if (selectedPeriodId != null) {
        await loadResidents();
        await loadRecords();
      } else {
        residents = [];
        records = [];
        recordByResident.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> loadPeriods() async {
    final response = await supabase
        .from('collection_periods')
        .select()
        .order('period_start', ascending: false);

    periods = List<Map<String, dynamic>>.from(response);

    if (periods.isEmpty) {
      selectedPeriodId = null;
      return;
    }

    final exists = periods.any(
      (item) => item['id'].toString() == selectedPeriodId,
    );

    if (!exists) {
      selectedPeriodId = periods.first['id'].toString();
    }
  }

  Future<void> loadResidents() async {
    if (isAdmin) {
      final response = await supabase
          .from('residents')
          .select('id, resident_name, address')
          .eq('is_active', true)
          .order('resident_name');

      residents = List<Map<String, dynamic>>.from(response);
      return;
    }

    final assignments = await supabase
        .from('officer_resident_assignments')
        .select('resident_id')
        .eq('officer_id', officerId!);

    final residentIds = assignments
        .map((item) => item['resident_id'].toString())
        .toList();

    if (residentIds.isEmpty) {
      residents = [];
      return;
    }

    final response = await supabase
        .from('residents')
        .select('id, resident_name, address')
        .eq('is_active', true)
        .inFilter('id', residentIds)
        .order('resident_name');

    residents = List<Map<String, dynamic>>.from(response);
  }

  Future<void> loadRecords() async {
    final response = await supabase
        .from('collection_records')
        .select()
        .eq('period_id', selectedPeriodId!);

    records = List<Map<String, dynamic>>.from(response);

    recordByResident.clear();

    for (final record in records) {
      recordByResident[record['resident_id'].toString()] = record;
    }
  }

  Future<void> selectPeriod(String? value) async {
    if (value == null) return;

    setState(() {
      selectedPeriodId = value;
      loading = true;
    });

    try {
      await loadResidents();
      await loadRecords();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka periode: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> createPeriod() async {
    final nameController = TextEditingController();

    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (contextDialog, setDialogState) {
            return AlertDialog(
              title: const Text('Buat Periode Jimpitan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama periode',
                        hintText: 'Contoh: Jimpitan November 2026',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tanggal mulai',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: contextDialog,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );

                        if (picked != null) {
                          setDialogState(() {
                            startDate = picked;

                            if (endDate.isBefore(startDate)) {
                              endDate = startDate;
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(formatDate(startDate.toString())),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tanggal selesai',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: contextDialog,
                          initialDate: endDate,
                          firstDate: startDate,
                          lastDate: DateTime(2100),
                        );

                        if (picked != null) {
                          setDialogState(() => endDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(formatDate(endDate.toString())),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Nama periode harus diisi.'),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) {
      nameController.dispose();
      return;
    }

    try {
      setState(() => saving = true);

      final response = await supabase
          .from('collection_periods')
          .insert({
            'period_name': nameController.text.trim(),
            'period_start': startDate.toIso8601String().substring(0, 10),
            'period_end': endDate.toIso8601String().substring(0, 10),
            'status': 'open',
          })
          .select()
          .single();

      selectedPeriodId = response['id'].toString();

      await loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Periode berhasil dibuat.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat periode: $e')),
        );
      }
    } finally {
      nameController.dispose();

      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  // =====================================================
  // HAPUS PERIODE
  // Bisa digunakan untuk periode terbuka maupun tertutup.
  // =====================================================

  Future<void> deletePeriod() async {
    if (!isAdmin || selectedPeriodId == null) return;

    final periodId = selectedPeriodId!;

    final selected = periods.where(
      (item) => item['id'].toString() == periodId,
    );

    if (selected.isEmpty) return;

    final period = selected.first;
    final periodName = period['period_name']?.toString() ?? '-';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hapus periode?'),
          content: Text(
            'Periode "$periodName" akan dihapus permanen.\n\n'
            'Seluruh catatan jimpitan dan transaksi pemasukan '
            'yang terhubung dengan periode ini juga akan dihapus.\n\n'
            'Tindakan ini tidak dapat dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Hapus Permanen'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      setState(() => saving = true);

      // 1. Ambil seluruh catatan jimpitan dalam periode.
      final recordResponse = await supabase
          .from('collection_records')
          .select('id')
          .eq('period_id', periodId);

      final recordIds = List<Map<String, dynamic>>.from(recordResponse)
          .map((item) => item['id'].toString())
          .toList();

      // 2. Hapus transaksi yang terhubung ke catatan jimpitan.
      if (recordIds.isNotEmpty) {
        await supabase
            .from('transactions')
            .delete()
            .inFilter('collection_record_id', recordIds);

        // Periksa apakah transaksi terkait masih tersisa.
        final remainingTransactions = await supabase
            .from('transactions')
            .select('id')
            .inFilter('collection_record_id', recordIds);

        if (remainingTransactions.isNotEmpty) {
          throw Exception(
            'Transaksi pemasukan belum berhasil dihapus. '
            'Periksa izin DELETE pada tabel transactions di Supabase.',
          );
        }
      }

      // 3. Hapus catatan jimpitan dalam periode.
      await supabase
          .from('collection_records')
          .delete()
          .eq('period_id', periodId);

      // 4. Pastikan catatan jimpitan benar-benar sudah terhapus.
      final remainingRecords = await supabase
          .from('collection_records')
          .select('id')
          .eq('period_id', periodId);

      if (remainingRecords.isNotEmpty) {
        throw Exception(
          'Catatan jimpitan masih tersimpan di database. '
          'Kemungkinan kebijakan RLS belum mengizinkan admin '
          'menghapus data pada tabel collection_records.',
        );
      }

      // 5. Hapus periode setelah semua catatan turunannya terhapus.
      await supabase
          .from('collection_periods')
          .delete()
          .eq('id', periodId);

      // 6. Pastikan periode benar-benar sudah terhapus.
      final remainingPeriod = await supabase
          .from('collection_periods')
          .select('id')
          .eq('id', periodId)
          .maybeSingle();

      if (remainingPeriod != null) {
        throw Exception(
          'Periode belum berhasil dihapus. '
          'Periksa izin DELETE pada tabel collection_periods.',
        );
      }

      selectedPeriodId = null;

      await loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Periode berhasil dihapus.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              'Gagal menghapus periode: '
              '${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }

      // Muat ulang data agar tampilan sesuai kondisi database.
      await loadData();
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> prepareRecords() async {
    if (selectedPeriodId == null || residents.isEmpty) return;

    try {
      setState(() => saving = true);

      final rows = residents.map((resident) {
        return {
          'period_id': selectedPeriodId,
          'resident_id': resident['id'],
          'status': 'pending',
          'amount_collected': 0,
        };
      }).toList();

      await supabase.from('collection_records').upsert(
        rows,
        onConflict: 'period_id,resident_id',
        ignoreDuplicates: true,
      );

      await loadRecords();

      if (mounted) {
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daftar pencatatan berhasil disiapkan.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyiapkan daftar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> editRecord(Map<String, dynamic> resident) async {
    final residentId = resident['id'].toString();
    final existing = recordByResident[residentId];

    final currentStatus = existing?['status']?.toString() ?? 'pending';

    final statusController = ValueNotifier<String>(currentStatus);

    final amountController = TextEditingController(
      text: existing == null
          ? ''
          : ((existing['amount_collected'] as num?) ?? 0)
              .toStringAsFixed(0),
    );

    final notesController = TextEditingController(
      text: existing?['notes']?.toString() ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (contextDialog, setDialogState) {
            return AlertDialog(
              title: const Text('Catat Jimpitan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resident['resident_name']?.toString() ?? '-',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: statusLabels.containsKey(currentStatus)
                          ? currentStatus
                          : 'pending',
                      decoration: const InputDecoration(
                        labelText: 'Status pencatatan',
                        border: OutlineInputBorder(),
                      ),
                      items: statusLabels.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          statusController.value = value;
                          setDialogState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    if (statusController.value == 'collected') ...[
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Nominal yang diterima',
                          prefixText: 'Rp ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Catatan (opsional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () {
                    if (statusController.value == 'collected') {
                      final amount = double.tryParse(
                        amountController.text.trim(),
                      );

                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Nominal harus lebih dari nol.'),
                          ),
                        );
                        return;
                      }
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      await saveRecord(
        residentId: residentId,
        residentName: resident['resident_name']?.toString() ?? '-',
        existing: existing,
        status: statusController.value,
        amount: statusController.value == 'collected'
            ? double.parse(amountController.text.trim())
            : 0,
        notes: notesController.text.trim(),
      );
    }

    statusController.dispose();
    amountController.dispose();
    notesController.dispose();
  }

  Future<void> saveRecord({
    required String residentId,
    required String residentName,
    required Map<String, dynamic>? existing,
    required String status,
    required double amount,
    required String notes,
  }) async {
    try {
      setState(() => saving = true);

      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Sesi login tidak ditemukan.');
      }

      final now = DateTime.now();

      final collectedAt = status == 'collected'
          ? now.toIso8601String()
          : null;

      final data = <String, dynamic>{
        'period_id': selectedPeriodId,
        'resident_id': residentId,
        'status': status,
        'amount_collected': amount,
        'collected_at': collectedAt,
        'notes': notes.isEmpty ? null : notes,
      };

      if (isAdmin) {
        if (existing != null && existing['officer_id'] != null) {
          data['officer_id'] = existing['officer_id'];
        }
      } else {
        data['officer_id'] = officerId;
      }

      // Simpan catatan jimpitan terlebih dahulu.
      final savedRecord = await supabase
          .from('collection_records')
          .upsert(
            data,
            onConflict: 'period_id,resident_id',
          )
          .select('id, collected_at')
          .single();

      final recordId = savedRecord['id'].toString();

      if (status == 'collected' && amount > 0) {
        final transactionDate = (
          savedRecord['collected_at']?.toString() ??
          now.toIso8601String()
        ).substring(0, 10);

        await supabase.from('transactions').upsert(
          {
            'transaction_type': 'income',
            'resident_id': residentId,
            'collection_record_id': recordId,
            'amount': amount,
            'transaction_date': transactionDate,
            'description': 'Pemasukan jimpitan - $residentName',
            'recorded_by': user.id,
          },
          onConflict: 'collection_record_id',
        );
      } else {
        await supabase
            .from('transactions')
            .delete()
            .eq('collection_record_id', recordId);
      }

      await loadRecords();

      if (mounted) {
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pencatatan jimpitan dan keuangan berhasil disinkronkan.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan pencatatan: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> closePeriod() async {
    if (selectedPeriodId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tutup periode?'),
        content: const Text(
          'Periode yang ditutup tidak dapat digunakan untuk '
          'pencatatan baru. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Tutup Periode'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => saving = true);

      await supabase
          .from('collection_periods')
          .update({'status': 'closed'})
          .eq('id', selectedPeriodId!);

      await loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Periode berhasil ditutup.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menutup periode: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPeriod = periods.where(
      (item) => item['id'].toString() == selectedPeriodId,
    );

    final period = selectedPeriod.isEmpty ? null : selectedPeriod.first;
    final isPeriodOpen = period?['status'] == 'open';

    final collectedCount = residents.where((resident) {
      return recordByResident[resident['id'].toString()]?['status'] ==
          'collected';
    }).length;

    final totalAmount = residents.fold<double>(0, (total, resident) {
      final record = recordByResident[resident['id'].toString()];

      if (record?['status'] != 'collected') return total;

      return total +
          ((record?['amount_collected'] as num?)?.toDouble() ?? 0);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jimpitan'),
        actions: [
          IconButton(
            onPressed: loading || saving ? null : loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isAdmin) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: saving ? null : createPeriod,
                        icon: const Icon(Icons.add),
                        label: const Text('Buat Periode Jimpitan'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (periods.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Belum ada periode jimpitan. '
                          'Admin dapat membuat periode baru.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedPeriodId,
                      decoration: const InputDecoration(
                        labelText: 'Pilih periode',
                        border: OutlineInputBorder(),
                      ),
                      items: periods.map((item) {
                        final label =
                            '${item['period_name']} '
                            '(${item['status'] == 'open' ? 'Dibuka' : 'Ditutup'})';

                        return DropdownMenuItem<String>(
                          value: item['id'].toString(),
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: saving ? null : selectPeriod,
                    ),
                    const SizedBox(height: 12),
                    if (period != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                period['period_name']?.toString() ?? '-',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${formatDate(period['period_start']?.toString())} - '
                                '${formatDate(period['period_end']?.toString())}',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _summaryItem(
                                      'Sudah diambil',
                                      '$collectedCount/${residents.length}',
                                    ),
                                  ),
                                  Expanded(
                                    child: _summaryItem(
                                      'Total terkumpul',
                                      formatRupiah(totalAmount),
                                    ),
                                  ),
                                ],
                              ),
                              if (isAdmin) ...[
                                const SizedBox(height: 12),
                                if (isPeriodOpen)
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: saving ? null : closePeriod,
                                      child: const Text('Tutup Periode'),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: saving ? null : deletePeriod,
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'Hapus Periode',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (isPeriodOpen) ...[
                      OutlinedButton.icon(
                        onPressed: saving ? null : prepareRecords,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Siapkan Daftar Warga'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Daftar Warga (${residents.length})',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (residents.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Belum ada warga yang ditugaskan kepada petugas ini, '
                            'atau belum ada warga aktif.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ...residents.map((resident) {
                      final residentId = resident['id'].toString();
                      final record = recordByResident[residentId];

                      final status =
                          record?['status']?.toString() ?? 'pending';

                      final amount = record?['amount_collected'] ?? 0;

                      final canEdit = isPeriodOpen &&
                          (isAdmin || role == 'officer');

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
                                          resident['resident_name']
                                                  ?.toString() ??
                                              '-',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          resident['address']?.toString() ??
                                              '-',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _statusBadge(status),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      status == 'collected'
                                          ? formatRupiah(amount)
                                          : statusLabels[status] ??
                                              'Belum dicatat',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (canEdit)
                                    TextButton.icon(
                                      onPressed: saving
                                          ? null
                                          : () => editRecord(resident),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        record == null ? 'Catat' : 'Ubah',
                                      ),
                                    ),
                                ],
                              ),
                              if (record?['notes'] != null &&
                                  record!['notes']
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                const Divider(),
                                Text(
                                  'Catatan: ${record['notes']}',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: saving
          ? const LinearProgressIndicator(minHeight: 2)
          : null,
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    Color color;

    switch (status) {
      case 'collected':
        color = Colors.green;
        break;
      case 'not_home':
        color = Colors.orange;
        break;
      case 'refused':
        color = Colors.red;
        break;
      case 'skipped':
        color = Colors.blueGrey;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusLabels[status] ?? 'Belum dicatat',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
