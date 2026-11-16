
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class KeuanganPage extends StatefulWidget {
  const KeuanganPage({super.key});

  @override
  State<KeuanganPage> createState() => _KeuanganPageState();
}

class _KeuanganPageState extends State<KeuanganPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> transactions = [];

  bool isLoading = true;
  bool isSaving = false;
  String? loadError;
  String selectedFilter = 'Semua';

  static const Color primaryColor = Color(0xFF256B50);
  static const Color backgroundColor = Color(0xFFF6F8F7);

  double get totalIncome {
    return transactions
        .where((item) => item['transaction_type'] == 'income')
        .fold<double>(
          0,
          (sum, item) => sum + _amount(item['amount']),
        );
  }

  double get totalExpense {
    return transactions
        .where((item) => item['transaction_type'] == 'expense')
        .fold<double>(
          0,
          (sum, item) => sum + _amount(item['amount']),
        );
  }

  double get balance => totalIncome - totalExpense;

  double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatRupiah(num value) {
    final rounded = value.round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);

      final remaining = digits.length - i - 1;

      if (remaining > 0 && remaining % 3 == 0) {
        buffer.write('.');
      }
    }

    return 'Rp ${rounded < 0 ? '-' : ''}$buffer';
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';

    final date = DateTime.tryParse(value.toString());

    if (date == null) return value.toString();

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _dateToDatabase(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  // =====================================================
  // MUAT TRANSAKSI
  // =====================================================

  Future<void> _loadTransactions() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final result = await supabase
          .from('transactions')
          .select('''
            id,
            transaction_type,
            resident_id,
            collection_record_id,
            officer_id,
            amount,
            transaction_date,
            description,
            recorded_by,
            created_at,
            residents!transactions_resident_id_fkey(
              resident_name
            ),
            profiles!transactions_recorded_by_fkey(
              full_name
            )
          ''')
          .order('transaction_date', ascending: false)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        transactions = List<Map<String, dynamic>>.from(result);
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadError = e.toString();
        isLoading = false;
      });
    }
  }

  // =====================================================
  // TAMBAH PENGELUARAN
  // =====================================================

  Future<void> _showAddExpenseDialog() async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    DateTime selectedDate = DateTime.now();
    bool saving = false;

    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (contextDialog, setDialogState) {
            Future<void> saveExpense() async {
              if (!formKey.currentState!.validate()) return;

              final userId = supabase.auth.currentUser?.id;

              if (userId == null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Sesi login tidak ditemukan.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Input hanya angka bulat Rupiah.
              final amount = double.tryParse(
                amountController.text.trim(),
              );

              if (amount == null || amount <= 0) return;

              setDialogState(() => saving = true);

              try {
                await supabase.from('transactions').insert({
                  'transaction_type': 'expense',
                  'amount': amount,
                  'transaction_date': _dateToDatabase(selectedDate),
                  'description':
                      descriptionController.text.trim().isEmpty
                          ? null
                          : descriptionController.text.trim(),
                  'recorded_by': userId,
                });

                if (!mounted || !dialogContext.mounted) return;

                Navigator.of(dialogContext).pop();

                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Pengeluaran berhasil disimpan.'),
                    backgroundColor: Colors.green,
                  ),
                );

                await _loadTransactions();
              } catch (e) {
                if (!mounted || !dialogContext.mounted) return;

                setDialogState(() => saving = false);

                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Gagal menyimpan pengeluaran: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text(
                'Tambah Pengeluaran',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Nominal pengeluaran',
                            prefixText: 'Rp ',
                            hintText: 'Contoh: 50000',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final amount = double.tryParse(
                              (value ?? '').trim(),
                            );

                            if (amount == null || amount <= 0) {
                              return 'Masukkan nominal yang valid.';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        InkWell(
                          onTap: saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: dialogContext,
                                    initialDate: selectedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );

                                  if (picked != null) {
                                    setDialogState(() {
                                      selectedDate = picked;
                                    });
                                  }
                                },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Tanggal pengeluaran',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_month),
                            ),
                            child: Text(
                              _formatDate(
                                selectedDate.toIso8601String(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: descriptionController,
                          maxLines: 3,
                          maxLength: 500,
                          textCapitalization:
                              TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Keterangan',
                            hintText:
                                'Contoh: Pembelian perlengkapan kegiatan',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: saving ? null : saveExpense,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();
    descriptionController.dispose();
  }

  // =====================================================
  // RINGKASAN KEUANGAN
  // =====================================================

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _formatRupiah(amount),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // FILTER TRANSAKSI
  // =====================================================

  List<Map<String, dynamic>> get filteredTransactions {
    if (selectedFilter == 'Pemasukan') {
      return transactions
          .where((item) => item['transaction_type'] == 'income')
          .toList();
    }

    if (selectedFilter == 'Pengeluaran') {
      return transactions
          .where((item) => item['transaction_type'] == 'expense')
          .toList();
    }

    return transactions;
  }

  Widget _buildFilter() {
    const filters = [
      'Semua',
      'Pemasukan',
      'Pengeluaran',
    ];

    return Wrap(
      spacing: 8,
      children: filters.map((filter) {
        final selected = selectedFilter == filter;

        return ChoiceChip(
          label: Text(filter),
          selected: selected,
          onSelected: (_) {
            setState(() {
              selectedFilter = filter;
            });
          },
          selectedColor: const Color(0xFFDCEBE2),
          labelStyle: TextStyle(
            color: selected ? primaryColor : Colors.grey.shade700,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
            color: selected
                ? const Color(0xFFB5D3C1)
                : Colors.grey.shade300,
          ),
        );
      }).toList(),
    );
  }

  // =====================================================
  // ITEM RIWAYAT TRANSAKSI
  // =====================================================

  Widget _buildTransactionItem(Map<String, dynamic> item) {
    final isIncome = item['transaction_type'] == 'income';

    final amount = _amount(item['amount']);
    final description =
        item['description']?.toString().trim() ?? '';

    final residentData = item['residents'];

    final resident = residentData is Map
        ? residentData['resident_name']?.toString() ?? ''
        : '';

    final recorderData = item['profiles'];

    final recorder = recorderData is Map
        ? recorderData['full_name']?.toString() ?? ''
        : '';

    final title = isIncome
        ? (resident.isNotEmpty ? resident : 'Pemasukan Jimpitan')
        : (description.isNotEmpty ? description : 'Pengeluaran');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isIncome
                  ? const Color(0xFFE4F2E9)
                  : const Color(0xFFFCE9E7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isIncome
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
              color: isIncome
                  ? Colors.green.shade700
                  : Colors.red.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _formatDate(item['transaction_date']),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (description.isNotEmpty && isIncome) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
                if (recorder.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Dicatat oleh: $recorder',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIncome ? '+' : '-'}${_formatRupiah(amount)}',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isIncome
                  ? Colors.green.shade700
                  : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // TAMPILAN UTAMA
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final visibleTransactions = filteredTransactions;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Keuangan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: isLoading ? null : _loadTransactions,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isSaving ? null : _showAddExpenseDialog,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Pengeluaran'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadTransactions,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Ringkasan Keuangan',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (isLoading && transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (loadError != null && transactions.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text('Gagal memuat data keuangan.'),
                    const SizedBox(height: 8),
                    Text(
                      loadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _loadTransactions,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              )
            else ...[
              _buildSummaryCard(
                title: 'Total Pemasukan',
                amount: totalIncome,
                color: Colors.green.shade700,
                icon: Icons.south_west,
              ),
              const SizedBox(height: 10),
              _buildSummaryCard(
                title: 'Total Pengeluaran',
                amount: totalExpense,
                color: Colors.red.shade700,
                icon: Icons.north_east,
              ),
              const SizedBox(height: 10),
              _buildSummaryCard(
                title: 'Saldo Kas',
                amount: balance,
                color: primaryColor,
                icon: Icons.account_balance_wallet_outlined,
              ),
            ],
            const SizedBox(height: 26),
            const Text(
              'Riwayat Transaksi',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _buildFilter(),
            const SizedBox(height: 14),
            if (isLoading && transactions.isNotEmpty)
              const LinearProgressIndicator(),
            if (loadError != null && transactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Gagal memperbarui data: $loadError',
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                  ),
                ),
              ),
            if (!isLoading && visibleTransactions.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Center(
                  child: Text(
                    selectedFilter == 'Semua'
                        ? 'Belum ada transaksi.'
                        : 'Belum ada transaksi $selectedFilter.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ...visibleTransactions.map(_buildTransactionItem),
            const SizedBox(height: 85),
          ],
        ),
      ),
    );
  }
}
