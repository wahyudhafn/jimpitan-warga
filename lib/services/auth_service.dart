
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final supabase = Supabase.instance.client;

  Future<String> login({
    required String email,
    required String password,
  }) async {
    final response =
        await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    final user = response.user;

    if (user == null) {
      throw Exception('Login gagal.');
    }

    final profile = await supabase
        .from('profiles')
        .select('role, full_name')
        .eq('id', user.id)
        .single();

    final role = profile['role'] as String;

    if (!['admin', 'officer', 'resident'].contains(role)) {
      await supabase.auth.signOut();
      throw Exception('Role akun tidak valid.');
    }

    return role;
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await supabase.auth.resetPasswordForEmail(
      email.trim(),
    );
  }
}
