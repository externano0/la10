import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const auth = req.headers.get('Authorization') ?? '';
    const sb = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data: { user }, error: authErr } = await sb.auth.getUser(auth.replace('Bearer ', ''));
    if (authErr || !user) return json({ error: { code: 'UNAUTHORIZED', message: 'auth required' } }, 401);

    const { lat, lng, heading, speed, accuracy_m, order_id } = await req.json();
    if (typeof lat !== 'number' || typeof lng !== 'number') {
      return json({ error: { code: 'BAD_REQUEST', message: 'lat/lng required' } }, 400);
    }

    const point = `SRID=4326;POINT(${lng} ${lat})`;
    const { error: upErr } = await sb.from('rider_locations').upsert({
      rider_id: user.id, location: point, heading, speed_ms: speed, accuracy_m, recorded_at: new Date().toISOString(),
    });
    if (upErr) throw upErr;

    await sb.from('rider_location_history').insert({
      rider_id: user.id, order_id: order_id ?? null, location: point, heading, speed_ms: speed, accuracy_m,
    });

    return json({ ok: true });
  } catch (e) {
    return json({ error: { code: 'INTERNAL', message: String(e?.message ?? e) } }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
