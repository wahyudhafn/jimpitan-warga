
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DataPetugasPage extends StatefulWidget {
  const DataPetugasPage({super.key});

  @override
  State<DataPetugasPage> createState() => _DataPetugasPageState();
}

class _DataPetugasPageState extends State<DataPetugasPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> petugas = [];
  Map<String, int> assignmentCounts = {};

  bool isLoading = true;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _loadOfficers();
  }

  // =====================================================
  // MUAT DATA PETUGAS DAN JUMLAH WARGA
  // =====================================================

  Future<void> _loadOfficers() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        loadError = null;
      });
    }

    try {
      final result = await supabase
          .from('officers')
          .select('''
            id,
            profile_id,
            assigned_area,
            is_active,
            profiles!officers_profile_id_fkey(
              full_name,
              username,
              phone
            )
          ''')
          .order('created_at');

      final assignments = await supabase
          .from('officer_resident_assignments')
          .select('officer_id');

      final counts = <String, int>{};

      for (final assignment in assignments) {
        final officerId = assignment['officer_id'].toString();
        counts[officerId] = (counts[officerId] ?? 0) + 1;
      }

      if (!mounted) return;

      setState(() {
        petugas = List<Map<String, dynamic>>.from(result);
        assignmentCounts = counts;
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
  // TAMBAH PETUGAS
  // =====================================================

  Future<void> _showAddOfficerDialog() async {
    final formKey = GlobalKey<FormState>();

    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final phoneController = TextEditingController();
    final areaController = TextEditingController();

    bool saving = false;
    bool obscurePassword = true;

    final messenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> saveOfficer() async {
              if (!formKey.currentState!.validate()) return;

              setDialogState(() => saving = true);

              try {
                final result = await supabase.functions.invoke(
                  'create-user',
                  body: {
                    'full_name': nameController.text.trim(),
                    'username':
                        usernameController.text.trim().toLowerCase(),
                    'password': passwordController.text,
                    'phone': phoneController.text.trim(),
                    'assigned_area': areaController.text.trim(),
                    'role': 'officer',
                  },
                );

                if (result.status < 200 || result.status >= 300) {
                  final data = result.data;
                  final message = data is Map
                      ? data['message']?.toString() ??
                          data['error']?.toString()
                      : null;

                  throw Exception(
                    message ?? 'Gagal membuat akun petugas.',
                  );
                }

                if (result.data is Map &&
                    result.data['success'] != true) {
                  throw Exception(
                    result.data['message']?.toString() ??
                        result.data['error']?.toString() ??
                        'Gagal membuat akun petugas.',
                  );
                }

                if (!mounted || !dialogContext.mounted) return;

                Navigator.of(dialogContext).pop();

                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Akun petugas berhasil dibuat.'),
                    backgroundColor: Colors.green,
                  ),
                );

                await _loadOfficers();
              } catch (e) {
                if (!mounted || !dialogContext.mounted) return;

                setDialogState(() => saving = false);

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      e.toString().replaceFirst('Exception: ', ''),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text(
                'Tambah Petugas',
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
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            hintText: 'Contoh: petugas01',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final username =
                                (value ?? '').trim().toLowerCase();

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
                          obscureText: obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password awal',
                            helperText: 'Minimal 8 karakter',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setDialogState(() {
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
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Nomor HP (opsional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: areaController,
                          textCapitalization:
                              TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Wilayah tugas (opsional)',
                            hintText: 'Contoh: RT 01 / RW 02',
                            border: OutlineInputBorder(),
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
                  onPressed: saving ? null : saveOfficer,
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

    nameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    areaController.dispose();
  }

  // =====================================================
  // ATUR PEMBAGIAN WARGA
  // =====================================================

  Future<void> _showAssignmentDialog(
    Map<String, dynamic> item,
    String officerName,
  ) async {
    final officerId = item['id'].toString();
    final messenger = ScaffoldMessenger.of(context);

    List<Map<String, dynamic>> residents = [];
    Set<String> originalSelected = {};
    Set<String> selected = {};

    bool saving = false;
    String? error;

    try {
      final results = await Future.wait([
        supabase
            .from('residents')
            .select('id, resident_name, address, is_active')
            .order('resident_name'),
        supabase
            .from('officer_resident_assignments')
            .select('resident_id')
            .eq('officer_id', officerId),
      ]);

      residents = List<Map<String, dynamic>>.from(results[0]);

      final assignments =
          List<Map<String, dynamic>>.from(results[1]);

      originalSelected = assignments
          .map((row) => row['resident_id'].toString())
          .toSet();

      selected = Set<String>.from(originalSelected);
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;

    if (error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal memuat daftar warga: $error'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (contextDialog, setDialogState) {
            Future<void> saveAssignments() async {
              setDialogState(() => saving = true);

              try {
                final removed =
                    originalSelected.difference(selected).toList();

                final added =
                    selected.difference(originalSelected).toList();

                if (removed.isNotEmpty) {
                  await supabase
                      .from('officer_resident_assignments')
                      .delete()
                      .eq('officer_id', officerId)
                      .inFilter('resident_id', removed);
                }

                if (added.isNotEmpty) {
                  await supabase
                      .from('officer_resident_assignments')
                      .insert(
                    added.map((residentId) {
                      return {
                        'officer_id': officerId,
                        'resident_id': residentId,
                      };
                    }).toList(),
                  );
                }

                if (!mounted || !dialogContext.mounted) return;

                Navigator.of(dialogContext).pop();

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Pembagian warga untuk $officerName berhasil disimpan.',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );

                await _loadOfficers();
              } catch (e) {
                if (!mounted || !dialogContext.mounted) return;

                setDialogState(() => saving = false);

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Gagal menyimpan pembagian: ${e.toString()}',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text(
                'Pembagian Warga',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 460,
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      officerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${selected.length} warga dipilih',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const Divider(height: 24),
                    Expanded(
                      child: residents.isEmpty
                          ? const Center(
                              child: Text('Belum ada data warga.'),
                            )
                          : ListView.builder(
                              itemCount: residents.length,
                              itemBuilder: (context, index) {
                                final resident = residents[index];
                                final id = resident['id'].toString();
                                final name =
                                    resident['resident_name']?.toString() ??
                                        '-';
                                final address =
                                    resident['address']?.toString() ?? '';
                                final active =
                                    resident['is_active'] == true;

                                return CheckboxListTile(
                                  value: selected.contains(id),
                                  onChanged: saving
                                      ? null
                                      : (checked) {
                                          setDialogState(() {
                                            if (checked == true) {
                                              selected.add(id);
                                            } else {
                                              selected.remove(id);
                                            }
                                          });
                                        },
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (address.isNotEmpty) address,
                                      if (!active) 'Warga nonaktif',
                                    ].join(' • '),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: active
                                          ? Colors.grey.shade600
                                          : Colors.red.shade700,
                                    ),
                                  ),
                                  dense: true,
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Centang nama warga yang menjadi tanggung jawab petugas ini.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
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
                  onPressed: saving ? null : saveAssignments,
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
                      : const Text('Simpan Pembagian'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =====================================================
  // RESET PASSWORD PETUGAS
  // =====================================================

  Future<void> _showResetPasswordDialog(
    Map<String, dynamic> item,
    String officerName,
  ) async {
    final profileId = item['profile_id']?.toString();

    if (profileId == null || profileId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ID akun petugas tidak ditemukan.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    bool saving = false;
    bool obscurePassword = true;
    bool obscureConfirm = true;

    final messenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (contextDialog, setDialogState) {
            Future<void> resetPassword() async {
              if (!formKey.currentState!.validate()) return;

              setDialogState(() => saving = true);

              try {
                final result = await supabase.functions.invoke(
                  'reset-user-password',
                  body: {
                    'user_id': profileId,
                    'new_password': passwordController.text,
                  },
                );

                if (result.status < 200 || result.status >= 300) {
                  final data = result.data;
                  final message = data is Map
                      ? data['message']?.toString() ??
                          data['error']?.toString()
                      : null;

                  throw Exception(
                    message ?? 'Gagal mereset password.',
                  );
                }

                if (result.data is Map &&
                    result.data['success'] != true) {
                  throw Exception(
                    result.data['message']?.toString() ??
                        'Gagal mereset password.',
                  );
                }

                if (!mounted || !dialogContext.mounted) return;

                Navigator.of(dialogContext).pop();

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Password $officerName berhasil direset.',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted || !dialogContext.mounted) return;

                setDialogState(() => saving = false);

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      e.toString().replaceFirst('Exception: ', ''),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text(
                'Reset Password Petugas',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 380,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          officerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Buat password sementara baru. Petugas wajib menggantinya saat login berikutnya.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password baru',
                          helperText: 'Minimal 8 karakter',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
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
                        obscureText: obscureConfirm,
                        decoration: InputDecoration(
                          labelText: 'Ulangi password baru',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
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
                    ],
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
          },
        );
      },
    );

    passwordController.dispose();
    confirmController.dispose();
  }

  // =====================================================
  // KARTU PETUGAS
  // =====================================================

  Widget _buildOfficerCard(Map<String, dynamic> item) {
    final profile = item['profiles'] as Map<String, dynamic>? ?? {};
    final active = item['is_active'] == true;

    final officerId = item['id'].toString();
    final name = profile['full_name']?.toString() ?? '-';
    final username = profile['username']?.toString() ?? '-';
    final phone = profile['phone']?.toString() ?? '';
    final area = item['assigned_area']?.toString() ?? '';
    final residentCount = assignmentCounts[officerId] ?? 0;

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
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Username: $username',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'HP: $phone',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                      if (area.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Wilayah: $area',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6F3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 19,
                    color: Color(0xFF256B50),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$residentCount warga ditugaskan',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF256B50),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showAssignmentDialog(item, name),
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: const Text('Atur Warga'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF256B50),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showResetPasswordDialog(item, name),
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: const Text('Reset Password'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF256B50),
                  ),
                ),
              ],
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
          'Data Petugas',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddOfficerDialog,
        backgroundColor: const Color(0xFF256B50),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Petugas'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadOfficers,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              '${petugas.length} petugas terdaftar',
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
                    const Text('Gagal memuat data petugas.'),
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
                      onPressed: _loadOfficers,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              )
            else if (petugas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(35),
                child: Center(
                  child: Text('Belum ada data petugas.'),
                ),
              )
            else
              ...petugas.map(_buildOfficerCard),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
