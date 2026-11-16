
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DataWargaPage extends StatefulWidget {
  const DataWargaPage({super.key});

  @override
  State<DataWargaPage> createState() => _DataWargaPageState();
}

class _DataWargaPageState extends State<DataWargaPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> warga = [];
  bool isLoading = true;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _loadResidents();
  }

  Future<void> _loadResidents() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final result = await supabase
          .from('residents')
          .select(
            'id, profile_id, resident_name, address, notes, is_active',
          )
          .order('resident_name');

      if (!mounted) return;

      setState(() {
        warga = List<Map<String, dynamic>>.from(result);
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
  // TAMBAH WARGA
  // =====================================================

  Future<void> _showAddResidentDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddResidentDialog(),
    );

    if (!mounted || result != true) return;

    await _loadResidents();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Akun warga berhasil dibuat.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // =====================================================
  // RESET PASSWORD
  // =====================================================

  Future<void> _showResetPasswordDialog(
    Map<String, dynamic> item,
  ) async {
    final profileId = item['profile_id']?.toString();

    if (profileId == null || profileId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ID akun warga tidak ditemukan.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResetPasswordDialog(
        profileId: profileId,
        residentName: item['resident_name']?.toString() ?? '-',
      ),
    );

    if (!mounted || result != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Password ${item['resident_name']} berhasil direset.',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  // =====================================================
  // KARTU WARGA
  // =====================================================

  Widget _buildResidentCard(Map<String, dynamic> item) {
    final active = item['is_active'] == true;

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['resident_name']?.toString() ?? '-',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item['address']?.toString() ?? '-',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if ((item['notes'] ?? '').toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          'Catatan: ${item['notes']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  active ? 'Aktif' : 'Nonaktif',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _showResetPasswordDialog(item),
                icon: const Icon(Icons.lock_reset, size: 18),
                label: const Text('Reset Password'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF256B50),
                ),
              ),
            ),
          ],
        ),
      ),
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
        title: const Text(
          'Data Warga',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isLoading ? null : _showAddResidentDialog,
        backgroundColor: const Color(0xFF256B50),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Warga'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadResidents,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              '${warga.length} warga terdaftar',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 15),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(35),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (loadError != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('Gagal memuat data warga.'),
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
                      onPressed: _loadResidents,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              )
            else if (warga.isEmpty)
              const Padding(
                padding: EdgeInsets.all(35),
                child: Center(
                  child: Text('Belum ada data warga.'),
                ),
              )
            else
              ...warga.map(_buildResidentCard),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// DIALOG TAMBAH WARGA
// =======================================================

class _AddResidentDialog extends StatefulWidget {
  const _AddResidentDialog();

  @override
  State<_AddResidentDialog> createState() => _AddResidentDialogState();
}

class _AddResidentDialogState extends State<_AddResidentDialog> {
  final supabase = Supabase.instance.client;
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final notesController = TextEditingController();

  bool saving = false;
  bool obscurePassword = true;
  String? errorMessage;

  @override
  void dispose() {
    nameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    addressController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> saveResident() async {
    if (saving) return;

    if (!formKey.currentState!.validate()) return;

    setState(() {
      saving = true;
      errorMessage = null;
    });

    try {
      final result = await supabase.functions.invoke(
        'create-user',
        body: {
          'full_name': nameController.text.trim(),
          'username': usernameController.text.trim().toLowerCase(),
          'password': passwordController.text,
          'phone': phoneController.text.trim(),
          'address': addressController.text.trim(),
          'notes': notesController.text.trim(),
          'role': 'resident',
        },
      );

      if (result.status < 200 || result.status >= 300) {
        final data = result.data;
        final message = data is Map
            ? data['message']?.toString() ?? data['error']?.toString()
            : null;

        throw Exception(message ?? 'Gagal membuat akun warga.');
      }

      if (result.data is Map && result.data['success'] != true) {
        throw Exception(
          result.data['message']?.toString() ??
              result.data['error']?.toString() ??
              'Gagal membuat akun warga.',
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Tambah Warga',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  enabled: !saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama lengkap',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nama wajib diisi.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: usernameController,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'Contoh: budi01',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final username = (value ?? '').trim().toLowerCase();

                    if (!RegExp(
                      r'^[a-z0-9][a-z0-9._-]{2,29}$',
                    ).hasMatch(username)) {
                      return 'Username 3–30 karakter, tanpa spasi.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  enabled: !saving,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password awal',
                    helperText: 'Minimal 8 karakter',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: saving
                          ? null
                          : () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 8) {
                      return 'Password minimal 8 karakter.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  enabled: !saving,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Nomor HP (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressController,
                  enabled: !saving,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Alamat',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Alamat wajib diisi.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  enabled: !saving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: saving ? null : saveResident,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF256B50),
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
  }
}

// =======================================================
// DIALOG RESET PASSWORD
// =======================================================

class _ResetPasswordDialog extends StatefulWidget {
  final String profileId;
  final String residentName;

  const _ResetPasswordDialog({
    required this.profileId,
    required this.residentName,
  });

  @override
  State<_ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final supabase = Supabase.instance.client;
  final formKey = GlobalKey<FormState>();

  final passwordController = TextEditingController();
  final confirmController = TextEditingController();

  bool saving = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;
  String? errorMessage;

  @override
  void dispose() {
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> resetPassword() async {
    if (saving) return;

    if (!formKey.currentState!.validate()) return;

    setState(() {
      saving = true;
      errorMessage = null;
    });

    try {
      final result = await supabase.functions.invoke(
        'reset-user-password',
        body: {
          'user_id': widget.profileId,
          'new_password': passwordController.text,
        },
      );

      if (result.status < 200 || result.status >= 300) {
        final data = result.data;
        final message = data is Map
            ? data['message']?.toString() ?? data['error']?.toString()
            : null;

        throw Exception(message ?? 'Gagal mereset password.');
      }

      if (result.data is Map && result.data['success'] != true) {
        throw Exception(
          result.data['message']?.toString() ??
              result.data['error']?.toString() ??
              'Gagal mereset password.',
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Reset Password Warga',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 380,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.residentName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Buat password sementara baru. Warga wajib menggantinya saat login berikutnya.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: passwordController,
                  enabled: !saving,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password baru',
                    helperText: 'Minimal 8 karakter',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: saving
                          ? null
                          : () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 8) {
                      return 'Password minimal 8 karakter.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmController,
                  enabled: !saving,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Ulangi password baru',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: saving
                          ? null
                          : () {
                              setState(() {
                                obscureConfirm = !obscureConfirm;
                              });
                            },
                      icon: Icon(
                        obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value != passwordController.text) {
                      return 'Konfirmasi password tidak sama.';
                    }
                    return null;
                  },
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: saving ? null : resetPassword,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF256B50),
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
              : const Text('Reset Password'),
        ),
      ],
    );
  }
}
