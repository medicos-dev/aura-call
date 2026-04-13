import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cached contact information
class CachedContact {
  final String callId;
  final String name;
  final String? avatarUrl;
  final DateTime? lastSeen;

  CachedContact({
    required this.callId,
    required this.name,
    this.avatarUrl,
    this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'name': name,
        'avatarUrl': avatarUrl,
        'lastSeen': lastSeen?.toIso8601String(),
      };

  factory CachedContact.fromJson(Map<String, dynamic> json) => CachedContact(
        callId: json['callId'] as String,
        name: json['name'] as String? ?? 'Unknown',
        avatarUrl: json['avatarUrl'] as String?,
        lastSeen: json['lastSeen'] != null
            ? DateTime.tryParse(json['lastSeen'] as String)
            : null,
      );
}

/// Service for instant hydrated contact display (Dummy Data Mode)
class ContactCacheService {
  static final ContactCacheService _instance = ContactCacheService._internal();
  factory ContactCacheService() => _instance;
  ContactCacheService._internal();

  static const String _cacheKey = 'contact_cache_v1';

  final Map<String, CachedContact> _cache = {};

  /// Get contact from cache (instant, synchronous)
  CachedContact? getContact(String callId) => _cache[callId];

  /// Get display name (returns "Aura Friend" if not found)
  String getDisplayName(String callId) {
    return _cache[callId]?.name ?? 'Aura Friend';
  }

  /// Get all cached contacts
  List<CachedContact> get allContacts => _cache.values.toList();

  /// Load cache from disk (call on app start)
  Future<void> loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_cacheKey);
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        for (final entry in decoded.entries) {
          _cache[entry.key] = CachedContact.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      } catch (_) {
        // Corrupted cache, ignore
      }
    }
  }

  /// Save cache to disk
  Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> toSave = {};
    for (final entry in _cache.entries) {
      toSave[entry.key] = entry.value.toJson();
    }
    await prefs.setString(_cacheKey, jsonEncode(toSave));
  }

  /// Refresh contacts with DUMMY DATA since backend is removed
  Future<List<String>> refreshContacts(String myCallId) async {
    // Generate dummy 3D avatars using DiceBear Adventurer API
    // Ensure we have some base mock friends
    final mockFriends = [
      CachedContact(callId: 'MOCK01', name: 'Alex Johnson', avatarUrl: 'https://api.dicebear.com/7.x/adventurer/png?seed=Alex'),
      CachedContact(callId: 'MOCK02', name: 'Sarah Connor', avatarUrl: 'https://api.dicebear.com/7.x/adventurer/png?seed=Sarah'),
      CachedContact(callId: 'MOCK03', name: 'Cyber Punk', avatarUrl: 'https://api.dicebear.com/7.x/adventurer/png?seed=Cyber'),
    ];

    for (var friend in mockFriends) {
      _cache[friend.callId] = friend;
    }

    await _saveToDisk();
    return _cache.keys.toList();
  }

  /// Add or update a single contact in cache
  void updateContact(String callId, {String? name, String? avatarUrl}) {
    final existing = _cache[callId];
    _cache[callId] = CachedContact(
      callId: callId,
      name: name ?? existing?.name ?? callId,
      avatarUrl: avatarUrl ?? existing?.avatarUrl,
      lastSeen: existing?.lastSeen,
    );
    _saveToDisk();
  }

  /// Lookup by call ID - for ping name resolution
  String resolveName(String callId) {
    return _cache[callId]?.name ?? 'Aura Friend';
  }
}
