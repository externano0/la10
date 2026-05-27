/// Repositorio de mensajes (texto y audio) entre el jefe y un rider.
/// Cada rider tiene un hilo único identificado por su `rider_id`.

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../supabase/client.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.riderId,
    required this.senderUserId,
    required this.body,
    required this.createdAt,
    this.audioUrl,
    this.audioDurationMs,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        riderId: j['rider_id'] as String,
        senderUserId: j['sender_user_id'] as String,
        body: (j['body'] as String?) ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        audioUrl: j['audio_url'] as String?,
        audioDurationMs: j['audio_duration_ms'] as int?,
      );

  final String id;
  final String riderId;
  final String senderUserId;
  final String body;
  final DateTime createdAt;

  /// Ruta del audio en el bucket `chat-audios` (no URL pública).
  /// Para reproducirlo hay que llamar `ChatRepository.signedAudioUrl(...)`.
  final String? audioUrl;
  final int? audioDurationMs;

  bool get isAudio => audioUrl != null && audioUrl!.isNotEmpty;
}

class ChatRepository {
  ChatRepository._();
  static final instance = ChatRepository._();

  /// Stream realtime del hilo completo del rider, del más viejo al más nuevo.
  Stream<List<ChatMessage>> watchThread(String riderId) {
    return La10Supabase.client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('rider_id', riderId)
        .order('created_at')
        .map((rows) => rows.map(ChatMessage.fromJson).toList());
  }

  Future<void> send({required String riderId, required String body}) async {
    final u = La10Supabase.auth.currentUser;
    if (u == null) throw StateError('not authenticated');
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    await La10Supabase.client.from('chat_messages').insert({
      'rider_id': riderId,
      'sender_user_id': u.id,
      'body': trimmed,
    });
  }

  /// Sube el audio al bucket y crea el mensaje apuntando al objeto.
  /// `bytes` viene del MediaRecorder del browser (típicamente WebM/Opus).
  /// El path se arma como '<sender_uid>/<timestamp>.webm' para que la policy
  /// de storage permita el upload (la carpeta debe ser el uid del que sube).
  Future<void> sendAudio({
    required String riderId,
    required Uint8List bytes,
    required int durationMs,
    String contentType = 'audio/webm',
  }) async {
    final u = La10Supabase.auth.currentUser;
    if (u == null) throw StateError('not authenticated');
    final ext = contentType.contains('mp4') ? 'm4a' : 'webm';
    final path = '${u.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await La10Supabase.client.storage.from('chat-audios').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    await La10Supabase.client.from('chat_messages').insert({
      'rider_id': riderId,
      'sender_user_id': u.id,
      'body': '🎤',
      'audio_url': path,
      'audio_duration_ms': durationMs,
    });
  }

  /// Devuelve una URL temporal firmada para escuchar el audio.
  /// El bucket es privado: necesitamos firmar cada vez que se reproduce.
  Future<String> signedAudioUrl(String path, {int expiresSec = 60 * 60}) async {
    return La10Supabase.client.storage
        .from('chat-audios')
        .createSignedUrl(path, expiresSec);
  }
}

