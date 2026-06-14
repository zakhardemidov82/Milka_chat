import 'package:flutter/material.dart';
import 'package:milka_chat/screens/rooms_list_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/user_model.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Наша залізна ініціалізація Supabase
  await Supabase.initialize(
    url: 'https://cdiicutdbugowjzvridb.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNkaWljdXRkYnVnb3dqenZyaWRiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NTU3MzEsImV4cCI6MjA5NjQzMTczMX0.uyORJMnyYu1uDmSlpeJtZ1UOGCrZFPYcSy5UlJMgBEk', // Твій публічний ключ
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // ФУНКЦІЯ ПЕРЕВІРКИ ДОСТУПУ В БАЗІ ДАНИХ
  Future<UserModel> _checkUserAccess(String userId) async {
    final supabase = Supabase.instance.client;

    try {
      print('🛰️ РОБЛЮ ЗАПИТ ДЛЯ ID: $userId');

      // Беремо звичайним списком select() без хитрих модифікаторів
      final List<dynamic> response = await supabase
          .from('profiles')
          .select()
          .eq('id', userId);

      print('📡 ВІДПОВІДЬ ВІД БАЗИ profiles: $response');

      if (response.isNotEmpty) {
        final data = response.first; // Беремо перший рядок з масиву
        print('✅ ЗНАЙДЕНО: ${data['display_name']}, СТАТУС: ${data['is_approved']}');

        return UserModel(
          id: data['id'].toString(),
          phoneNumber: '',
          displayName: data['display_name']?.toString() ?? 'Невідомий',
          role: data['role']?.toString() ?? 'family',
          isApproved: data['is_approved'] == true,
        );
      } else {
        print('❌ У ТАБЛИЦІ profiles НЕМАЄ ЗАПИСУ З ID: $userId');
        return UserModel(
          id: userId,
          phoneNumber: '',
          displayName: 'Гість',
          role: 'family',
          isApproved: false,
        );
      }
    } catch (e) {
      print('🚨 КРИТИЧНА ПОМИЛКА: $e');
      return UserModel(
        id: userId,
        phoneNumber: '',
        displayName: 'Помилка зв\'язку',
        role: 'family',
        isApproved: false,
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    // ІМІТУЄМО ID ПРИСТРОЮ, ЯКИЙ НАМАГАЄТЬСЯ ЗАЙТИ
    // Спробуй міняти цей ID для тесту: '1' - Шеф, '2' - Побратим, '3' - Шпигун
    const String currentDeviceUserId = '1';

    return MaterialApp(
      title: 'Milka Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo),

      // Використовуємо FutureBuilder, щоб додаток спочатку запитав дозвіл у Франкфурта
      home: FutureBuilder<UserModel>(
        future: _checkUserAccess(currentDeviceUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()), // Крутилка, поки база думає
            );
          }

          if (snapshot.hasData) {
            final user = snapshot.data!;
            // Передаємо перевіреного юзера в чат
            return RoomsListScreen(currentUser: user);
          }

          return const Scaffold(
            body: Center(child: Text('Критична помилка запуску.')),
          );
        },
      ),
    );
  }
}
