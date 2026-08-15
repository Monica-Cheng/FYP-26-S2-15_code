// NEVER import this in client components.
import { createClient } from "@supabase/supabase-js";

function getAdminEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  // Supabase renamed service_role to the "secret" key (sb_secret_…).
  // Neither name may ever carry a NEXT_PUBLIC_ prefix — this bypasses RLS.
  const serviceRoleKey =
    process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_SECRET_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      "Missing NEXT_PUBLIC_SUPABASE_URL, or SUPABASE_SERVICE_ROLE_KEY / SUPABASE_SECRET_KEY.",
    );
  }

  return { url, serviceRoleKey };
}

export function createSupabaseAdminClient() {
  const { url, serviceRoleKey } = getAdminEnv();

  return createClient(url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
