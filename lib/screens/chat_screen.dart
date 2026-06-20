import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

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
  final ImagePicker _picker = ImagePicker();

  StreamSubscription<List<Map<String, dynamic>>>? _pingSubscription;
  final DateTime _screenInitTime = DateTime.now().toUtc();

  // Змінні для зберігання текстів поточного користувача
  String? _btn1;
  String? _btn2;
  String? _btn3;
  String? _btn4;

  @override
  void initState() {
    super.initState();
    _startListeningToPings();
    _fetchMyButtons(); // ⚡ Завантажуємо налаштування при вході
  }

  // 📥 Завантажуємо тексти кнопок з мого профілю
  Future<void> _fetchMyButtons() async {
    try {
      final data = await _supabase
          .from('profiles')
          .select('btn1, btn2, btn3, btn4')
          .eq('id', widget.currentUser.id)
          .single();

      if (mounted) {
        setState(() {
          _btn1 = data['btn1']?.toString();
          _btn2 = data['btn2']?.toString();
          _btn3 = data['btn3']?.toString();
          _btn4 = data['btn4']?.toString();
        });
      }
    } catch (e) {
      debugPrint('Помилка завантаження кнопок: $e');
    }
  }

  // 📝 Діалог для налаштування кнопки (викликається довгим натисканням)
  void _editButtonText(int index, String? currentText) {
    String newText = currentText ?? '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Налаштування кнопки $index'),
        content: TextField(
          controller: TextEditingController(text: newText),
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Введіть текст повідомлення...',
            border: OutlineInputBorder(),
          ),
          onChanged: (val) => newText = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати')),
          ElevatedButton(
            onPressed: () async {
              try {
                // Зберігаємо новий текст у базу
                await _supabase
                    .from('profiles')
                    .update({'btn$index': newText.trim()})
                    .eq('id', widget.currentUser.id);
                await _fetchMyButtons(); // Оновлюємо UI
                if (mounted) Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
              }
            },
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );
  }

  // ⚡ Відправка мікро-коду на сервер
  void _sendQuickMessage(String code) async {
    try {
      await _supabase.from('messages').insert({
        'text': code,
        'sender_id': widget.currentUser.id,
        'receiver_id': widget.targetReceiverId,
      });
      // Жодних ручних прокруток тут більше немає!
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка відправки: $e')));
    }
  }

  // 🧱 Віджет самої розумної кнопки
  Widget _buildTacticalButton(int index, String? configuredText) {
    final hasText = configuredText != null && configuredText.trim().isNotEmpty;
    final buttonLabel = hasText ? '$index' : '?';
    // Якщо налаштована - синя. Якщо пуста - сіра.
    final bgColor = hasText ? Colors.blue.shade700 : Colors.grey.shade400;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: bgColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            if (!hasText) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Затисніть кнопку, щоб додати текст')),
              );
              return;
            }
            _sendQuickMessage('#BTN$index#'); // Відправляємо код!
          },
          onLongPress: () => _editButtonText(index, configuredText),
          child: Text(
            buttonLabel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
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

      if (pingTime.isAfter(_screenInitTime) &&
          senderId != widget.currentUser.id &&
          receiverId == widget.currentUser.id) {

        try {
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

  void _sendPing() async {
    try {
      await _supabase.from('pings').insert({
        'sender_id': widget.currentUser.id,
        'sender_name': widget.currentUser.displayName,
        'receiver_id': widget.targetReceiverId,
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

  // 📸 Функція вибору та відправки фото
  Future<void> _sendMediaFile() async {
    try {
      // 1. Відкриваємо системне вікно вибору БУДЬ-ЯКОГО файлу
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Дозволяємо вибирати все: фото, відео, доки
        withData: true,     // Обов'язково для читання байтів (працює всюди)
      );

      if (result == null || result.files.isEmpty) return; // Користувач скасував вибір

      final selectedFile = result.files.first;
      final bytes = selectedFile.bytes;
      if (bytes == null) return;

      // 2. Визначаємо тип файлу за його розширенням
      final fileExt = selectedFile.extension?.toLowerCase() ?? '';
      String messageType = 'file'; // За замовчуванням — звичайний документ

      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExt)) {
        messageType = 'image';
      } else if (['mp4', 'mov', 'avi', 'mkv', '3gp'].contains(fileExt)) {
        messageType = 'video';
      }

      // 3. Генеруємо унікальне ім'я для бакета, щоб файли не перезаписували один одного
      final uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_${selectedFile.name}';
      final filePath = 'uploads/$messageType/$uniqueFileName';

      // 4. Завантажуємо в наш уже готовий бакет 'chat_media'
      await _supabase.storage.from('chat_media').uploadBinary(
        filePath,
        bytes,
      );

      // 5. Отримуємо пряме публічне посилання
      final fileUrl = _supabase.storage.from('chat_media').getPublicUrl(filePath);

      // 6. Записуємо повідомлення в базу Supabase
      await _supabase.from('messages').insert({
        'sender_id': widget.currentUser.id,
        'receiver_id': widget.targetReceiverId, // Твоя змінна для отримувача
        'text': selectedFile.name, // В текст запишемо оригінальне ім'я файлу
        'file_url': fileUrl,       // Універсальне поле для лінка
        'message_type': messageType // 'image', 'video' або 'file'
      });

      print('🚀 Медіа-повідомлення типу [$messageType] успішно відправлено!');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🚨 Помилка відправки файлу: $e')),
      );
    }
  }

  // 👁️ Автоматично позначаємо чужі повідомлення як прочитані
  void _markMessagesAsRead(List<Map<String, dynamic>> messages) {
    for (var msg in messages) {
      final rId = msg['receiver_id']?.toString().trim();
      final myId = widget.currentUser.id.toString().trim();
      final currentStatus = msg['status']?.toString() ?? 'sent';

      // Якщо повідомлення адресоване МЕНІ, і воно ще не прочитане
      if (rId == myId && currentStatus != 'read' && currentStatus != 'прочитано') {

        print('📡 Спроба оновити статус на read для повідомлення: ${msg['id']}');

        _supabase
            .from('messages')
            .update({'status': 'read'})
            .eq('id', msg['id'])
            .then((_) {
          print('✅ УСПІХ! Статус оновлено в базі.');
        })
            .catchError((error) {
          print('❌ ПОМИЛКА SUPABASE під час оновлення: $error');
        });
      }
    }
  }

  // ✅ Генератор галочок (одна, дві сірі, дві кольорові)
  Widget _buildStatusIcon(String status, bool isMyMessage) {
    if (!isMyMessage) return const SizedBox.shrink(); // Чужим галочки не малюємо

    // Оскільки твої бульбашки сині, 'прочитано' зробимо салатовим для контрасту
    if (status == 'read' || status == 'прочитано') {
      return const Icon(Icons.done_all, color: Colors.greenAccent, size: 16);
    } else if (status == 'delivered' || status == 'доставлено') {
      return const Icon(Icons.done_all, color: Colors.white70, size: 16);
    } else {
      // За замовчуванням 'sent' / 'відправлено'
      return const Icon(Icons.check, color: Colors.white70, size: 16);
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
                  .order('created_at', ascending: false), // 👈 НАЙНОВІШІ ПЕРШІ
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

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markMessagesAsRead(privateMessages);
                });


                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  reverse: true, // 👈 МАГІЯ: СПИСОК ПЕРЕВЕРНУТИЙ
                  itemCount: privateMessages.length,
                  itemBuilder: (context, index) {
                    final msg = privateMessages[index];
                    final String senderId = msg['sender_id']?.toString() ?? '';
                    final bool isMe = senderId == widget.currentUser.id;
                    final String status = msg['status']?.toString() ?? 'sent';

                    // --- 1. Логіка радара: попередження про недоставку ---
                    bool showDeliveryWarning = false;
                    final String createdAtStr = msg['created_at']?.toString() ?? '';

                    if (isMe && status == 'sent' && createdAtStr.isNotEmpty) {
                      final DateTime createdAt = DateTime.parse(createdAtStr).toLocal();
                      final Duration difference = DateTime.now().difference(createdAt);
                      if (difference.inMinutes >= 1) { // 👈 Тут стоїть 1 хвилина, можеш повернути на 10
                        showDeliveryWarning = true;
                      }
                    }

                    // --- 2. Перевірка наявності фото ---
                    final String? imageUrl = msg['image_url']?.toString();

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          // --- 3. Ім'я співрозмовника (FutureBuilder) ---
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

                          // --- 4. Головний контейнер (Бульбашка повідомлення) ---
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? Colors.indigo : Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min, // Щоб бульбашка не розтягувалась
                              children: [
                                // Якщо є фото — малюємо його зверху
                                if (imageUrl != null && imageUrl.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        imageUrl,
                                        width: 200,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return const SizedBox(
                                              width: 200, height: 200,
                                              // Білий індикатор для твоїх синіх бульбашок, синій для сірих
                                              child: Center(child: CircularProgressIndicator(color: Colors.white))
                                          );
                                        },
                                      ),
                                    ),
                                  ),

                                // Текст повідомлення та галочки (внизу під фото, або самі по собі)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        msg['text'] ?? '',
                                        style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 16),
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 6),
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: _buildStatusIcon(status, isMe),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // --- 5. Технічне повідомлення про недоставку (під бульбашкою) ---
                          if (showDeliveryWarning)
                            const Padding(
                              padding: EdgeInsets.only(top: 2, bottom: 6, right: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.info_outline, size: 14, color: Colors.grey),
                                  SizedBox(width: 4),
                                  Text(
                                    'Абонент поза мережею. Доставимо пізніше.',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic
                                    ),
                                  ),
                                ],
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

          // 🎛️ Швидкі кнопки + Поле вводу
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildTacticalButton(1, _btn1),
                    _buildTacticalButton(2, _btn2),
                    _buildTacticalButton(3, _btn3),
                    _buildTacticalButton(4, _btn4),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Напишіть повідомлення...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file, color: Colors.indigo), // Змінили іконку на скріпку
                      onPressed: _sendMediaFile, // Викликаємо нашу нову універсальну функцію файлів
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.indigo),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}