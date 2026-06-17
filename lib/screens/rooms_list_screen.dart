import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'group_chat_screen.dart';
import 'chat_screen.dart';

class RoomsListScreen extends StatefulWidget {
  final UserModel currentUser; // Переконайся, що тут написано саме так!

  const RoomsListScreen({Key? key, required this.currentUser}) : super(key: key);

  @override
  State<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends State<RoomsListScreen> {
  final _supabase = Supabase.instance.client;

  // 👈 Додаємо ініціалізацію, якщо її ще немає
  @override
  void initState() {
    super.initState();
    _markIncomingAsDelivered(); // Запускаємо наш радар
  }

  // 📡 Радар: ловить нові повідомлення і ставить статус "Доставлено"
  void _markIncomingAsDelivered() {
    final myId = widget.currentUser.id;

    // Підключаємось до живого потоку повідомлень, де отримувач — Я
    _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', myId)
        .listen((List<Map<String, dynamic>> messages) {

      for (var msg in messages) {
        final status = msg['status']?.toString() ?? 'sent';

        // Якщо хтось відправив мені повідомлення (sent), і я в мережі -> міняємо на delivered
        if (status == 'sent') {
          _supabase
              .from('messages')
              .update({'status': 'delivered'})
              .eq('id', msg['id'])
              .then((_) => print('✅ Повідомлення ${msg['id']} доставлено!'))
              .catchError((e) => print('❌ Помилка доставки: $e'));
        }
      }
    });
  }

  void _createNewRoom() async {
    // 1. ПЕРЕВІРКА НА "ПРИВИДА": Якщо ID фейковий або користувач незатверджений
    if (widget.currentUser.id == '4' || widget.currentUser.displayName == 'Гість') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🚨 Помилка доступу'),
          content: const Text('Вашого пристрою або ID немає в базі тактичної групи. Створення кімнат заблоковано.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Зрозуміло'),
            ),
          ],
        ),
      );
      return; // Зупиняємо виконання функції, далі код не піде
    }

    String roomName = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Створити тактичну групу'),
        content: TextField(
          decoration: const InputDecoration(hintText: 'Назва чату (напр. Сім\'я)'),
          onChanged: (val) => roomName = val.trim(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати')),
          TextButton(
            onPressed: () async {
              if (roomName.isNotEmpty) {
                try {
                  // Спроба вставити дані в Supabase
                  final roomData = await _supabase.from('rooms').insert({
                    'name': roomName,
                    'creator_id': widget.currentUser.id,
                  }).select().single();

                  await _supabase.from('room_members').insert({
                    'room_id': roomData['id'],
                    'user_id': widget.currentUser.id,
                  });

                  Navigator.pop(context);
                  if (mounted) setState(() {});
                } catch (e) {
                  // ЯКЩО БАЗА ПОВЕРНЕ ПОМИЛКУ — МИ ЇЇ ПОБАЧИМО
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.red,
                      content: Text('Помилка бази даних: $e'),
                    ),
                  );
                }
              }
            },
            child: const Text('Створити'),
          ),
        ],
      ),
    );
  }

  // 🧠 Збирає групові та активні приватні чати в єдиний список
  Future<List<Map<String, dynamic>>> _fetchCombinedChats() async {
    final myId = widget.currentUser.id;

    // 1. Беремо групові чати (як і раніше)
    final groupRes = await _supabase
        .from('room_members')
        .select('room_id, rooms(id, name, creator_id)')
        .eq('user_id', myId);

    // 2. Шукаємо активні приватні діалоги (повідомлення без room_id, де я відправник АБО отримувач)
    final privateMsgsRes = await _supabase
        .from('messages')
        .select('sender_id, receiver_id')
        .isFilter('room_id', null)
        .or('sender_id.eq.$myId,receiver_id.eq.$myId');

    // 3. Збираємо унікальні ID людей, з якими є хоча б одне повідомлення
    Set<String> activeContactIds = {};
    for (var msg in privateMsgsRes) {
      final sId = msg['sender_id']?.toString() ?? '';
      final rId = msg['receiver_id']?.toString() ?? '';
      if (sId.isNotEmpty && sId != myId) activeContactIds.add(sId);
      if (rId.isNotEmpty && rId != myId) activeContactIds.add(rId);
    }

    // 4. Отримуємо профілі, щоб підтягнути імена (беремо тільки тих, з ким говорили)
    List<dynamic> activeProfiles = [];
    if (activeContactIds.isNotEmpty) {
      activeProfiles = await _supabase
          .from('profiles')
          .select('id, display_name')
          .inFilter('id', activeContactIds.toList()); // ТІЛЬКИ ті, з ким є чат!
    }

    // 5. Зливаємо все в єдиний стандартизований масив
    List<Map<String, dynamic>> combinedChats = [];

    // Додаємо групи
    for (var g in groupRes) {
      if (g['rooms'] != null) {
        combinedChats.add({
          'type': 'group',
          'id': g['rooms']['id']?.toString() ?? '',
          'name': g['rooms']['name']?.toString() ?? 'Без назви',
          'creator_id': g['rooms']['creator_id']?.toString() ?? '',
        });
      }
    }

    // Додаємо приватні чати
    for (var p in activeProfiles) {
      combinedChats.add({
        'type': 'private',
        'id': p['id'].toString(),
        'name': p['display_name']?.toString() ?? 'Абонент',
        'creator_id': '', // Для приватних не потрібно
      });
    }

    return combinedChats;
  }

  // НОВА ФУНКЦІЯ: Відкриває список контактів для приватного чату
  void _openContactsList() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text(
                'Особисті повідомлення',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Оберіть абонента для приватного зв\'язку:',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  // Дістаємо всіх користувачів із бази, КРІМ тебе самого
                  future: _supabase
                      .from('profiles')
                      .select('id, display_name')
                      .neq('id', widget.currentUser.id),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final contacts = snapshot.data!;
                    if (contacts.isEmpty) {
                      return const Center(child: Text('Більше немає зареєстрованих користувачів.'));
                    }

                    return ListView.builder(
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        final String contactId = contact['id'].toString();
                        final String contactName = contact['display_name']?.toString() ?? 'Невідомий';

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.indigo.shade100,
                              child: const Icon(Icons.person, color: Colors.indigo),
                            ),
                            title: Text(contactName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('ID: $contactId'),
                            trailing: const Icon(Icons.message, color: Colors.indigo),
                            onTap: () {
                              // 1. Спочатку закриваємо шторку контактів
                              Navigator.pop(context);
                              // 2. Перекидаємо в ПРИВАТНИЙ чат із передачею правильного ID
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    currentUser: widget.currentUser,
                                    targetReceiverId: contactId,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Кімнати: ${widget.currentUser.displayName}'),
        backgroundColor: Colors.teal,
        actions: [
          // 👤 НОВА КНОПКА: Відкриває список контактів
          IconButton(
            icon: const Icon(Icons.person_search, color: Colors.white, size: 28),
            tooltip: 'Написати особисто',
            onPressed: _openContactsList,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchCombinedChats(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Помилка: ${snapshot.error}'));
          }

          final allChats = snapshot.data ?? [];
          if (allChats.isEmpty) {
            return const Center(child: Text('У вас ще немає жодного чату. Почніть нову бесіду!'));
          }

          return ListView.builder(
            itemCount: allChats.length,
            itemBuilder: (context, index) {
              final chat = allChats[index];
              final bool isGroup = chat['type'] == 'group';
              final String chatId = chat['id'];
              final String chatName = chat['name'];
              final String creatorId = chat['creator_id'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  // Якщо група - іконка людей (teal). Якщо приват - іконка людини (indigo).
                  leading: Icon(
                    isGroup ? Icons.group : Icons.person,
                    color: isGroup ? Colors.teal : Colors.indigo,
                    size: 30,
                  ),
                  title: Text(chatName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    isGroup
                        ? (creatorId == widget.currentUser.id ? '👑 Група (Ви адмін)' : '👥 Група')
                        : '👤 Особистий чат',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (isGroup) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupChatScreen(
                            currentUser: widget.currentUser,
                            roomId: chatId,
                            roomName: chatName,
                            creatorId: creatorId,
                          ),
                        ),
                      ).then((_) { if (mounted) setState(() {}); });
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            currentUser: widget.currentUser,
                            targetReceiverId: chatId,
                          ),
                        ),
                      ).then((_) { if (mounted) setState(() {}); });
                    }
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: _createNewRoom,
        child: const Icon(Icons.add_comment, color: Colors.white),
      ),
    );
  }
}