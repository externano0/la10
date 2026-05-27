// Invoked by pg_cron every 10s (see supabase/migrations/013_cron.sql when added)
// or callable manually for testing.
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async () => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const sb = createClient(url, service);

  const nowIso = new Date().toISOString();
  const { data: expired, error } = await sb.from('dispatch_offers')
    .update({ response: 'expired', responded_at: nowIso })
    .eq('response', 'pending')
    .lt('expires_at', nowIso)
    .select('order_id');
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  const orderIds = Array.from(new Set((expired ?? []).map((r: any) => r.order_id)));
  for (const order_id of orderIds) {
    await sb.from('orders').update({ status: 'pending_assignment' }).eq('id', order_id).eq('status', 'offered');
    await sb.functions.invoke('dispatch-order', { body: { order_id } });
  }
  return new Response(JSON.stringify({ expired_count: expired?.length ?? 0, re_dispatched: orderIds.length }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
