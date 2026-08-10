import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'providers/pos_provider.dart';
import 'providers/settings_provider.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/splash_setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Wajib sebelum pakai DateFormat locale 'id_ID' (dipakai di absen, rekap, struk).
  await initializeDateFormatting('id_ID', null);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => PosProvider()),
      ],
      child: const RuangSenyawaApp(),
    ),
  );
}

class RuangSenyawaApp extends StatelessWidget {
  const RuangSenyawaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          title: 'Ruang Senyawa POS',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(settings.fontScale),
          darkTheme: AppTheme.darkTheme(settings.fontScale),
          themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(settings.fontScale),
              ),
              child: Listener(
                onPointerDown: (_) => settings.userInteracted(),
                child: child!,
              ),
            );
          },
          home: const SplashSetupScreen(),
        );
      },
    );
  }
}
