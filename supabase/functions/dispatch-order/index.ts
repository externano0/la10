import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const OFFER_TTL_SEC = Number(Deno.env.get('DISPATCH_OFFER_TTL_SEC') ?? 30);
const RADIUS_M     = Number(Deno.env.get('DISPATCH_SEARCH_RADIUS_M') ?? 5000);

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const sb = createClient(url, service);

    const { order_id, rider_id: overrideRider } = await req.json();
    if (!order_id) return json({ error: { code: 'BAD_REQUEST', message: 'order_id required' } }, 400);

    const { data: order, error: oErr } = await sb.from('orders').select('id,status,pickup_location').eq('id', order_id).single();
    if (oErr || !order) return json({ error: { code: 'NOT_FOUND', message: 'order not found' } }, 404);
    if (!['pending_assignment','offered'].includes(order.status)) {
      return json({ error: { code: 'CONFLICT', message: `order in status ${order.status}` } }, 409);
    }

    // If reassigning manually, cancel any pending offer for this order first.
    if (overrideRider) {
      await sb.from('dispatch_offers')
        .update({ response: 'expired', responded_at: new Date().toISOString() })
        .eq('order_id', order_id).eq('response', 'pending');
    }

    let chosenRiderId: string;
    let score: number;
    if (overrideRider) {
      // Manual override path — trust the dispatcher's choice.
      chosenRiderId = overrideRider;
      score = 0;
    } else {
      const { data: candidates, error: cErr } = await sb.rpc('la10_find_best_rider', { p_order_id: order_id, p_radius_m: RADIUS_M });
      if (cErr) throw cErr;
      const rider = candidates?.[0];
      if (!rider) return json({ error: { code: 'NO_RIDER', message: 'no eligible rider' } }, 503);
      chosenRiderId = rider.rider_id;
      score = rider.score;
    }

    const expires_at = new Date(Date.now() + OFFER_TTL_SEC * 1000).toISOString();
    const { data: offer, error: insErr } = await sb.from('dispatch_offers').insert({
      order_id, rider_id: chosenRiderId, score, expires_at,
    }).select('id').single();
    if (insErr) throw insErr;

    await sb.from('orders').update({ status: 'offered' }).eq('id', order_id);

    return json({ offered_rider_id: chosenRiderId, offer_id: offer!.id, expires_at, manual: !!overrideRider });
  } catch (e) {
    return json({ error: { code: 'INTERNAL', message: String((e as Error)?.message ?? e) } }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
