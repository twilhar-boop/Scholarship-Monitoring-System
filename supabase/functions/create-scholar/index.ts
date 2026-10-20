import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("Sign-in required");
    const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: userData, error: userErr } = await caller.auth.getUser();
    if (userErr || !userData.user) throw new Error("Invalid session");
    const { data: profile } = await caller.from("profiles").select("role").eq("id", userData.user.id).single();
    if (profile?.role !== "staff") throw new Error("Only Scholarship Staff can register scholars");
    const body = await req.json();
    const student_id = String(body.student_id || "").trim();
    const full_name = String(body.full_name || "").trim();
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");
    const program_id = String(body.program_id || "");
    if (!student_id || !full_name || !email || password.length < 8 || !["merit","community"].includes(program_id)) throw new Error("Provide valid fields; password must be at least 8 characters");
    const admin = createClient(url, service);
    const { data: created, error: createErr } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name, student_id } });
    if (createErr) throw createErr;
    const { error: profileErr } = await admin.from("profiles").insert({ id: created.user.id, role: "scholar", student_id, full_name, program_id });
    if (profileErr) { await admin.auth.admin.deleteUser(created.user.id); throw profileErr; }
    return new Response(JSON.stringify({ ok: true, student_id }), { headers: { ...cors, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message || "Request failed" }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
  }
});