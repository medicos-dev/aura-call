import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/background_handler.dart';
import '../services/call_service.dart';
import '../services/presence_service.dart';
import '../services/sound_service.dart';
import '../widgets/add_contact_sheet.dart';
import 'call_overlay.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  final TextEditingController _callIdController = TextEditingController();

  String _myCallId = '';
  String _userName = '';
  String _avatarUrl = '';
  List<String> _contactIds = [];
  List<String> _onlineUserIds = [];
  Map<String, String> _contactNames = {}; // Map Call ID -> Username
  bool _isLoading = true;

  late CallService _callService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _callService = CallService();
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = FlutterBackgroundService();
    service.invoke('app_lifecycle', {
      'state': state == AppLifecycleState.resumed ? 'resumed' : 'paused',
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callService.dispose();
    _callIdController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();

    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString('call_id') ?? '';
    final storedName = prefs.getString('user_name') ?? 'User';
    final storedAvatar = prefs.getString('user_avatar') ?? '';
    List<String> contacts = prefs.getStringList('contacts') ?? [];

    setState(() {
      _myCallId = storedId;
      _userName = storedName;
      _avatarUrl = storedAvatar;
      _contactIds = contacts;
      _isLoading = false;
    });

    // Sync contacts from cloud
    if (storedId.isNotEmpty) {
      _syncProfileIfNeeded(
        storedId,
        storedName,
        storedAvatar,
      ); // Self-heal profile
      await _syncContacts(storedId);
      _subscriptionContacts(); // Listen for new contacts (Bidirectional)
    }

    // Fetch names for contacts
    if (contacts.isNotEmpty) {
      await _fetchContactNames(contacts);
    }

    await _callService.initialize();

    final presence = PresenceService(
      supabase: _supabase,
      myCallId: _myCallId,
      onOnlineUsersUpdated: (ids) {
        setState(() => _onlineUserIds = ids);
      },
    );
    presence.connect();

    // Check for pending call answer from background
    final answeredFromBg = prefs.getBool('answered_from_background') ?? false;
    if (answeredFromBg) {
      await prefs.setBool('answered_from_background', false);
      final callerId = prefs.getString('pending_caller_id');

      if (callerId != null && callerId.isNotEmpty) {
        // Navigate immediately to connected call screen
        if (mounted) {
          Navigator.of(context).push(
            CupertinoPageRoute(
              builder:
                  (_) => CallOverlay(
                    callService: _callService,
                    remoteDisplayName: callerId,
                    isVideoCall:
                        true, // Default to video or check payload if possible
                    answeredFromBackground: true,
                  ),
            ),
          );
        }
      }
    }

    // Re-enable Background Service hook
    await initializeService();
    final service = FlutterBackgroundService();
    service.invoke("init", {"call_id": _myCallId});
  }

  Future<void> _addContact() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => AddContactSheet(
            onAdd: (inputValue) {
              if (inputValue.isNotEmpty &&
                  !_contactIds.contains(inputValue) &&
                  inputValue != _myCallId) {
                _saveContact(inputValue);
                _sendContactAddSignal(inputValue);
              }
            },
          ),
    );
    // Ensure focus is cleared on main context too, just in case
    if (mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Future<void> _saveContact(String newId) async {
    setState(() => _contactIds.add(newId));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('contacts', _contactIds);
    await _fetchContactNames([newId]);

    // Cloud sync
    try {
      await _supabase.from('contacts').upsert({
        'owner_id': _myCallId,
        'contact_id': newId,
      });
    } catch (e) {
      debugPrint('Error saving contact to cloud: $e');
    }
  }

  void _startCall(String targetId, bool video) async {
    SoundService.startOutgoingRing();
    final callType = video ? CallType.video : CallType.audio;

    bool success = await _callService.startCall(targetId, callType);

    if (success) {
      if (!mounted) return;

      SoundService.stopRing();
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder:
              (_) => CallOverlay(
                callService: _callService,
                remoteDisplayName: targetId,
                isVideoCall: video,
              ),
        ),
      );
    } else {
      SoundService.playError();
    }
  }

  Future<void> _sendPing(String targetId) async {
    // SoundService.playPing(); // Removed self-play as per user feedback
    await _supabase.from('signals').insert({
      'sender_id': _myCallId,
      'receiver_id': targetId,
      'type': 'ping',
      'status': 'active',
      'data': {'name': _userName},
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ping sent to $targetId'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: const Color(0xFF128C7E),
        ),
      );
    }
  }

  Future<void> _sendContactAddSignal(String targetId) async {
    await _supabase.from('signals').insert({
      'sender_id': _myCallId,
      'receiver_id': targetId,
      'type': 'contact_add',
      'data': {'name': _userName},
    });
  }

  Future<void> _syncContacts(String myId) async {
    try {
      final response = await _supabase
          .from('contacts')
          .select('contact_id')
          .eq('owner_id', myId);

      final cloudContacts =
          (response as List).map((e) => e['contact_id'] as String).toList();
      final localContacts = _contactIds;

      // Merge unique
      final allContacts = {...localContacts, ...cloudContacts}.toList();

      if (allContacts.length > localContacts.length) {
        setState(() => _contactIds = allContacts);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('contacts', allContacts);

        // Fetch names for new merged list
        await _fetchContactNames(allContacts);
      } else if (localContacts.isNotEmpty) {
        await _fetchContactNames(localContacts);
      }
    } catch (e) {
      debugPrint('Error syncing contacts: $e');
    }
  }

  Future<void> _fetchContactNames(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final response = await _supabase
          .from('profiles')
          .select('id, username')
          .inFilter('id', ids);

      final names = <String, String>{};
      for (final row in response) {
        names[row['id'] as String] = row['username'] as String? ?? 'Unknown';
      }

      if (mounted) {
        setState(() {
          _contactNames.addAll(names);
        });
      }
    } catch (e) {
      debugPrint('Error fetching contact names: $e');
    }
  }

  Future<void> _syncProfileIfNeeded(
    String id,
    String name,
    String avatar,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('need_profile_sync') ?? true) {
      try {
        await _supabase.from('profiles').upsert({
          'call_id': id,
          'username': name,
          'avatar_url': avatar,
          'last_seen': DateTime.now().toIso8601String(),
        }, onConflict: 'call_id');
        await prefs.setBool('need_profile_sync', false);
      } catch (e) {
        debugPrint('Retry profile sync failed: $e');
      }
    }
  }

  void _subscriptionContacts() {
    _supabase
        .channel('public:contacts')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'contacts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: _myCallId,
          ),
          callback: (payload) {
            // Reload contacts when someone (or background service) adds a contact for me
            _syncContacts(_myCallId);
          },
        )
        .subscribe();

    // Also listen for profile changes to update names in real-time
    _supabase
        .channel('public:profiles')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            // If a contact's name changed, refresh names
            // Optimistic update: check if ID is in our contacts
            final newRecord = payload.newRecord;
            if (newRecord != null &&
                _contactIds.contains(newRecord['call_id'])) {
              _fetchContactNames([newRecord['call_id']]);
            }
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: GestureDetector(
          onTap:
              () => Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => const ProfileScreen()),
              ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Greeting Chip - Samsung Now Bar style
              Container(
                padding: const EdgeInsets.only(
                  left: 4,
                  right: 16,
                  top: 4,
                  bottom: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage:
                          _avatarUrl.isNotEmpty
                              ? NetworkImage(_avatarUrl)
                              : null,
                      backgroundColor: const Color(0xFF128C7E),
                      child:
                          _avatarUrl.isEmpty
                              ? const Icon(
                                CupertinoIcons.person_fill,
                                size: 16,
                                color: Colors.white,
                              )
                              : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Hi, $_userName',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.search, color: Color(0xFF128C7E)),
            onPressed: () {},
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CupertinoActivityIndicator(radius: 20))
              : Column(
                children: [
                  // Return to Call Bar
                  AnimatedBuilder(
                    animation: _callService,
                    builder: (context, child) {
                      if (!_callService.isInCall) {
                        return const SizedBox.shrink();
                      }
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder:
                                  (_) => CallOverlay(
                                    callService: _callService,
                                    remoteDisplayName:
                                        _callService.participants.isNotEmpty
                                            ? _callService
                                                .participants
                                                .first
                                                .participantId
                                            : 'Unknown',
                                    isVideoCall:
                                        _callService.callType == CallType.video,
                                  ),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          color: const Color(0xFF128C7E),
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.phone_fill,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Tap to return to call',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                CupertinoIcons.chevron_right,
                                color: Colors.white,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  Expanded(
                    child:
                        _contactIds.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    CupertinoIcons.person_2,
                                    size: 64,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No contacts yet',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap + to add a friend',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _contactIds.length,
                              separatorBuilder:
                                  (_, __) => Divider(
                                    height: 1,
                                    indent: 88,
                                    color: Colors.grey.shade200,
                                  ),
                              itemBuilder: (context, index) {
                                final id = _contactIds[index];
                                final isOnline = _onlineUserIds.contains(id);
                                final name = _contactNames[id] ?? id;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundImage: NetworkImage(
                                          'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=random&size=128',
                                        ),
                                      ),
                                      if (isOnline)
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF25D366),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1C1C1E),
                                    ),
                                  ),
                                  subtitle: Text(
                                    id != name
                                        ? id
                                        : (isOnline ? 'Online' : 'Offline'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          CupertinoIcons.bell_fill,
                                          color: Colors.orange.shade400,
                                          size: 22,
                                        ),
                                        onPressed: () => _sendPing(id),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          CupertinoIcons.phone_fill,
                                          color: Color(0xFF128C7E),
                                          size: 22,
                                        ),
                                        onPressed: () => _startCall(id, false),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          CupertinoIcons.video_camera_solid,
                                          color: Color(0xFF128C7E),
                                          size: 22,
                                        ),
                                        onPressed: () => _startCall(id, true),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContact,
        backgroundColor: const Color(0xFF128C7E),
        shape: const CircleBorder(),
        child: const Icon(CupertinoIcons.add, color: Colors.white, size: 28),
      ),
    );
  }
}
