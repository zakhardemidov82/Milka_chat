import 'package:flutter/material.dart';
import 'package:milka_chat/screens/rooms_list_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:milka_chat/models/user_model.dart';
import 'package:milka_chat/screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Наша залізна ініціалізація Supabase
  await Supabase.initialize(
    url: 'https://cdiicutdbugowjzvridb.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNkaWljdXRkYnVnb3dqenZyaWRiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NTU3MzEsImV4cCI6MjA5NjQzMTczMX0.uyORJMnyYu1uDmSlpeJtZ1UOGCrZFPYcSy5UlJMgBEk',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // ФУНКЦІЯ ПЕРЕВІРКИ ДОСТУПУ: тепер повертає просту Map (карту даних),
  // щоб уникнути конфліктів дублювання класів UserModel у різних файлах
  Future<UserModel> _checkUserAccess(String userId) async {
    final supabase = Supabase.instance.client;

    try {
      print('🛰️ РОБЛЮ ЗАПИТ ДЛЯ ID: $userId');
      final List<dynamic> response = await supabase
          .from('profiles')
          .select()
          .eq('id', userId);

      if (response.isNotEmpty) {
        final data = response.first;
        // Повертаємо чистий UserModel
        return UserModel(
          id: data['id'].toString(),
          phoneNumber: '',
          displayName: data['display_name']?.toString() ?? 'Невідомий',
          role: data['role']?.toString() ?? 'family',
          isApproved: data['is_approved'] == true,
        );
      } else {
        return UserModel(id: userId, phoneNumber: '', displayName: 'Гість', role: 'family', isApproved: false);
      }
    } catch (e) {
      print('🚨 КРИТИЧНА ПОМИЛКА: $e');
      return UserModel(id: userId, phoneNumber: '', displayName: 'Помилка', role: 'family', isApproved: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Milka Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo),
      // Загортаємо в Builder, щоб дати кнопкам правильний внутрішній контекст Navigator
      home: Builder(
        builder: (innerContext) => Scaffold(
          appBar: AppBar(
            title: const Text('Оберіть профіль для тесту'),
            centerTitle: true,
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Під яким акаунтом зайти в додаток?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30),

                  _buildUserButton(innerContext, '1', '😎 Зайти як Шеф (ID: 1)', Colors.indigo),
                  const SizedBox(height: 15),

                  _buildUserButton(innerContext, '2', '🤝 Зайти як Побратим (ID: 2)', Colors.green),
                  const SizedBox(height: 15),

                  _buildUserButton(innerContext, '3', '🕵️ Зайти як Другий профіль (ID: 3)', Colors.orange),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserButton(BuildContext context, String userId, String label, Color color) {
    return SizedBox(
      width: 280,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (chatContext) => FutureBuilder<UserModel>(
                future: _checkUserAccess(userId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasData) {
                    return RoomsListScreen(currentUser: snapshot.data!);
                  }

                  return const Scaffold(
                    body: Center(child: Text('Помилка авторизації')),
                  );
                },
              ),
            ),
          );
        },
        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}