import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import '../../models/user_profile.dart';
import '../../services/storage_service.dart';
import '../../services/notification_service.dart';
import '../home/home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Form data
  final _nameController = TextEditingController();
  DateTime _birthDate = DateTime(1995, 1, 1);
  TimeOfDay _birthTime = const TimeOfDay(hour: 12, minute: 0);
  final _cityController = TextEditingController();
  bool _isSubmitting = false;
  String? _cityError;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _submit() async {
    if (_cityController.text.trim().isEmpty) {
      setState(() => _cityError = 'Please enter your birth city');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _cityError = null;
    });

    try {
      // Geocode the city
      final locations = await locationFromAddress(_cityController.text.trim());
      if (locations.isEmpty) {
        setState(() => _cityError = 'City not found. Try a different spelling.');
        return;
      }

      final location = locations.first;
      final timeStr =
          '${_birthTime.hour.toString().padLeft(2, '0')}:${_birthTime.minute.toString().padLeft(2, '0')}';

      final profile = UserProfile(
        name: _nameController.text.trim(),
        birthDate: _birthDate,
        birthTime: timeStr,
        birthCity: _cityController.text.trim(),
        latitude: location.latitude,
        longitude: location.longitude,
      );

      await StorageService.saveProfile(profile);
      await NotificationService.scheduleDailyNotification();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(
          () => _cityError = 'Could not find city. Please check the name.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: List.generate(
                  4,
                  (i) => Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i <= _currentPage
                            ? const Color(0xFF7C4DFF)
                            : Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) =>
                    setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(),
                  _buildNamePage(),
                  _buildBirthDatePage(),
                  _buildCityPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '✦',
            style: TextStyle(fontSize: 64),
          ),
          const SizedBox(height: 24),
          const Text(
            'CosmicTransit',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your personalised daily transit reading,\npowered by real astrology data & AI.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          _buildButton('Begin', _nextPage),
        ],
      ),
    );
  }

  Widget _buildNamePage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'What\'s your name?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'Enter your name',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF7C4DFF)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Color(0xFF7C4DFF), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 48),
          _buildButton('Next', () {
            if (_nameController.text.trim().isNotEmpty) _nextPage();
          }),
        ],
      ),
    );
  }

  Widget _buildBirthDatePage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'When were you born?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          // Birth date
          GestureDetector(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _birthDate,
                firstDate: DateTime(1920),
                lastDate: DateTime.now(),
                builder: (context, child) => Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFF7C4DFF),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (date != null) setState(() => _birthDate = date);
            },
            child: _buildInfoTile(
              'Birth Date',
              DateFormat('MMMM d, yyyy').format(_birthDate),
            ),
          ),
          const SizedBox(height: 16),
          // Birth time
          GestureDetector(
            onTap: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: _birthTime,
                builder: (context, child) => Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFF7C4DFF),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (time != null) setState(() => _birthTime = time);
            },
            child: _buildInfoTile(
              'Birth Time',
              _birthTime.format(context),
            ),
          ),
          const SizedBox(height: 48),
          _buildButton('Next', _nextPage),
        ],
      ),
    );
  }

  Widget _buildCityPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Where were you born?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _cityController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'e.g. Singapore, London, Tokyo',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF7C4DFF)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Color(0xFF7C4DFF), width: 2),
              ),
              errorText: _cityError,
              errorStyle: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
          const SizedBox(height: 48),
          _isSubmitting
              ? const CircularProgressIndicator(color: Color(0xFF7C4DFF))
              : _buildButton('See My Stars', _submit),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C4DFF),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          elevation: 0,
        ),
        child: Text(text,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
