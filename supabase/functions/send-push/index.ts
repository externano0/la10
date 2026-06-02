// send-push: dispara una notificación FCM a un usuario.
// verify_jwt=false porque la llamamos desde otras edge functions; Supabase
// no acepta el service_role como Bearer entre edge fns. La seguridad real
// está en FIREBASE_SERVICE_ACCOUNT_JSON (env secret) — sin esa key nadie
// puede firmar el JWT que valida FCM.
//
// v0.1.15: payload DATA-ONLY (sin `notification`). Esto evita que el SO
// muestre su heads-up estilo "mensaje" — el cliente (flutter_callkit_incoming)
// es el unico que muestra UI. Asi siempre aparece el popup tipo llamada
// full-screen, nunca la notif tipo SMS.
// Tradeoff: con app matada en OEMs muy agresivos (MIUI extreme power
// saver) el bg handler podria no arrancar → no se muestra nada. Lo
// mitigamos con priority=HIGH + el foreground service del plugin
// callkit que mantiene viva la conexion.
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
    if (!user_id) return json({ error: 'user_id required' }, 400);

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
      // DATA-ONLY: NO mandamos campo `notification`. El SO no muestra
      // heads-up — el cliente (flutter_callkit_incoming) es el unico
      // responsable de la UI. Asi nunca aparece la notif estilo SMS.
      // Incluimos title/body adentro de `data` por si el cliente los
      // necesita renderear adentro del popup.
      const payload = {
        message: {
          token: row.token,
          data: Object.fromEntries(
            Object.entries({
              title: title ?? '',
              body: body ?? '',
              ...(data ?? {}),
            }).map(([k, v]) => [k, String(v)]),
          ),
          android: {
            // HIGH despierta el celu aunque esté bloqueado / en Doze y es
            // requerido para que el bg handler de FCM se dispare en
            // data-only mode.
            priority: 'HIGH',
            collapse_key: 'offer',
            // NO ponemos `android.notification` porque eso forzaria al
            // SO a renderizar heads-up — lo cual es justo lo que queremos
            // evitar (queremos solo el popup tipo llamada del cliente).
          },
          apns: {
            payload: {
              aps: {
                // content-available=1 + sin alert = silent push en iOS.
                // Permite que el cliente reciba el data y muestre callkit.
                'content-available': 1,
              },
            },
            headers: {
              'apns-priority': '5',
              'apns-push-type': 'background',
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
