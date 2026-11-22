import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/database_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final storageService = StorageService();
  runApp(EpubMobileApp(databaseService: DatabaseService(storageService)));
}

class EpubMobileApp extends StatelessWidget {
  const EpubMobileApp({super.key, required this.databaseService});

  final DatabaseService databaseService;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      databaseService: databaseService,
      child: MaterialApp(
        title: 'EPUB Mobile',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const HomeScreen(),
      ),
    );
  }
}

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.databaseService,
    required super.child,
  });

  final DatabaseService databaseService;

  static DatabaseService databaseOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!.databaseService;
  }

  static DatabaseService readDatabase(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    final scope = element?.widget as AppScope?;
    assert(scope != null, 'AppScope is missing');
    return scope!.databaseService;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return databaseService != oldWidget.databaseService;
  }
}
