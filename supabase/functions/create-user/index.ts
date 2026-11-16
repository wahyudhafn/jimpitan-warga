
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const USER_EMAIL_DOMAIN = "akun.jimpitan-warga.invalid";

function response(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return response({ error: "Metode tidak diizinkan." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authorization = req.headers.get("Authorization");

  if (!authorization?.startsWith("Bearer ")) {
    return response({ error: "Token autentikasi tidak ditemukan." }, 401);
  }

  const accessToken = authorization.substring(7);

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  try {
    // 1. Verifikasi identitas admin
    const {
      data: { user: caller },
      error: callerError,
    } = await adminClient.auth.getUser(accessToken);

    if (callerError || !caller) {
      return response({ error: "Sesi login tidak valid." }, 401);
    }

    // 2. Pastikan pemanggil adalah admin aktif
    const { data: adminProfile, error: profileError } =
      await adminClient
        .from("profiles")
        .select("role, is_active")
        .eq("id", caller.id)
        .maybeSingle();

    if (
      profileError ||
      !adminProfile ||
      adminProfile.role !== "admin" ||
      !adminProfile.is_active
    ) {
      return response(
        { error: "Hanya administrator aktif yang boleh membuat akun." },
        403,
      );
    }

    // 3. Baca dan validasi data
    const body = await req.json();

    const fullName = String(body.full_name ?? "").trim();
    const username = String(body.username ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const role = String(body.role ?? "");
    const phone = String(body.phone ?? "").trim();
    const address = String(body.address ?? "").trim();
    const notes = String(body.notes ?? "").trim();
    const assignedArea = String(body.assigned_area ?? "").trim();

    if (!fullName || fullName.length > 120) {
      return response({ error: "Nama lengkap wajib diisi (maksimal 120 karakter)." }, 400);
    }

    if (!/^[a-z0-9][a-z0-9._-]{2,29}$/.test(username)) {
      return response(
        { error: "Username harus 3–30 karakter: huruf kecil, angka, titik, _ atau -." },
        400,
      );
    }

    if (password.length < 8 || password.length > 72) {
      return response(
        { error: "Password awal harus 8–72 karakter." },
        400,
      );
    }

    if (role !== "resident" && role !== "officer") {
      return response({ error: "Role harus resident atau officer." }, 400);
    }

    if (phone.length > 30) {
      return response({ error: "Nomor telepon terlalu panjang." }, 400);
    }

    if (role === "resident" && (!address || address.length > 300)) {
      return response(
        { error: "Alamat warga wajib diisi (maksimal 300 karakter)." },
        400,
      );
    }

    if (address.length > 300 || notes.length > 1000 || assignedArea.length > 200) {
      return response({ error: "Ada data yang melebihi batas panjang." }, 400);
    }

    // 4. Pastikan username belum digunakan
    const { data: existingProfile, error: usernameError } =
      await adminClient
        .from("profiles")
        .select("id")
        .eq("username", username)
        .maybeSingle();

    if (usernameError) {
      console.error("Pemeriksaan username:", usernameError);
      return response({ error: "Gagal memeriksa username." }, 500);
    }

    if (existingProfile) {
      return response({ error: "Username sudah digunakan." }, 409);
    }

    // 5. Buat akun Auth.
    // Trigger handle_new_user() akan membuat profil otomatis.
    const internalEmail = `${username}@${USER_EMAIL_DOMAIN}`;

    const { data: authData, error: authError } =
      await adminClient.auth.admin.createUser({
        email: internalEmail,
        password,
        email_confirm: true,
        user_metadata: {
          full_name: fullName,
        },
      });

    if (authError || !authData.user) {
      console.error("Pembuatan akun Auth:", authError);
      return response(
        { error: authError?.message ?? "Gagal membuat akun." },
        400,
      );
    }

    const newUserId = authData.user.id;

    try {
      // 6. Lengkapi profil yang dibuat oleh trigger
      const { error: updateProfileError } = await adminClient
        .from("profiles")
        .update({
          full_name: fullName,
          username,
          phone: phone || null,
          role,
          is_active: true,
          must_change_password: true,
        })
        .eq("id", newUserId);

      if (updateProfileError) throw updateProfileError;

      // 7. Simpan data sesuai jenis akun
      if (role === "resident") {
        const { error } = await adminClient
          .from("residents")
          .insert({
            profile_id: newUserId,
            resident_name: fullName,
            address,
            notes: notes || null,
            is_active: true,
          });

        if (error) throw error;
      }

      if (role === "officer") {
        const { error } = await adminClient
          .from("officers")
          .insert({
            profile_id: newUserId,
            assigned_area: assignedArea || null,
            is_active: true,
          });

        if (error) throw error;
      }

      return response({
        success: true,
        message: role === "resident"
          ? "Akun warga berhasil dibuat."
          : "Akun petugas berhasil dibuat.",
        user_id: newUserId,
        username,
        role,
      });
    } catch (saveError) {
      console.error("Penyimpanan data profil:", saveError);

      // Bersihkan akun Auth jika penyimpanan data gagal.
      // Profil ikut terhapus melalui ON DELETE CASCADE.
      const { error: deleteError } =
        await adminClient.auth.admin.deleteUser(newUserId);

      if (deleteError) {
        console.error("Pembersihan akun gagal:", deleteError);
      }

      return response(
        { error: "Gagal menyimpan data. Akun baru dibatalkan." },
        500,
      );
    }
  } catch (error) {
    console.error("Kesalahan create-user:", error);
    return response({ error: "Terjadi kesalahan pada server." }, 500);
  }
});
