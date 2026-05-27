/// Envoltorio que escucha el stream de ofertas pendientes del rider.
///
/// Cuando llega una oferta NUEVA (id que no estaba antes), reproduce el
/// ringtone y muestra un SnackBar persistente con un botón "Ver" que abre
/// `/r/offers`. Se usa para envolver las screens del rider donde queremos
/// que la notificación interrumpa.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

import 'chat_ringtone.dart';
import 'offer_popup.dart';
import 'offer_ringtone.dart';

final myOffersStreamProvider = StreamProvider<List<Offer>>((ref) {
  return OffersRepository.instance.watchMyPending();
});

/// Stream del propio hilo del rider para detectar mensajes nuevos.
/// La family key es el `rider_id` (que para el rider es su propio user.id).
final _myChatStreamProvider = StreamProvider<List<ChatMessage>>((ref) {
  final u = La10Supabase.auth.currentUser;
  if (u == null) return Stream.value(const <ChatMessage>[]);
  return ChatRepository.instance.watchThread(u.id);
});

class OfferAlertGuard extends ConsumerStatefulWidget {
  const OfferAlertGuard({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<OfferAlertGuard> createState() => _OfferAlertGuardState();
}

class _OfferAlertGuardState extends ConsumerState<OfferAlertGuard> {
  // IDs de ofertas / mensajes ya alertados (no repetir sonido en rebuild).
  final _alertedOffers = <String>{};
  final _alertedMessages = <String>{};
  // Primer snapshot: lo usamos para silenciar lo viejo y solo alertar lo nuevo.
  bool _primedOffers = false;
  bool _primedMessages = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Offer>>>(myOffersStreamProvider, (_, next) {
      next.whenData(_onOffersSnapshot);
    });
    ref.listen<AsyncValue<List<ChatMessage>>>(_myChatStreamProvider, (_, next) {
      next.whenData(_onMessagesSnapshot);
    });
    return widget.child;
  }

  void _onOffersSnapshot(List<Offer> offers) {
    if (!_primedOffers) {
      _primedOffers = true;
      _alertedOffers.addAll(offers.map((o) => o.id));
      return;
    }
    for (final o in offers) {
      if (_alertedOffers.add(o.id)) _ringOffer(o);
    }
  }

  void _onMessagesSnapshot(List<ChatMessage> msgs) {
    if (!_primedMessages) {
      _primedMessages = true;
      _alertedMessages.addAll(msgs.map((m) => m.id));
      return;
    }
    final me = La10Supabase.auth.currentUser?.id;
    for (final m in msgs) {
      if (_alertedMessages.add(m.id)) {
        // Solo avisamos los que NO mandó el rider (los del jefe).
        if (m.senderUserId != me) _ringMessage(m);
      }
    }
  }

  void _ringMessage(ChatMessage m) {
    ChatRingtone.instance.play();
    if (!mounted) return;
    final preview = m.isAudio ? '🎤 Audio del dispatch' : 'Mensaje del dispatch';
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              const Icon(Icons.chat_bubble, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  preview,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Abrir',
            textColor: Colors.white,
            onPressed: () => context.push('/r/chat'),
          ),
        ),
      );
  }

  void _ringOffer(Offer offer) {
    OfferRingtone.instance.play();
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent ?? true) {
      showOfferPopup(context, offer);
    }
  }
}
