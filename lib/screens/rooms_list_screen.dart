import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'group_chat_screen.dart';

class RoomsListScreen extends StatefulWidget {
  final UserModel currentUser; // Переконайся, що тут написано саме так!

  const RoomsListScreen({Key? key, required this.currentUser}) : super(key: key);

  @override
  State<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends State<RoomsListScreen> {
  final _supabase = Supabase.instance.client;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Кімнати: ${widget.currentUser.displayName}'),
        backgroundColor: Colors.teal,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _supabase.from('room_members').select('room_id, rooms(id, name, creator_id)').eq('user_id', widget.currentUser.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final myMemberships = snapshot.data!;
          if (myMemberships.isEmpty) {
            return const Center(child: Text('Ви ще не створили жодної групи і вас нікуди не запросили.'));
          }

          return ListView.builder(
            itemCount: myMemberships.length,
            itemBuilder: (context, index) {
              if (myMemberships[index]['rooms'] == null) return const SizedBox.shrink();

              final roomInfo = myMemberships[index]['rooms'] as Map<String, dynamic>;
              final String rId = roomInfo['id'] ?? '';
              final String rName = roomInfo['name'] ?? 'Без назви';
              final String cId = roomInfo['creator_id'] ?? '';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.group, color: Colors.teal, size: 30),
                  title: Text(rName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(cId == widget.currentUser.id ? '👑 Ви адмін' : '👤 Учасник'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GroupChatScreen(
                          currentUser: widget.currentUser,
                          roomId: rId,
                          roomName: rName,
                          creatorId: cId,
                        ),
                      ),
                    ).then((_) {
                      if (mounted) setState(() {});
                    });
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