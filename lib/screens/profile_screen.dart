import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../widgets/app_toast.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = const FlutterSecureStorage();
  String _userName = '';
  String _callId = '';
  String _avatarUrl = '';
  String _bgOption = 'assets/call_background_1.png';

  String get _bgLabel {
    switch (_bgOption) {
      case 'assets/call_background_1.png': return 'Modern Aura';
      case 'assets/call_background_2.png': return 'Dark Neon';
      case 'assets/call_background_3.png': return 'Ocean Vibe';
      default: return 'Modern Aura';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'User';
      _callId = prefs.getString('call_id') ?? '';
      _avatarUrl = prefs.getString('user_avatar') ?? '';
      _bgOption = prefs.getString('call_background') ?? 'assets/call_background_1.png';
    });
  }

  // DiceBear v9 styles
  static const List<String> _avatarStyles = [
    'identicon', 'fun-emoji', 'dylan', 'open-peeps',
    'personas', 'notionists', 'thumbs',
  ];

  void _showAvatarPicker() {
    final baseSeed = const Uuid().v4().substring(0, 6);
    List<Map<String, String>> avatarList = List.generate(15, (i) {
      final style = _avatarStyles[i % _avatarStyles.length];
      final seed = '${baseSeed}_$i';
      return {
        'style': style,
        'seed': seed,
        'url': 'https://api.dicebear.com/9.x/$style/png?seed=$seed',
      };
    });

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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Change Avatar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      GestureDetector(
                        onTap: () {
                          final newSeed = const Uuid().v4().substring(0, 6);
                          avatarList = List.generate(15, (i) {
                            final style = _avatarStyles[i % _avatarStyles.length];
                            final seed = '${newSeed}_$i';
                            return {
                              'style': style,
                              'seed': seed,
                              'url': 'https://api.dicebear.com/9.x/$style/png?seed=$seed',
                            };
                          });
                          setSheetState(() {});
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
                    itemCount: avatarList.length,
                    itemBuilder: (context, index) {
                      final avatar = avatarList[index];
                      return GestureDetector(
                        onTap: () async {
                          final url = avatar['url']!;
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('user_avatar', url);
                          await _storage.write(key: 'user_avatar', value: url);
                          setState(() => _avatarUrl = url);
                          if (context.mounted) Navigator.pop(sheetContext);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade200, width: 1.5),
                          ),
                          child: ClipOval(
                            child: Image.network(
                              avatar['url']!,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(child: CupertinoActivityIndicator(color: Colors.grey.shade400));
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

  void _changeBackground() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              bottom: true,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('Background Selection',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                    _buildBgItem('assets/call_background_1.png', 'Modern Aura', setSheetState),
                    _buildBgItem('assets/call_background_2.png', 'Dark Neon', setSheetState),
                    _buildBgItem('assets/call_background_3.png', 'Ocean Vibe', setSheetState),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBgItem(String path, String label, StateSetter setSheetState) {
    final isSelected = _bgOption == path;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(path, width: 60, height: 60, fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 60, height: 60, color: Colors.grey.shade200,
            child: const Icon(CupertinoIcons.photo),
          ),
        ),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      trailing: isSelected ? const Icon(CupertinoIcons.checkmark_alt_circle_fill, color: Color(0xFF128C7E)) : null,
      onTap: () async {
        final nav = Navigator.of(context);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('call_background', path);
        setState(() => _bgOption = path);
        setSheetState(() {});
        nav.pop();
      },
    );
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _callId));
    AppToast.show(context, 'Code copied to clipboard', type: AppToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Color(0xFF128C7E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Color(0xFF1C1C1E),
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 32),
          // Avatar (tappable to change)
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundImage:
                        _avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) : null,
                    backgroundColor: const Color(0xFF128C7E),
                    child:
                        _avatarUrl.isEmpty
                            ? const Icon(
                              CupertinoIcons.person_fill,
                              size: 60,
                              color: Colors.white,
                            )
                            : null,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF128C7E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.pencil, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Name
          Text(
            _userName,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 48),
          // Code Section
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'YOUR AURA CODE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                // Fancy Code Display
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children:
                        _callId.split('').map((char) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 44,
                            height: 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFF128C7E), // Solid Teal
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF128C7E,
                                  ).withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                char,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
                // Copy Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(CupertinoIcons.doc_on_doc),
                    label: const Text('Copy Code'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF128C7E),
                      side: const BorderSide(color: Color(0xFF128C7E)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // App Settings Section
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              leading: const Icon(CupertinoIcons.photo, color: Color(0xFF128C7E)),
              title: const Text('Call Background'),
              subtitle: Text(_bgLabel),
              trailing: const Icon(CupertinoIcons.chevron_right),
              onTap: _changeBackground,
            ),
          ),
          const SizedBox(height: 24),
          // Info Text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Share this code with friends so they can add you on AURA',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }
}
