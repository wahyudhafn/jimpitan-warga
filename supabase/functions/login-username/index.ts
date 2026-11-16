
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(
  body: Record<string, unknown>,
  status = 200,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return response({ error: "Metode tidak diizinkan." }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey =
      Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
    const serviceRoleKey = Deno.env.get(
      "SUPABASE_SERVICE_ROLE_KEY",
    );

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      console.error("Konfigurasi Supabase belum lengkap.");
      return response(
        { error: "Layanan autentikasi belum dikonfigurasi." },
        500,
      );
    }

    const body = await req.json();

    const username =
      typeof body.username === "string"
        ? body.username.trim().toLowerCase()
        : "";

    const password =
      typeof body.password === "string"
        ? body.password
        : "";

    if (
      !/^[a-z0-9][a-z0-9._-]{2,29}$/.test(username) ||
      password.length === 0 ||
      password.length > 128
    ) {
      return response(
        { error: "Username atau password salah." },
        401,
      );
    }

    // Client khusus server untuk membaca profil dan data Auth.
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

    // Cari profil berdasarkan username.
    // Maksimal dua hasil untuk mendeteksi username duplikat
    // yang berbeda huruf besar/kecil.
    const { data: profiles, error: profileError } =
      await adminClient
        .from("profiles")
        .select("id, role, is_active, must_change_password")
        .eq("username", username)
        .limit(2);

    if (
      profileError ||
      !profiles ||
      profiles.length !== 1
    ) {
      return response(
        { error: "Username atau password salah." },
        401,
      );
    }

    const profile = profiles[0];

    if (profile.is_active !== true) {
      return response(
        { error: "Akun tidak aktif. Hubungi admin." },
        403,
      );
    }

    // Ambil email internal berdasarkan ID akun Auth.
    const { data: authResult, error: authLookupError } =
      await adminClient.auth.admin.getUserById(profile.id);

    const authUser = authResult?.user;

    if (
      authLookupError ||
      !authUser ||
      !authUser.email
    ) {
      console.error("Identitas Auth akun tidak ditemukan.");
      return response(
        { error: "Akun belum dikonfigurasi dengan benar." },
        500,
      );
    }

    // Client publik untuk memverifikasi password.
    // Password tidak disimpan atau diverifikasi secara manual.
    const authClient = createClient(
      supabaseUrl,
      anonKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      },
    );

    const { data: loginData, error: loginError } =
      await authClient.auth.signInWithPassword({
        email: authUser.email,
        password,
      });

    if (
      loginError ||
      !loginData.session ||
      !loginData.user
    ) {
      return response(
        { error: "Username atau password salah." },
        401,
      );
    }

    return response({
      success: true,
      access_token: loginData.session.access_token,
      refresh_token: loginData.session.refresh_token,
      token_type: loginData.session.token_type,
      expires_in: loginData.session.expires_in,
      role: profile.role,
      must_change_password:
        profile.must_change_password,
    });
  } catch (error) {
    console.error(
      "Kesalahan login:",
      error instanceof Error ? error.message : "Unknown error",
    );

    return response(
      { error: "Terjadi kesalahan pada layanan login." },
      500,
    );
  }
});
