// send-push: dispara una notificación FCM a un usuario.
// Inputs: { user_id, title, body, data?: Record<string,string> }
// Requires env var FIREBASE_SERVICE_ACCOUNT_JSON con el JSON de la service
// account de Firebase (Project settings -> Service accounts -> Generate key).
//
// Usamos el endpoint HTTP v1 de FCM (el v1, no el legacy).
// Doc: https://firebase.google.com/docs/cloud-messaging/send-message

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
  // Importamos la private key PEM como CryptoKey RSA.
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

    // Buscamos todos los tokens del usuario (android, ios, web).
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
      const payload = {
        message: {
          token: row.token,
          notification: { title, body: body ?? '' },
          data: Object.fromEntries(
            Object.entries(data ?? {}).map(([k, v]) => [k, String(v)]),
          ),
          android: {
            priority: 'HIGH',
            notification: {
              channel_id: 'la10_offers',
              sound: 'default',
              // Visibilidad en pantalla bloqueada y heads-up.
              visibility: 'PUBLIC',
              default_vibrate_timings: true,
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
                'content-available': 1,
              },
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
        // Si FCM dice que el token es inválido, lo limpiamos.
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
