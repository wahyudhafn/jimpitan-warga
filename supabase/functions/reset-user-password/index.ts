
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const json = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });

  try {
    if (req.method !== "POST") {
      return json({ success: false, message: "Method tidak diizinkan." }, 405);
    }

    const authorization = req.headers.get("Authorization");

    if (!authorization?.startsWith("Bearer ")) {
      return json({ success: false, message: "Token tidak ditemukan." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authClient = createClient(supabaseUrl, anonKey, {
      global: {
        headers: { Authorization: authorization },
      },
    });

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Verifikasi admin yang sedang login
    const {
      data: { user: caller },
      error: authError,
    } = await authClient.auth.getUser();

    if (authError || !caller) {
      return json({ success: false, message: "Sesi login tidak valid." }, 401);
    }

    const { data: adminProfile, error: adminError } = await adminClient
      .from("profiles")
      .select("role, is_active")
      .eq("id", caller.id)
      .single();

    if (
      adminError ||
      adminProfile?.role !== "admin" ||
      adminProfile?.is_active !== true
    ) {
      return json({
        success: false,
        message: "Hanya admin aktif yang dapat mereset password.",
      }, 403);
    }

    const body = await req.json();
    const userId = body.user_id;
    const newPassword = body.new_password;

    if (
      typeof userId !== "string" ||
      typeof newPassword !== "string"
    ) {
      return json({
        success: false,
        message: "Data akun dan password wajib diisi.",
      }, 400);
    }

    if (newPassword.length < 8 || newPassword.length > 72) {
      return json({
        success: false,
        message: "Password harus 8 sampai 72 karakter.",
      }, 400);
    }

    // Pastikan target adalah akun warga atau petugas
    const { data: targetProfile, error: targetError } = await adminClient
      .from("profiles")
      .select("id, role, username")
      .eq("id", userId)
      .single();

    if (
      targetError ||
      !targetProfile ||
      !["resident", "officer"].includes(targetProfile.role)
    ) {
      return json({
        success: false,
        message: "Akun warga atau petugas tidak ditemukan.",
      }, 404);
    }

    // Ganti password Auth
    const { error: passwordError } =
      await adminClient.auth.admin.updateUserById(userId, {
        password: newPassword,
      });

    if (passwordError) {
      return json({
        success: false,
        message: "Gagal mengganti password akun.",
      }, 400);
    }

    // Wajibkan pengguna mengganti password saat login berikutnya
    const { error: profileError } = await adminClient
      .from("profiles")
      .update({
        must_change_password: true,
        updated_at: new Date().toISOString(),
      })
      .eq("id", userId);

    if (profileError) {
      return json({
        success: false,
        message:
          "Password sudah diganti, tetapi status wajib ganti password gagal diperbarui.",
      }, 500);
    }

    return json({
      success: true,
      message: "Password berhasil direset.",
      username: targetProfile.username,
    });
  } catch (error) {
    console.error("Reset password error:", error);

    return json({
      success: false,
      message: "Terjadi kesalahan pada server.",
    }, 500);
  }
});
