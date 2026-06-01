// send-push: dispara una notificación FCM a un usuario.
// verify_jwt=false porque la llamamos desde otras edge functions; Supabase
// no acepta el service_role como Bearer entre edge fns. La seguridad real
// está en FIREBASE_SERVICE_ACCOUNT_JSON (env secret) — sin esa key nadie
// puede firmar el JWT que valida FCM.
//
// v0.1.13: payload HIBRIDO (notification + data). El campo `notification`
// es lo que garantiza que el SO Android muestra heads-up incluso si la
// app fue matada por el battery saver (caso ZTE/Samsung/MIUI con celu
// bloqueado). El campo `data` lleva `type=offer` + `order_id` para el
// tap handler. Antes intentamos data-only para mostrar fullScreenIntent
// custom desde el cliente, pero el bg isolate no arrancaba con la app
// matada → no llegaba nada.
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create, getNumericDate } from 'https://deno.land/x/djwt@v3.0.2/mod.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = getNumericDate(0);
  const exp = getNumericDate(60 * 60);
  const pem = sa.private_key.replace(/\\n/g, '\n');
  const pemBody = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pemBody), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign']
  );
  const jwt = await create(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp,
    },
    key,
  );
  const tokRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const tok = await tokRes.json();
  if (!tok.access_token) throw new Error(`fcm auth failed: ${JSON.stringify(tok)}`);
  return tok.access_token as string;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!saJson) return json({ error: 'FIREBASE_SERVICE_ACCOUNT_JSON missing' }, 500);
    const sa: ServiceAccount = JSON.parse(saJson);

    const sb = createClient(url, service);
    const { user_id, title, body, data } = await req.json();
    if (!user_id || !title) return json({ error: 'user_id, title required' }, 400);

    const { data: tokens, error } = await sb.from('fcm_tokens')
      .select('token, platform').eq('user_id', user_id);
    if (error) throw error;
    if (!tokens || tokens.length === 0) {
      return json({ sent: 0, reason: 'no_tokens' });
    }

    const accessToken = await getAccessToken(sa);
    const endpoint = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let sent = 0;
    const errors: unknown[] = [];
    for (const row of tokens) {
      // HIBRIDO: notification (display garantizado por el SO incluso con
      // app matada o celu bloqueado) + data (type + order_id para tap).
      // El canal `la10_offers_call` esta creado en el cliente con MAX
      // importance + vibrationPattern de llamada + LED rojo. El SO usa
      // esos flags al renderizar la heads-up.
      const payload = {
        message: {
          token: row.token,
          notification: { title, body: body ?? '' },
          data: Object.fromEntries(
            Object.entries({ title, body: body ?? '', ...(data ?? {}) })
              .map(([k, v]) => [k, String(v)]),
          ),
          android: {
            // HIGH despierta el celu aunque esté bloqueado / en Doze.
            priority: 'HIGH',
            // Sobreescribe ofertas viejas: solo una heads-up por rider.
            collapse_key: 'offer',
            notification: {
              channel_id: 'la10_offers_call',
              sound: 'default',
              visibility: 'PUBLIC',
              notification_priority: 'PRIORITY_MAX',
              // tag controla que una oferta nueva pise la anterior. El
              // collapse_key arriba es de transporte; tag es del display.
              tag: 'offer',
              // No mandamos default_vibrate_timings porque el canal ya
              // define un pattern custom de "llamada" (1s vibra/0.5s pausa
              // x3). Si lo dejaramos true, el SO usaria el default y
              // pisaria nuestro pattern.
              default_vibrate_timings: false,
              default_light_settings: false,
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
                'content-available': 1,
                'interruption-level': 'time-sensitive',
              },
            },
            headers: {
              'apns-priority': '10',
              'apns-push-type': 'alert',
            },
          },
        },
      };
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });
      if (res.ok) {
        sent += 1;
      } else {
        const text = await res.text();
        errors.push({ token: row.token.slice(0, 12) + '…', status: res.status, body: text });
        if (res.status === 404 || res.status === 400) {
          await sb.from('fcm_tokens').delete().eq('user_id', user_id).eq('token', row.token);
        }
      }
    }
    return json({ sent, errors: errors.length ? errors : undefined });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
