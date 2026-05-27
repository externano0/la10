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
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const auth = req.headers.get('Authorization') ?? '';
    const sbUser = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const sbSvc  = createClient(url, service);

    const { data: { user } } = await sbUser.auth.getUser(auth.replace('Bearer ', ''));
    if (!user) return json({ error: { code: 'UNAUTHORIZED', message: 'auth required' } }, 401);

    const { offer_id, response } = await req.json();
    if (!offer_id || !['accepted','declined'].includes(response)) {
      return json({ error: { code: 'BAD_REQUEST', message: 'offer_id and response required' } }, 400);
    }

    const { data: offer, error: oErr } = await sbSvc.from('dispatch_offers')
      .select('id,order_id,rider_id,response,expires_at').eq('id', offer_id).single();
    if (oErr || !offer) return json({ error: { code: 'NOT_FOUND', message: 'offer not found' } }, 404);
    if (offer.rider_id !== user.id) return json({ error: { code: 'FORBIDDEN', message: 'not your offer' } }, 403);
    if (offer.response !== 'pending') return json({ error: { code: 'CONFLICT', message: 'offer already resolved' } }, 409);
    if (new Date(offer.expires_at).getTime() < Date.now()) {
      await sbSvc.from('dispatch_offers').update({ response: 'expired', responded_at: new Date().toISOString() }).eq('id', offer_id);
      return json({ error: { code: 'EXPIRED', message: 'offer expired' } }, 410);
    }

    await sbSvc.from('dispatch_offers').update({ response, responded_at: new Date().toISOString() }).eq('id', offer_id);

    if (response === 'accepted') {
      await sbSvc.from('orders').update({
        status: 'assigned', assigned_rider_id: user.id, assigned_at: new Date().toISOString(),
      }).eq('id', offer.order_id);
      await sbSvc.from('riders').update({ status: 'on_delivery' }).eq('user_id', user.id);
      return json({ order_status: 'assigned' });
    }

    // declined: kick re-dispatch
    await sbSvc.from('orders').update({ status: 'pending_assignment' }).eq('id', offer.order_id);
    await sbSvc.functions.invoke('dispatch-order', { body: { order_id: offer.order_id } });
    return json({ order_status: 'pending_assignment' });
  } catch (e) {
    return json({ error: { code: 'INTERNAL', message: String(e?.message ?? e) } }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
