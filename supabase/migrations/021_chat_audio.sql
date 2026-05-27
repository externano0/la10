-- Soporte de mensajes de audio en el chat:
--  * audio_url: ruta del archivo en el bucket `chat-audios` (no URL pública).
--  * audio_duration_ms: para mostrar la duración en la burbuja antes de cargar.
-- Si audio_url está seteado, el `body` puede ser '🎤' o vacío.
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS audio_url         text,
  ADD COLUMN IF NOT EXISTS audio_duration_ms int;

-- Relajamos el length del body para permitir audio-only (texto del placeholder).
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_body_check;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_body_check
  CHECK (length(body) BETWEEN 0 AND 2000);

-- Bucket privado para los audios. Subidas y lecturas vía RLS de storage.
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-audios', 'chat-audios', false)
ON CONFLICT (id) DO NOTHING;

-- Convención de path: '<rider_id>/<uuid>.webm'
-- Lectura: el rider lee su carpeta; dispatcher/admin leen cualquiera.
DROP POLICY IF EXISTS chat_audios_read ON storage.objects;
CREATE POLICY chat_audios_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'chat-audios'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR public.is_dispatcher()
      OR public.is_admin()
    )
  );

-- Escritura: el rider sube en SU carpeta; dispatcher/admin pueden subir en cualquiera.
DROP POLICY IF EXISTS chat_audios_write ON storage.objects;
CREATE POLICY chat_audios_write ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-audios'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR public.is_dispatcher()
      OR public.is_admin()
    )
  );
