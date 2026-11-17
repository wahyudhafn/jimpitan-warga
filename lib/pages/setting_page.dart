
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final supabase = Supabase.instance.client;

  final formKey = GlobalKey<FormState>();

  final appNameController =
      TextEditingController(text: 'jimpitan');
  final neighborhoodController = TextEditingController();
  final addressController = TextEditingController();
  final amountController = TextEditingController();

  bool loading = true;
  bool saving = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    appNameController.dispose();
    neighborhoodController.dispose();
    addressController.dispose();
    amountController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      loading = true;
      loadError = null;
    });

    try {
      final response = await supabase
          .from('jimpitan_settings')
          .select();

      final settings =
          List<Map<String, dynamic>>.from(response);

      for (final item in settings) {
        final name = item['setting_name']?.toString();
        final value = item['setting_value']?.toString() ?? '';

        switch (name) {
          case 'app_name':
            appNameController.text = value;
            break;
          case 'neighborhood_name':
            neighborhoodController.text = value;
            break;
          case 'address':
            addressController.text = value;
            break;
          case 'default_amount':
            amountController.text = value;
            break;
        }
      }
    } catch (e) {
      loadError = e.toString();
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      final settings = {
        'app_name': appNameController.text.trim(),
        'neighborhood_name':
            neighborhoodController.text.trim(),
        'address': addressController.text.trim(),
        'default_amount': amountController.text.trim(),
      };

      for (final entry in settings.entries) {
        await supabase
            .from('jimpitan_settings')
            .upsert(
              {
                'setting_name': entry.key,
                'setting_value': entry.value,
              },
              onConflict: 'setting_name',
            );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengaturan berhasil disimpan.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan pengaturan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final dialogFormKey = GlobalKey<FormState>();

    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool changing = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (contextDialog, setDialogState) {
            Future<void> changePassword() async {
              if (!dialogFormKey.currentState!.validate()) {
                return;
              }

              setDialogState(() => changing = true);

              try {
                final result =
                    await supabase.functions.invoke(
                  'change-password',
                  body: {
                    'old_password':
                        oldPasswordController.text,
                    'new_password':
                        newPasswordController.text,
                  },
                );

                if (result.status < 200 ||
                    result.status >= 300) {
                  final data = result.data;
                  final message = data is Map
                      ? data['message']?.toString() ??
                          data['error']?.toString()
                      : null;

                  throw Exception(
                    message ?? 'Gagal mengganti password.',
                  );
                }

                if (result.data is Map &&
                    result.data['success'] != true) {
                  throw Exception(
                    result.data['message']?.toString() ??
                        'Gagal mengganti password.',
                  );
                }

                if (!mounted || !dialogContext.mounted) {
                  return;
                }

                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Password berhasil diganti.',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted || !dialogContext.mounted) {
                  return;
                }

                setDialogState(() => changing = false);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      e.toString().replaceFirst(
                        'Exception: ',
                        '',
                      ),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Ganti Password Admin'),
              content: SizedBox(
                width: 400,
                child: Form(
                  key: dialogFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: oldPasswordController,
                        obscureText: obscureOld,
                        decoration: InputDecoration(
                          labelText: 'Password lama',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                obscureOld = !obscureOld;
                              });
                            },
                            icon: Icon(
                              obscureOld
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password lama wajib diisi.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: newPasswordController,
                        obscureText: obscureNew,
                        decoration: InputDecoration(
                          labelText: 'Password baru',
                          helperText: 'Minimal 8 karakter',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                obscureNew = !obscureNew;
                              });
                            },
                            icon: Icon(
                              obscureNew
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
                        controller: confirmPasswordController,
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
                          if (value != newPasswordController.text) {
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
                  onPressed: changing
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: changing ? null : changePassword,
                  child: changing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Simpan Password'),
                ),
              ],
            );
          },
        );
      },
    );

    oldPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text(
          'Pengaturan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: loading || saving ? null : _loadSettings,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _loadSettings,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  if (loadError != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Text(
                              'Pengaturan belum dapat dimuat.',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              loadError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                            TextButton(
                              onPressed: _loadSettings,
                              child: const Text('Coba lagi'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Identitas Aplikasi',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildField(
                              label: 'Nama aplikasi',
                              controller: appNameController,
                              validator: (value) {
                                if (value == null ||
                                    value.trim().isEmpty) {
                                  return 'Nama aplikasi wajib diisi.';
                                }
                                return null;
                              },
                            ),
                            _buildField(
                              label: 'Nama RT / RW',
                              controller: neighborhoodController,
                              hint: 'Contoh: RT 01 / RW 05',
                            ),
                            _buildField(
                              label: 'Alamat lingkungan',
                              controller: addressController,
                              maxLines: 2,
                            ),
                            _buildField(
                              label: 'Nominal jimpitan default',
                              controller: amountController,
                              keyboardType: TextInputType.number,
                              hint: 'Contoh: 1000',
                              validator: (value) {
                                final amount = num.tryParse(
                                  (value ?? '').trim(),
                                );

                                if (amount == null || amount < 0) {
                                  return 'Masukkan nominal yang valid.';
                                }
                                return null;
                              },
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed:
                                    saving ? null : _saveSettings,
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF256B50),
                                ),
                                child: saving
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Simpan Pengaturan',
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Keamanan Akun',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ganti password akun administrator secara berkala.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _showChangePasswordDialog,
                              icon: const Icon(
                                Icons.lock_outline,
                              ),
                              label: const Text(
                                'Ganti Password Admin',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
