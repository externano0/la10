-- Tokens FCM (Firebase Cloud Messaging) por usuario.
-- Cada login en un device nuevo pisa el token anterior del mismo (user,platform).
-- Esto permite que la edge fn dispatch-order le mande push al rider cuando
-- llega una oferta, sin importar si la app está abierta, en background o
-- el celu está bloqueado.

CREATE TABLE public.fcm_tokens (
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token       text NOT NULL,
  platform    text NOT NULL CHECK (platform IN ('android','ios','web')),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, platform)
);

ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;

-- El usuario lee y escribe SOLO su propio token. La edge fn usa service_role.
CREATE POLICY fcm_tokens_self ON public.fcm_tokens
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE TRIGGER fcm_tokens_set_updated_at
  BEFORE UPDATE ON public.fcm_tokens
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);
