import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

const clampInt = (value: unknown, min: number, max: number) => {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return null;
  return Math.max(min, Math.min(max, parsed));
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const presenterToken = Deno.env.get("PRESENTER_TOKEN");
  if (!supabaseUrl || !serviceRoleKey || !presenterToken) {
    return json({ error: "Server configuration is incomplete" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const action = String(body.action ?? "");
  const roomId = String(body.room_id ?? "gamification-live").trim();
  if (!/^[a-z0-9][a-z0-9-]{2,63}$/i.test(roomId)) {
    return json({ error: "Invalid room id" }, 400);
  }

  if (action === "get-state") {
    const { data: room, error } = await admin
      .from("presentation_rooms")
      .select("*")
      .eq("id", roomId)
      .maybeSingle();
    if (error) return json({ error: error.message }, 500);
    if (!room) return json({ error: "Room not found" }, 404);

    let nextAllowedAt: string | null = null;
    const participantId = String(body.participant_id ?? "");
    if (/^[0-9a-f-]{36}$/i.test(participantId)) {
      const { data: participant } = await admin
        .from("presentation_participants")
        .select("last_click_at")
        .eq("room_id", roomId)
        .eq("participant_id", participantId)
        .maybeSingle();
      if (participant?.last_click_at) {
        nextAllowedAt = new Date(new Date(participant.last_click_at).getTime() + 60_000).toISOString();
      }
    }

    return json({ room, next_allowed_at: nextAllowedAt });
  }

  if (action === "claim-example") {
    const participantId = String(body.participant_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(participantId)) {
      return json({ error: "Invalid participant id" }, 400);
    }
    const { data, error } = await admin.rpc("claim_presentation_example", {
      p_room_id: roomId,
      p_participant_id: participantId,
      p_cooldown_seconds: 60,
      p_max_examples: 42,
    });
    if (error) return json({ error: error.message }, 500);
    return json(data?.[0] ?? { accepted: false });
  }

  const suppliedToken = String(body.presenter_token ?? "");
  if (!suppliedToken || suppliedToken !== presenterToken) {
    return json({ error: "Presenter authorization failed" }, 403);
  }

  if (action === "verify-presenter") {
    return json({ ok: true });
  }

  if (action === "set-state") {
    const requested = (body.state ?? {}) as Record<string, unknown>;
    const state: Record<string, number | string> = { updated_at: new Date().toISOString() };
    const fields: Array<[string, number, number]> = [
      ["current_slide", 0, 12],
      ["horizontal_index", 0, 3],
      ["reward_reveal", 0, 3],
      ["achievement_gallery_index", 0, 3],
      ["quest_gallery_index", 0, 2],
    ];
    for (const [field, min, max] of fields) {
      if (requested[field] !== undefined) {
        const value = clampInt(requested[field], min, max);
        if (value === null) return json({ error: `Invalid ${field}` }, 400);
        state[field] = value;
      }
    }
    if (Object.keys(state).length === 1) return json({ error: "No state fields supplied" }, 400);

    const { data, error } = await admin
      .from("presentation_rooms")
      .update(state)
      .eq("id", roomId)
      .select("*")
      .single();
    if (error) return json({ error: error.message }, 500);
    return json({ room: data });
  }

  if (action === "reset-session") {
    const { error: participantError } = await admin
      .from("presentation_participants")
      .delete()
      .eq("room_id", roomId);
    if (participantError) return json({ error: participantError.message }, 500);

    const { data, error } = await admin
      .from("presentation_rooms")
      .update({
        current_slide: 0,
        horizontal_index: 0,
        reward_reveal: 0,
        achievement_gallery_index: 0,
        quest_gallery_index: 0,
        example_count: 0,
        reset_version: Date.now(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", roomId)
      .select("*")
      .single();
    if (error) return json({ error: error.message }, 500);
    return json({ room: data });
  }

  return json({ error: "Unknown action" }, 400);
});
