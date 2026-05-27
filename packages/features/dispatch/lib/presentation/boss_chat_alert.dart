/// Aviso global al jefe cuando un rider le manda un mensaje.
///
/// Suscribimos al stream de `chat_messages` (RLS ya filtra: el jefe ve todo).
/// Cuando aparece un mensaje nuevo que NO mandó él, suena y aparece un
/// SnackBar con el nombre del rider + botón "Abrir".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

import 'chat_ringtone.dart';

final _allChatStreamProvider = StreamProvider<List<ChatMessage>>((ref) {
  // Limitamos a los últimos N por rendimiento; el stream solo refleja cambios.
  return La10Supabase.client
      .from('chat_messages')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows.map(ChatMessage.fromJson).toList());
});

final _ridersIndexProvider = FutureProvider<Map<String, String>>((ref) async {
  final rs = await RidersRepository.instance.listAll();
  return {for (final r in rs) r.userId: r.displayName};
});

class BossChatAlert extends ConsumerStatefulWidget {
  const BossChatAlert({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<BossChatAlert> createState() => _BossChatAlertState();
}

class _BossChatAlertState extends ConsumerState<BossChatAlert> {
  final _alerted = <String>{};
  bool _primed = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<ChatMessage>>>(_allChatStreamProvider, (_, next) {
      next.whenData(_onSnapshot);
    });
    return widget.child;
  }

  void _onSnapshot(List<ChatMessage> msgs) {
    if (!_primed) {
      _primed = true;
      _alerted.addAll(msgs.map((m) => m.id));
      return;
    }
    final me = La10Supabase.auth.currentUser?.id;
    for (final m in msgs) {
      if (_alerted.add(m.id) && m.senderUserId != me) {
        _ring(m);
      }
    }
  }

  void _ring(ChatMessage m) {
    ChatRingtone.instance.play();
    if (!mounted) return;
    final ridersIndex = ref.read(_ridersIndexProvider).asData?.value ?? const {};
    final who = ridersIndex[m.riderId] ?? 'Rider';
    final preview = m.isAudio ? '🎤 ${m.body.isEmpty ? "Audio" : m.body}' : m.body;
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          backgroundColor: Theme.of(context).colorScheme.primary,
          content: Row(
            children: [
              const Icon(Icons.chat_bubble, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      who,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      preview,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Abrir',
            textColor: Colors.white,
            onPressed: () => context.push('/d/chat/${m.riderId}?name=${Uri.encodeComponent(who)}'),
          ),
        ),
      );
  }
}
