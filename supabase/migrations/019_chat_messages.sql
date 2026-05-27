-- Mensajes entre el jefe (dispatchers + admin) y un rider.
-- Modelo: un hilo por rider. Cualquier dispatcher escribe en ese hilo.
-- El rider solo ve y escribe en su propio hilo.

CREATE TABLE public.chat_messages (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id        uuid NOT NULL REFERENCES public.riders(user_id) ON DELETE CASCADE,
  sender_user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  body            text NOT NULL CHECK (length(body) BETWEEN 1 AND 2000),
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_chat_messages_rider_created
  ON public.chat_messages (rider_id, created_at DESC);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- El rider lee su propio hilo; el dispatcher / admin lee todos.
CREATE POLICY chat_select ON public.chat_messages
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_dispatcher()
    OR public.is_admin()
  );

-- El rider escribe en su propio hilo; el dispatcher / admin escribe en cualquiera.
-- En ambos casos, el sender debe ser el usuario actual (anti-spoofing).
CREATE POLICY chat_insert ON public.chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_user_id = auth.uid()
    AND (
      rider_id = auth.uid()
      OR public.is_dispatcher()
      OR public.is_admin()
    )
  );

-- Realtime: mensajes nuevos llegan en vivo.
ALTER TABLE public.chat_messages REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
