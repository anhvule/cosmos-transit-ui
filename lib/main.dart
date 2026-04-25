import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'providers/reading_provider.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'services/api_cache_service.dart';
import 'screens/predictions/predictions_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  await ApiCacheService.sweepStaleEntries();
  await MobileAds.instance.initialize();
  await NotificationService.init();
  runApp(const CosmicTransitApp());
}

class CosmicTransitApp extends StatelessWidget {
  const CosmicTransitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReadingProvider(),
      child: MaterialApp(
        title: 'CosmicTransit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF7C4DFF),
          scaffoldBackgroundColor: const Color(0xFF0D0B2E),
          fontFamily: 'SF Pro Display',
        ),
        home: const PredictionsScreen(),
      ),
    );
  }
}
