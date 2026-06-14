import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class ChatScreen extends StatefulWidget {
  final UserModel currentUser;
  final String targetReceiverId;

  const ChatScreen({
    Key? key,
    required this.currentUser,
    this.targetReceiverId = '1',
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final _supabase = Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _pingSubscription;
  final DateTime _screenInitTime = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _startListeningToPings();
  }

  @override
  void dispose() {
    _pingSubscription?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  // 🚨 ПРИВАТНИЙ РАДАР ТРИВОГИ
  void _startListeningToPings() {
    _pingSubscription = _supabase
        .from('pings')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(1)
        .listen((data) async {
      if (data.isEmpty) return;

      final latestPing = data.first;
      final String senderId = latestPing['sender_id']?.toString() ?? '';
      final String receiverId = latestPing['receiver_id']?.toString() ?? '';
      final String createdAtStr = latestPing['created_at'] ?? '';

      if (createdAtStr.isEmpty) return;
      final DateTime pingTime = DateTime.parse(createdAtStr).toUtc();

      // ЧІТКА ТАКТИЧНА УМОВА:
      // 1. Сигнал свіжий
      // 2. Відправник — НЕ я
      // 3. Цей сигнал відправлено САМЕ МЕНІ (receiver_id == мій id)
      if (pingTime.isAfter(_screenInitTime) &&
          senderId != widget.currentUser.id &&
          receiverId == widget.currentUser.id) {

        try {
          // Беремо чесне ім'я з profiles по ID відправника
          final profileData = await _supabase
              .from('profiles')
              .select('display_name')
              .eq('id', senderId)
              .maybeSingle();

          final String realSenderName = profileData != null
              ? (profileData['display_name'] ?? 'Абонент [$senderId]')
              : 'Абонент [$senderId]';

          _showEmergencyOverlay(realSenderName);

        } catch (e) {
          _showEmergencyOverlay('Користувач (ID: $senderId)');
        }
      }
    });
  }

  void _showEmergencyOverlay(String attackerName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red[900],
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.white, size: 30),
            SizedBox(width: 10),
            Text('🚨 ПРИВАТНИЙ SOS! 🚨', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Увага! Користувач [$attackerName] надіслав вам сигнал тривоги з приватного чату!',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red[900]),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Прийнято / Зрозуміло'),
          ),
        ],
      ),
    );
  }

  // 🚨 ВІДПРАВКА SOS З ВКАЗІВКОЮ ОТРИМУВАЧА
  void _sendPing() async {
    try {
      await _supabase.from('pings').insert({
        'sender_id': widget.currentUser.id,
        'sender_name': widget.currentUser.displayName,
        'receiver_id': widget.targetReceiverId, // ТЕПЕР ЗАПИСУЄМО, КОМУ ЛЕТИТЬ ТРИВОГА!
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚨 ПРИВАТНИЙ СИГНАЛ SOS ВІДПРАВЛЕНО!'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка SOS: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await _supabase.from('messages').insert({
        'text': text,
        'sender_id': widget.currentUser.id,
        'receiver_id': widget.targetReceiverId,
      });
      _messageController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка відправки: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<List<Map<String, dynamic>>>(
          future: _supabase.from('profiles').select('display_name').eq('id', widget.targetReceiverId),
          builder: (context, snapshot) {
            String receiverName = 'Абонент [${widget.targetReceiverId}]';
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              receiverName = snapshot.data!.first['display_name'] ?? receiverName;
            }
            return Text('${widget.currentUser.displayName} ➡️ $receiverName');
          },
        ),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.gpp_bad, color: Colors.redAccent, size: 30),
            tooltip: 'Оголосити тривогу SOS у цей чат',
            onPressed: _sendPing,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .order('created_at', ascending: true),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allMessages = snapshot.data!;

                final privateMessages = allMessages.where((msg) {
                  final sId = msg['sender_id']?.toString();
                  final rId = msg['receiver_id']?.toString();

                  final bool iSentToHim = (sId == widget.currentUser.id && rId == widget.targetReceiverId);
                  final bool heSentToMe = (sId == widget.targetReceiverId && rId == widget.currentUser.id);

                  return iSentToHim || heSentToMe;
                }).toList();

                if (privateMessages.isEmpty) {
                  return const Center(child: Text('Приватна переписка порожня.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: privateMessages.length,
                  itemBuilder: (context, index) {
                    final msg = privateMessages[index];
                    final String senderId = msg['sender_id']?.toString() ?? '';
                    final bool isMe = senderId == widget.currentUser.id;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _supabase.from('profiles').select('display_name').eq('id', senderId),
                              builder: (context, profileSnapshot) {
                                String name = 'Абонент [$senderId]';
                                if (profileSnapshot.hasData && profileSnapshot.data!.isNotEmpty) {
                                  name = profileSnapshot.data!.first['display_name'] ?? name;
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                                  child: Text(name, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                );
                              },
                            ),
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? Colors.indigo : Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              msg['text'] ?? '',
                              style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Напишіть приватне повідомлення...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.indigo),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}