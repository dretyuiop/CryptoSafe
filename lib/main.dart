import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptosafe/business/crypto/index.dart';
import 'package:cryptosafe/presentation/screens/first_setup_screen.dart';
import 'package:cryptosafe/presentation/screens/home_screen.dart';
import 'package:cryptosafe/presentation/screens/upload_screen.dart';
import 'package:cryptosafe/presentation/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  final firstSetupDone = prefs.getBool('first_setup_done') ?? false;

  if (firstSetupDone) {
    Future(() async {
      await readIndexCloud();
    });
  }

  runApp(MyApp(firstSetupDone: firstSetupDone));
}

class MyApp extends StatelessWidget {
  final bool firstSetupDone;
  const MyApp({super.key, required this.firstSetupDone});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HowApp',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: firstSetupDone
          ? const MainNavigationScreen()
          : const FirstSetupScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const UploadScreen(),
    const SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.cloud_upload), label: 'Upload'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
