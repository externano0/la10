/// Hilo de chat 1-a-1 entre el jefe y un rider.
/// La misma screen sirve para ambos lados: el `riderId` define el hilo,
/// y RLS se encarga de que cada uno solo vea/escriba lo que le corresponde.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

import 'audio_recorder.dart';
import 'audio_bubble_player.dart';

/// Provider parametrizado por `riderId`: cada hilo tiene su propio stream.
final chatThreadProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, riderId) {
  return ChatRepository.instance.watchThread(riderId);
});

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.riderId, required this.title});

  /// Identificador del hilo (siempre el `user_id` del rider).
  final String riderId;

  /// Lo que se muestra en el AppBar (típicamente el nombre del rider).
  final String title;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scrollCtl = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ChatRepository.instance.send(riderId: widget.riderId, body: body);
      _input.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo enviar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    // Scrollea al final cuando llega un mensaje nuevo. Diferido para que
    // el ListView ya tenga el item incorporado en el layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtl.hasClients) return;
      _scrollCtl.animateTo(
        _scrollCtl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chatThreadProvider(widget.riderId));

    // Cada vez que llega un mensaje nuevo, scrollea al fondo.
    ref.listen(chatThreadProvider(widget.riderId), (_, next) {
      next.whenData((_) => _scrollToBottom());
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (msgs) {
                if (msgs.isEmpty) {
                  return const Center(
                    child: Text('Sin mensajes todavía. Escribí algo abajo.'),
                  );
                }
                final meId = La10Supabase.auth.currentUser?.id;
                return ListView.builder(
                  controller: _scrollCtl,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) =>
                      _Bubble(msg: msgs[i], mine: msgs[i].senderUserId == meId),
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  AudioRecorderButton(riderId: widget.riderId),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Escribí un mensaje…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.mine});
  final ChatMessage msg;

  /// True si el mensaje lo mandó el usuario que está mirando ahora.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final color = mine ? cs.primary : cs.surfaceContainerHighest;
    final fg = mine ? cs.onPrimary : cs.onSurface;

    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (msg.isAudio)
              AudioBubblePlayer(message: msg, foreground: fg)
            else
              Text(msg.body, style: TextStyle(color: fg)),
            const SizedBox(height: 4),
            Text(
              _hhmm(msg.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: fg.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
