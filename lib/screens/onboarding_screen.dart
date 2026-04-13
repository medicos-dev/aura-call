import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'home_screen.dart';
import '../widgets/app_toast.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _nameController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _isLoading = false;
  String _selectedAvatarSeed = 'Aura';
  String _selectedAvatarStyle = 'adventurer'; // Option: micah, bottts, adventurer

  // All available DiceBear v9 styles
  static const List<String> _avatarStyles = [
    'identicon', 'fun-emoji', 'dylan', 'open-peeps', 
    'personas', 'notionists', 'thumbs',
  ];

  // Generate 15 mixed avatar entries with random seeds
  List<Map<String, String>> _avatarList = [];

  @override
  void initState() {
    super.initState();
    _generateAvatarList();
  }

  void _generateAvatarList() {
    final baseSeed = const Uuid().v4().substring(0, 6);
    _avatarList = List.generate(15, (i) {
      final style = _avatarStyles[i % _avatarStyles.length];
      final seed = '${baseSeed}_$i';
      return {
        'style': style,
        'seed': seed,
        'url': 'https://api.dicebear.com/9.x/$style/png?seed=$seed',
      };
    });
    // Set first avatar as default selection
    if (_selectedAvatarSeed == 'Aura') {
      _selectedAvatarStyle = _avatarList[0]['style']!;
      _selectedAvatarSeed = _avatarList[0]['seed']!;
    }
  }

  void _showAvatarPicker() {
    FocusManager.instance.primaryFocus?.unfocus();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          bottom: true,
          child: Container(
            height: 340,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                // Header row with title and refresh
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Choose Your Vibe', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      GestureDetector(
                        onTap: () {
                          _generateAvatarList();
                          setSheetState(() {});
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF128C7E).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.refresh, size: 16, color: Color(0xFF128C7E)),
                              SizedBox(width: 6),
                              Text('Refresh', style: TextStyle(color: Color(0xFF128C7E), fontWeight: FontWeight.w600, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Horizontally scrollable avatar grid
                SizedBox(
                  height: 200,
                  child: GridView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: _avatarList.length,
                    itemBuilder: (context, index) {
                      final avatar = _avatarList[index];
                      final isSelected = _selectedAvatarStyle == avatar['style'] && _selectedAvatarSeed == avatar['seed'];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedAvatarStyle = avatar['style']!;
                            _selectedAvatarSeed = avatar['seed']!;
                          });
                          Navigator.pop(sheetContext);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? const Color(0xFF128C7E) : Colors.grey.shade200,
                              width: isSelected ? 3 : 1.5,
                            ),
                            boxShadow: isSelected ? [
                              BoxShadow(
                                color: const Color(0xFF128C7E).withValues(alpha: 0.3),
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            ] : null,
                          ),
                          child: ClipOval(
                            child: Image.network(
                              avatar['url']!,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CupertinoActivityIndicator(color: Colors.grey.shade400),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey.shade100,
                                child: Icon(CupertinoIcons.person_fill, color: Colors.grey.shade400, size: 30),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _completeSetup() async {
    if (_nameController.text.trim().isEmpty) {
      AppToast.show(context, 'Please enter your name', type: AppToastType.error);
      return;
    }

    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final callId =
        prefs.getString('call_id') ??
        const Uuid().v4().substring(0, 6).toUpperCase();
    final name = _nameController.text.trim();
    final avatarUrl = 'https://api.dicebear.com/9.x/$_selectedAvatarStyle/png?seed=$_selectedAvatarSeed';

    await prefs.setString('call_id', callId);
    await prefs.setString('user_name', name);
    await prefs.setString('user_avatar', avatarUrl);
    await prefs.setBool('onboarding_complete', true);

    await _storage.write(key: 'call_id', value: callId);
    await _storage.write(key: 'user_name', value: name);
    await _storage.write(key: 'user_avatar', value: avatarUrl);

    // Backend sync removed (Dummy Data mode)
    await prefs.setBool('need_profile_sync', false);

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(CupertinoPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Avatar
              GestureDetector(
                onTap: _showAvatarPicker,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade100,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.transparent,
                        backgroundImage: NetworkImage('https://api.dicebear.com/9.x/$_selectedAvatarStyle/png?seed=$_selectedAvatarSeed'),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF128C7E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(CupertinoIcons.pencil, color: Colors.white, size: 20),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Welcome to AURA',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your name to get started',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 48),
              // Name Input
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: 'Your Name',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: Icon(
                      CupertinoIcons.person_fill,
                      color: Colors.grey.shade400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 3),
              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _completeSetup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF128C7E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child:
                      _isLoading
                          ? const CupertinoActivityIndicator(
                            color: Colors.white,
                          )
                          : const Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
