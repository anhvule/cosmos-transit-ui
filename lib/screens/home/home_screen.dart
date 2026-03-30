import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/reading_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/focus_chip.dart';
import '../../widgets/ad_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // MVP: isPremium is hardcoded false, wired for future IAP
  final bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    // Fetch reading on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReadingProvider>().fetchReading();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = StorageService.getProfile();
    final provider = context.watch<ReadingProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, ${profile?.name ?? 'Stargazer'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('EEEE, MMMM d').format(DateTime.now()),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const Text('✦', style: TextStyle(fontSize: 32)),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Content area
                    if (provider.isLoading) _buildLoading(),
                    if (provider.error != null) _buildError(provider),
                    if (provider.hasReading && !provider.isLoading) ...[
                      // Transit summary
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Transits',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              provider.reading!.transitSummary,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Daily reading
                      const Text(
                        'Today\'s Reading',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        provider.reading!.reading,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Focus area chips
                      const Text(
                        'Focus Areas',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: provider.reading!.focusAreas
                            .map((fa) => FocusChip(focusArea: fa))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // AdMob banner at bottom
            AdBannerWidget(isPremium: _isPremium),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: [
            CircularProgressIndicator(color: Color(0xFF7C4DFF)),
            SizedBox(height: 16),
            Text(
              'Reading the cosmos...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ReadingProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            const Text('🌌', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              provider.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                provider.clearError();
                provider.fetchReading();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
