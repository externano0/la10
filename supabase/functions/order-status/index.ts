import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Allowed transitions enforced server-side. Source of truth.
const ALLOWED: Record<string, string[]> = {
  draft:              ['pending_assignment','cancelled'],
  pending_assignment: ['offered','cancelled'],
  offered:            ['assigned','pending_assignment','cancelled'],
  assigned:           ['picked_up','cancelled'],
  picked_up:          ['delivered','cancelled'],
  delivered:          [],
  cancelled:          [],
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

    const { order_id, to, reason } = await req.json();
    if (!order_id || !to) return json({ error: { code: 'BAD_REQUEST', message: 'order_id and to required' } }, 400);

    const { data: order, error: oErr } = await sbSvc.from('orders')
      .select('id,status,business_id,assigned_rider_id').eq('id', order_id).single();
    if (oErr || !order) return json({ error: { code: 'NOT_FOUND', message: 'order not found' } }, 404);

    if (!ALLOWED[order.status]?.includes(to)) {
      return json({ error: { code: 'INVALID_TRANSITION', message: `${order.status} -> ${to} not allowed` } }, 409);
    }

    const update: Record<string, unknown> = { status: to };
    if (to === 'picked_up')  update.picked_up_at  = new Date().toISOString();
    if (to === 'delivered')  update.delivered_at  = new Date().toISOString();
    if (to === 'cancelled') { update.cancelled_at = new Date().toISOString(); update.cancel_reason = reason ?? null; }

    const { error: upErr } = await sbSvc.from('orders').update(update).eq('id', order_id);
    if (upErr) throw upErr;

    // If order leaves the rider's plate (delivered/cancelled), free them.
    if (['delivered','cancelled'].includes(to) && order.assigned_rider_id) {
      await sbSvc.from('riders').update({ status: 'available' }).eq('user_id', order.assigned_rider_id);
    }

    // Newly submitted → dispatch.
    if (to === 'pending_assignment') {
      await sbSvc.functions.invoke('dispatch-order', { body: { order_id } });
    }

    return json({ order_status: to });
  } catch (e) {
    return json({ error: { code: 'INTERNAL', message: String(e?.message ?? e) } }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
