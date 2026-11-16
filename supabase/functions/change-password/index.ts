
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const jsonResponse = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Metode tidak diizinkan." }, 405);
    }

    const authHeader = req.headers.get("Authorization");

    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ error: "Sesi login tidak ditemukan." }, 401);
    }

    const accessToken = authHeader.substring(7);
    const body = await req.json();

    const oldPassword = body.old_password;
    const newPassword = body.new_password;

    if (
      typeof oldPassword !== "string" ||
      typeof newPassword !== "string" ||
      !oldPassword ||
      !newPassword
    ) {
      return jsonResponse({ error: "Password wajib diisi." }, 400);
    }

    if (newPassword.length < 8) {
      return jsonResponse(
        { error: "Password baru minimal 8 karakter." },
        400,
      );
    }

    if (oldPassword === newPassword) {
      return jsonResponse(
        { error: "Password baru harus berbeda dari password lama." },
        400,
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const publishableKey =
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
      Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!supabaseUrl || !publishableKey || !serviceRoleKey) {
      throw new Error("Konfigurasi server belum lengkap.");
    }

    const adminClient = createClient(
      supabaseUrl,
      serviceRoleKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );

    const publicClient = createClient(
      supabaseUrl,
      publishableKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );

    // Verifikasi identitas pengguna berdasarkan access token.
    const {
      data: { user },
      error: userError,
    } = await publicClient.auth.getUser(accessToken);

    if (userError || !user) {
      return jsonResponse({ error: "Sesi login tidak valid." }, 401);
    }

    // Ambil profil pengguna.
    const { data: profile, error: profileError } =
      await adminClient
        .from("profiles")
        .select("id, username, is_active")
        .eq("id", user.id)
        .maybeSingle();

    if (profileError || !profile) {
      return jsonResponse({ error: "Profil pengguna tidak ditemukan." }, 404);
    }

    if (!profile.is_active) {
      return jsonResponse({ error: "Akun tidak aktif." }, 403);
    }

    if (!user.email) {
      return jsonResponse({ error: "Identitas akun tidak valid." }, 400);
    }

    // Verifikasi password lama.
    const { error: passwordError } =
      await publicClient.auth.signInWithPassword({
        email: user.email,
        password: oldPassword,
      });

    if (passwordError) {
      return jsonResponse({ error: "Password lama tidak benar." }, 400);
    }

    // Ubah password akun di Supabase Auth.
    const { error: updatePasswordError } =
      await adminClient.auth.admin.updateUserById(user.id, {
        password: newPassword,
      });

    if (updatePasswordError) {
      return jsonResponse(
        { error: "Gagal memperbarui password." },
        500,
      );
    }

    // Tandai bahwa pengguna sudah mengganti password awal.
    const { error: updateProfileError } =
      await adminClient
        .from("profiles")
        .update({ must_change_password: false })
        .eq("id", user.id);

    if (updateProfileError) {
      return jsonResponse(
        {
          error:
            "Password sudah berubah, tetapi status profil belum diperbarui. Silakan coba lagi.",
        },
        500,
      );
    }

    return jsonResponse({
      success: true,
      message: "Password berhasil diperbarui.",
    });
  } catch (error) {
    console.error("change-password error:", error);
    return jsonResponse({ error: "Terjadi kesalahan pada server." }, 500);
  }
});
