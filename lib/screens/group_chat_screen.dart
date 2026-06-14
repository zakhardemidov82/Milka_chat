import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class GroupChatScreen extends StatefulWidget {
  final UserModel currentUser;
  final String roomId;
  final String roomName;
  final String creatorId;

  const GroupChatScreen({
    Key? key,
    required this.currentUser,
    required this.roomId,
    required this.roomName,
    required this.creatorId,
  }) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final _supabase = Supabase.instance.client;

  // 1. СТВОРЮЄМО ФОКУС-НОДУ
  final FocusNode _focusNode = FocusNode();
  // 🎨 ПАЛІТРА ПРИЄМНИХ КОЛЬОРІВ ДЛЯ РІЗНИХ УЧАСНИКІВ (для їхніх повідомлень зліва)
  final List<Color> _userColors = [
    Colors.amber,       // М'який жовтий
    Colors.blue,        // Ніжно-синій
    Colors.lightGreen,  // Салатовий
    Colors.purple,      // Бузковий
    Colors.orange,      // Помаранчевий
    Colors.pink,        // Рожевий
    Colors.cyan,        // Бірюзовий
  ];

  bool get isAdmin => widget.currentUser.id == widget.creatorId;

  // Функція, яка повертає унікальний колір для кожного користувача
  Color _getBubbleColor(String senderId) {
    if (senderId.isEmpty) return Colors.grey;

    // Надійний алгоритм, який перетворює БУДЬ-ЯКИЙ текст (UUID) в унікальне число
    int hash = 0;
    for (int i = 0; i < senderId.length; i++) {
      hash = senderId.codeUnitAt(i) + ((hash << 5) - hash);
    }

    // Беремо залишок від ділення на кількість твоїх 7 кольорів
    final int colorIndex = hash.abs() % _userColors.length;

    // Повертаємо чистий колір, але додаємо .withOpacity(0.2),
    // щоб хмаринка була ніжною (пастельною), і чорний текст на ній читався ідеально!
    return _userColors[colorIndex].withOpacity(0.2);
  }

  // 2. АВТОМАТИЧНО СТАВИМО ФОКУС ПРИ ВХОДІ В ЧАТ
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  // 3. НЕ ЗАБУВАЄМО ОЧИСТИТИ ПАМ'ЯТЬ ПРИ ВИХОДІ
  @override
  void dispose() {
    _focusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await _supabase.from('messages').insert({
        'text': text,
        'sender_id': widget.currentUser.id,
        'room_id': widget.roomId,
      });
      _messageController.clear();

      // ПОВЕРТАЄМО КУРСОР НАЗАД В ПОЛЕ
      _focusNode.requestFocus();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
    }
  }

  // Відкриваємо вікно керування учасниками
  void _openManageMembersDialog() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  Text(widget.roomName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(isAdmin ? '👑 Ви Адмін цього чату' : '👥 Учасники чату', style: const TextStyle(color: Colors.grey)),
                  const Divider(),

                  // Список поточних учасників
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _supabase.from('room_members').select('user_id, profiles(display_name)').eq('room_id', widget.roomId),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final List<Map<String, dynamic>> messagesList = List<Map<String, dynamic>>.from(snapshot.data!);

                        if (messagesList.isEmpty) {
                          return const Center(child: Text('У цьому чаті ще немає повідомлень.'));
                        }

                        return ListView.builder(
                          itemCount: messagesList.length,
                          itemBuilder: (context, index) {
                            final msg = messagesList[index];

                            // 1. БЕЗПЕЧНО ДІСТАЄМО SENDER_ID
                            final String senderId = msg['sender_id']?.toString() ?? '';
                            final bool isMe = senderId == widget.currentUser.id;

                            // 2. ВИЗНАЧАЄМО КОЛІР БУЛЬБАШКИ
                            // Якщо моє — Colors.indigo, якщо чуже — розфарбовуємо по ID
                            final Color bubbleColor = isMe
                                ? Colors.indigo
                                : _getBubbleColor(senderId);

                            // 3. ДІСТАЄМО DISPLAY_NAME, ЯКИЙ НАМ ОДРАЗУ ПОВЕРНУВ SUPABASE
                            // Завдяки твоєму крутому запиту, ім'я вже є в msg['profiles']!
                            String authorName = 'Абонент [$senderId]';
                            if (msg['profiles'] != null && msg['profiles']['display_name'] != null) {
                              authorName = msg['profiles']['display_name'].toString();
                            }

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  // Ім'я автора показуємо тільки для чужих повідомлень
                                  if (!isMe)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8, bottom: 2, top: 4),
                                      child: Text(
                                        authorName,
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold
                                        ),
                                      ),
                                    ),

                                  // Контейнер самого повідомлення
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: bubbleColor,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        // Робимо красиві зрізи кутів залежно від того, чиє повідомлення
                                        bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
                                        bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                                      ),
                                    ),
                                    child: Text(
                                      msg['text'] ?? '',
                                      // Для моїх (темно-синіх) — текст білий. Для чужих (пастельних) — чіткий чорний.
                                      style: TextStyle(
                                          color: isMe ? Colors.white : Colors.black87,
                                          fontSize: 16
                                      ),
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

                  // Кнопка додавання людей (Тільки для Адміна)
                  if (isAdmin)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_add),
                      label: const Text('Запросити людину за ID'),
                      onPressed: () async {
                        String targetId = '';
                        await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Додати учасника'),
                            content: TextField(
                              decoration: const InputDecoration(hintText: 'Введіть ID користувача (напр. 2)'),
                              onChanged: (val) => targetId = val.trim(),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати')),
                              TextButton(
                                onPressed: () async {
                                  if (targetId.isNotEmpty) {
                                    try {
                                      await _supabase.from('room_members').insert({'room_id': widget.roomId, 'user_id': targetId});
                                      Navigator.pop(context);
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Користувача не знайдено або вже додано')));
                                    }
                                  }
                                },
                                child: const Text('Додати'),
                              ),
                            ],
                          ),
                        );
                        setModalState(() {});
                      },
                    ),

                  // Кнопка "Вийти з чату" для звичайних смертних
                  if (!isAdmin)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Покинути чат'),
                      onPressed: () async {
                        await _supabase.from('room_members').delete().eq('room_id', widget.roomId).eq('user_id', widget.currentUser.id);
                        Navigator.pop(context); // закрити шторку
                        Navigator.pop(context); // вийти з чату
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('👥 ${widget.roomName}'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'Учасники та керування',
            onPressed: _openManageMembersDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              // Слухаємо повідомлення саме для цієї кімнати
              stream: _supabase.from('messages').stream(primaryKey: ['id']).order('created_at', ascending: true),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                // Фільтруємо повідомлення по нашому room_id
                final roomMessages = snapshot.data!.where((msg) => msg['room_id'] == widget.roomId).toList();

                if (roomMessages.isEmpty) {
                  return const Center(child: Text('У цій кімнаті ще немає повідомлень. Напишіть щось першим!'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: roomMessages.length,
                  itemBuilder: (context, index) {
                    final msg = roomMessages[index];
                    final String senderId = msg['sender_id']?.toString() ?? '';
                    final bool isMe = senderId == widget.currentUser.id;
                    final Color userColor = _getBubbleColor(senderId); // Твій індивідуальний колір з рядка 30!

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          // ПІДПИС АВТОРА (Працює завжди для всіх, хто не я)
                          if (!isMe)
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _supabase.from('profiles').select('display_name').eq('id', senderId),
                              builder: (context, profSnap) {
                                String authorName = 'Абонент [$senderId]';
                                if (profSnap.hasData && profSnap.data!.isNotEmpty) {
                                  authorName = profSnap.data!.first['display_name'] ?? authorName;
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                                  child: Text(authorName, style: TextStyle(color: isMe ? Colors.white : userColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                );
                              },
                            ),
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? Colors.teal : Colors.grey[300],
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
                    focusNode: _focusNode, // ПРИВ'ЯЗУЄМО НАШ ФОКУС ТУТ
                    decoration: const InputDecoration(
                      hintText: 'Напишіть повідомлення групі...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send, color: Colors.teal), onPressed: _sendMessage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}