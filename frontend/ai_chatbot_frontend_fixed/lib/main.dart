import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:google_sign_in/google_sign_in.dart';
import 'api_service.dart';
import 'session_manager.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';





// ============================================================================
//  1. MAIN ENTRY POINT & CONFIGURATION
// ============================================================================

class Responsive {
  static double w(BuildContext context) => MediaQuery.of(context).size.width;
  static double h(BuildContext context) => MediaQuery.of(context).size.height;
  static bool isMobile(BuildContext context) => w(context) < 600;
  static bool isTablet(BuildContext context) => w(context) >= 600 && w(context) < 1024;
  static double textScale(BuildContext context) => isMobile(context) ? 1.15 : 1.0;
  static double fontSize(BuildContext context, double baseSize) => baseSize * textScale(context);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (only on platforms that support it)
  // On Windows, Firebase is not supported — skip silently.
  if (!kIsWeb && !Platform.isWindows) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // google-services.json placeholder still in place — Firebase will fail
      // until a real project is configured. App continues without Firebase.
      debugPrint('[Firebase] Initialization skipped: $e');
    }
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF050A18),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MavericksAIApp());
}

class MavericksAIApp extends StatelessWidget {
  const MavericksAIApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maveric AI',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      home: const AuthWrapper(),
    );
  }
}

// ============================================================================
//  2. THEME & DESIGN SYSTEM
// ============================================================================

class AppColors {
  // Primary gradient for "Mavericks AI" title - Rainbow gradient
  static const Color titleGradientCyan = Color(0xFF00D9FF);
  static const Color titleGradientGreen = Color(0xFF00E676);
  static const Color titleGradientPink = Color(0xFFFF00FF);
  static const Color titleGradientOrange = Color(0xFFFF9500);

  // Button/accent gradients
  static const Color primaryGradientStart = Color(0xFF4285F4);
  static const Color primaryGradientEnd = Color(0xFF550CC2);

  // Accent colors
  static const Color neonCyan = Color(0xFF00BCD4);
  static const Color neonGreen = Color(0xFF00E676);
  static const Color accentOrange = Color(0xFFFFAB40);
  static const Color accentRed = Color(0xFFFF5252);

  // Background colors
  static const Color deepSpace = Color(0xFF050A18);
  static const Color sidebarBackground = Color(0xFF0B1221);
  static const Color sidebarSurface = Color(0xFF1E293B);

  // Input box colors
  static const Color inputBackground = Color(0xFF1A2332);
  static const Color inputBorderColor = Colors.transparent;

  // Text colors
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Border colors
  static const Color borderLight = Color(0x1AFFFFFF);
  static const Color borderMedium = Color(0x33FFFFFF);

  // Other
  static const Color searchHighlight = Color(0xFFFFEB3B);
  static const Color logoutRed = Color(0xFFEF5350);
  static const Color googleRed = Color(0xFFDB4437);
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color disclaimerText = Color(0xFF64748B);

  // Image mode color
  static const Color imageModeActive = Color(0xFFE040FB);
}

class AppGradients {
  static const LinearGradient titleGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      AppColors.titleGradientCyan,
      AppColors.titleGradientGreen,
      AppColors.titleGradientPink,
      AppColors.titleGradientOrange,
    ],
  );

  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
  );

  static const LinearGradient glass = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x1AFFFFFF), Color(0x0DFFFFFF)],
  );
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.deepSpace,
      primaryColor: AppColors.primaryGradientStart,
      textTheme: GoogleFonts.robotoSlabTextTheme(ThemeData.dark().textTheme),
    );
  }
}

// ============================================================================
//  3. DATA MODELS
// ============================================================================

enum MessageType { user, bot, voice, system, image, file }
enum AttachmentType { image, file, camera }
enum AuthMode { signIn, signUp }

// InputMode enum for image generation toggle
enum InputMode { chat, image }

class ChatMessage {
  final String id;
  final String content;
  final MessageType type;
  final String sender;
  final DateTime timestamp;
  final bool isAnimating;
  final bool hasAnimated;
  final int? likeStatus;
  final String? voiceDuration;
  final bool isPlaying;
  final String? filePath;
  final String? fileName;
  final Uint8List? fileBytes;
  final String? imageUrl; // For generated images

  // Voice message fields (MessageType.voice)
  final String? transcript;   // speech-to-text result
  final int? audioSeconds;    // recording length in seconds

  ChatMessage({
    required this.id,
    required this.content,
    required this.type,
    this.sender = 'user',
    required this.timestamp,
    this.isAnimating = false,
    this.hasAnimated = true,
    this.likeStatus,
    this.voiceDuration,
    this.isPlaying = false,
    this.filePath,
    this.fileName,
    this.fileBytes,
    this.imageUrl,
    this.transcript,
    this.audioSeconds,
  });

  /// Convenience alias: for voice messages the recorded file lives in [filePath].
  String? get audioPath => type == MessageType.voice ? filePath : null;

  ChatMessage copyWith({bool? isAnimating, bool? hasAnimated, int? likeStatus, String? content, bool? isPlaying, String? imageUrl}) {
    return ChatMessage(
      id: id,
      content: content ?? this.content,
      type: type,
      sender: sender,
      timestamp: timestamp,
      isAnimating: isAnimating ?? this.isAnimating,
      hasAnimated: hasAnimated ?? this.hasAnimated,
      likeStatus: likeStatus ?? this.likeStatus,
      voiceDuration: voiceDuration,
      isPlaying: isPlaying ?? this.isPlaying,
      filePath: filePath,
      fileName: fileName,
      fileBytes: fileBytes,
      imageUrl: imageUrl ?? this.imageUrl,
      transcript: transcript,
      audioSeconds: audioSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'type': type.index,
    'sender': sender,
    'timestamp': timestamp.toIso8601String(),
    'isAnimating': isAnimating,
    'hasAnimated': hasAnimated,
    'likeStatus': likeStatus,
    'voiceDuration': voiceDuration,
    'filePath': filePath,
    'fileName': fileName,
    'fileBytes': fileBytes,
    'imageUrl': imageUrl,
    'transcript': transcript,
    'audioSeconds': audioSeconds,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    String determineSender() {
      if (json['sender'] != null) return json['sender'];
      final type = MessageType.values[json['type']];
      if (type == MessageType.bot || (type == MessageType.image && json['imageUrl'] != null)) {
        return 'bot';
      }
      return 'user';
    }

    return ChatMessage(
      id: json['id'],
      content: json['content'],
      type: MessageType.values[json['type']],
      sender: determineSender(),
      timestamp: DateTime.parse(json['timestamp']),
      isAnimating: json['isAnimating'] ?? false,
      hasAnimated: json['hasAnimated'] ?? true,
      likeStatus: json['likeStatus'],
      voiceDuration: json['voiceDuration'],
      filePath: json['filePath'],
      fileName: json['fileName'],
      fileBytes: json['fileBytes'],
      imageUrl: json['imageUrl'],
      transcript: json['transcript'],
      audioSeconds: json['audioSeconds'],
    );
  }
}

class ChatHistoryItem {
  final String id;
  final String title;
  final IconData icon;
  final DateTime createdAt;
  final DateTime lastUpdated;
  final List<ChatMessage> messages;
  final String preview;

  ChatHistoryItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.createdAt,
    required this.lastUpdated,
    required this.messages,
    required this.preview
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'icon': icon.codePoint,
    'createdAt': createdAt.toIso8601String(),
    'lastUpdated': lastUpdated.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'preview': preview
  };

  factory ChatHistoryItem.fromJson(Map<String, dynamic> json) => ChatHistoryItem(
      id: json['id'],
      title: json['title'],
      icon: IconData(json['icon'], fontFamily: 'MaterialIcons'),
      createdAt: DateTime.parse(json['createdAt']),
      lastUpdated: DateTime.parse(json['lastUpdated']),
      messages: (json['messages'] as List).map((m) => ChatMessage.fromJson(m)).toList(),
      preview: json['preview']
  );
}

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final DateTime createdAt;
  final bool isGoogleUser;
  final bool isGuest;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.createdAt,
    this.isGoogleUser = false,
    this.isGuest = false
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'avatarUrl': avatarUrl,
    'createdAt': createdAt.toIso8601String(),
    'isGoogleUser': isGoogleUser,
    'isGuest': isGuest
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      avatarUrl: json['avatarUrl'],
      createdAt: DateTime.parse(json['createdAt']),
      isGoogleUser: json['isGoogleUser'] ?? false,
      isGuest: json['isGuest'] ?? false
  );
}

// ============================================================================
//  3.1 ATTACHMENT DATA MODEL
// ============================================================================

class PendingAttachment {
  final AttachmentType type;
  final String filePath;
  final String fileName;
  final Uint8List? fileBytes;

  PendingAttachment({
    required this.type,
    required this.filePath,
    required this.fileName,
    this.fileBytes,
  });
}

// ============================================================================
//  4. STORAGE SERVICE
// ============================================================================

class ChatStorageService {
  static const String _searchHistoryKey = 'search_history';
  static const String _userProfileKey = 'user_profile';
  static const String _isLoggedInKey = 'is_logged_in';

  Future<String> _getHistoryKey() async {
    final isGuest = await SessionManager.getIsGuest();
    if (isGuest) return 'chat_history_guest';
    final userId = await SessionManager.getUserId();
    if (userId != null && userId > 0) return 'chat_history_$userId';
    return 'chat_history_guest';
  }

  static final ChatStorageService _instance = ChatStorageService._internal();
  factory ChatStorageService() => _instance;
  ChatStorageService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async { _prefs = await SharedPreferences.getInstance(); }

  Future<void> saveChatHistory(List<ChatHistoryItem> history) async {
    if (_prefs == null) await init();
    final key = await _getHistoryKey();
    await _prefs!.setString(key, jsonEncode(history.map((item) => item.toJson()).toList()));
  }

  Future<List<ChatHistoryItem>> loadChatHistory() async {
    if (_prefs == null) await init();

    final isGuest = await SessionManager.getIsGuest();
    final userId = await SessionManager.getUserId();

    // Guest migration logic
    if (!isGuest && userId != null && userId > 0) {
      final guestHistoryStr = _prefs!.getString('chat_history_guest');
      if (guestHistoryStr != null) {
        final userKey = 'chat_history_$userId';
        final userHistoryStr = _prefs!.getString(userKey);

        List<ChatHistoryItem> userHistory = [];
        if (userHistoryStr != null) {
          try {
            userHistory = (jsonDecode(userHistoryStr) as List).map((j) => ChatHistoryItem.fromJson(j)).toList();
          } catch (_) {}
        }

        List<ChatHistoryItem> guestHistory = [];
        try {
          guestHistory = (jsonDecode(guestHistoryStr) as List).map((j) => ChatHistoryItem.fromJson(j)).toList();
        } catch (_) {}

        if (guestHistory.isNotEmpty) {
          userHistory.addAll(guestHistory);
          final uniqueHistory = <String, ChatHistoryItem>{};
          for (var item in userHistory) uniqueHistory[item.id] = item;

          await _prefs!.setString(userKey, jsonEncode(uniqueHistory.values.map((item) => item.toJson()).toList()));

          final isGoogle = await SessionManager.getIsGoogleUser();
          if (!isGoogle) {
            for (var conv in guestHistory) {
              try {
                await ApiService.createConversation(id: conv.id, title: conv.title);
                final batch = <Map<String, dynamic>>[];
                for (var m in conv.messages) {
                  String typeStr = 'text';
                  if (m.type == MessageType.image) typeStr = 'image';
                  else if (m.type == MessageType.voice) typeStr = 'voice';
                  else if (m.type == MessageType.file) typeStr = 'file';
                  batch.add({
                    'id': m.id,
                    'sender': m.sender,
                    'content': m.content,
                    'type': typeStr,
                    'file_path': m.filePath,
                    'file_name': m.fileName,
                    'voice_duration': m.voiceDuration,
                    'image_url': m.imageUrl,
                    'like_status': m.likeStatus,
                  });
                }
                if (batch.isNotEmpty) {
                  await ApiService.batchSaveMessages(conv.id, batch);
                }
              } catch (_) {}
            }
          }

          await _prefs!.remove('chat_history_guest');
        }
      }
    }

    final key = await _getHistoryKey();
    List<ChatHistoryItem> localHistory = [];
    final jsonString = _prefs!.getString(key);
    if (jsonString != null) {
      try {
        localHistory = (jsonDecode(jsonString) as List).map((json) => ChatHistoryItem.fromJson(json)).toList();
      } catch (e) {
        localHistory = [];
      }
    }

    try {
      final backendConvs = await ApiService.fetchConversations();
      if (backendConvs.isNotEmpty) {
        final List<ChatHistoryItem> remoteHistory = [];
        for (var conv in backendConvs) {
          final id = conv["id"]?.toString() ?? "";
          if (id.isEmpty) continue;

          List<ChatMessage> messages = [];
          try {
            final details = await ApiService.fetchConversationDetails(id);
            if (details["messages"] != null) {
              messages = (details["messages"] as List).map((m) {
                MessageType mType = MessageType.user;
                final sender = m["sender"] ?? "user";
                final typeStr = m["type"] ?? "text";
                if (typeStr == "image") {
                  mType = MessageType.image;
                } else if (typeStr == "voice") {
                  mType = MessageType.voice;
                } else if (typeStr == "file") {
                  mType = MessageType.file;
                } else if (sender == "bot") {
                  mType = MessageType.bot;
                } else {
                  mType = MessageType.user;
                }

                return ChatMessage(
                  id: m["id"]?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  content: m["content"] ?? "",
                  type: mType,
                  sender: sender,
                  timestamp: m["timestamp"] != null ? DateTime.tryParse(m["timestamp"]) ?? DateTime.now() : DateTime.now(),
                  filePath: m["file_path"],
                  fileName: m["file_name"],
                  voiceDuration: m["voice_duration"],
                  imageUrl: m["image_url"],
                  likeStatus: m["like_status"],
                  hasAnimated: true,
                );
              }).toList();
            }
          } catch (_) {}

          final title = conv["title"] ?? "Conversation";
          final preview = conv["preview"] ?? "";
          final updatedAt = conv["updated_at"] != null ? DateTime.tryParse(conv["updated_at"]) ?? DateTime.now() : DateTime.now();

          remoteHistory.add(ChatHistoryItem(
            id: id,
            title: title,
            icon: Icons.chat_bubble_outline,
            createdAt: updatedAt,
            lastUpdated: updatedAt,
            messages: messages,
            preview: preview,
          ));
        }

        if (remoteHistory.isNotEmpty) {
          await saveChatHistory(remoteHistory);
          return remoteHistory;
        }
      }
    } catch (_) {}

    return localHistory;
  }

  Future<void> saveSearchHistory(List<String> searches) async {
    if (_prefs == null) await init();
    await _prefs!.setStringList(_searchHistoryKey, searches);
  }

  Future<List<String>> loadSearchHistory() async {
    if (_prefs == null) await init();
    return _prefs!.getStringList(_searchHistoryKey) ?? [];
  }

  Future<void> addSearchTerm(String term) async {
    if (term.trim().isEmpty) return;
    final searches = await loadSearchHistory();
    searches.remove(term);
    searches.insert(0, term);
    if (searches.length > 20) searches.removeLast();
    await saveSearchHistory(searches);
  }

  Future<void> clearSearchHistory() async {
    if (_prefs == null) await init();
    await _prefs!.remove(_searchHistoryKey);
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    if (_prefs == null) await init();
    await _prefs!.setString(_userProfileKey, jsonEncode(profile.toJson()));
  }

  Future<UserProfile?> loadUserProfile() async {
    if (_prefs == null) await init();
    final jsonString = _prefs!.getString(_userProfileKey);
    if (jsonString == null) return null;
    try { return UserProfile.fromJson(jsonDecode(jsonString)); }
    catch (e) { return null; }
  }

  Future<void> setLoggedIn(bool value) async {
    if (_prefs == null) await init();
    await _prefs!.setBool(_isLoggedInKey, value);
  }

  Future<bool> isLoggedIn() async {
    if (_prefs == null) await init();
    return _prefs!.getBool(_isLoggedInKey) ?? false;
  }

  Future<void> clearAllData() async {
    if (_prefs == null) await init();
    await _prefs!.clear();
  }
}

// ============================================================================
//  5. AUDIO RECORDING SERVICE
// ============================================================================

class AudioRecordingService {
  static final AudioRecordingService _instance = AudioRecordingService._internal();
  factory AudioRecordingService() => _instance;
  AudioRecordingService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  String? _currentRecordingPath;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentlyPlayingPath;

  // ── Live microphone amplitude (0.0 → 1.0), driven by the recorder itself.
  final StreamController<double> _amplitudeController =
  StreamController<double>.broadcast();
  final StreamController<int> _elapsedController =
  StreamController<int>.broadcast();
  StreamSubscription<Amplitude>? _amplitudeSub;

  /// Real microphone level, normalised to 0..1. Never random.
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// Elapsed recording seconds, emitted once per second.
  Stream<int> get elapsedStream => _elapsedController.stream;

  bool get isRecording => _isRecording;
  int get recordingSeconds => _recordingSeconds;

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Maps the recorder's dBFS reading onto a usable 0..1 range.
  static double _normalize(double dbfs) {
    if (dbfs.isNaN || dbfs.isInfinite) return 0.0;
    const double floor = -45.0; // treat anything quieter as silence
    final double v = ((dbfs - floor) / -floor).clamp(0.0, 1.0);
    // Slight curve so normal speech occupies the middle of the range.
    return math.pow(v, 0.7).toDouble();
  }

  Future<String?> startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _currentRecordingPath = '${directory.path}/voice_$timestamp.m4a';

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _currentRecordingPath!,
        );

        _isRecording = true;
        _recordingSeconds = 0;

        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _recordingSeconds++;
          if (!_elapsedController.isClosed) _elapsedController.add(_recordingSeconds);
        });

        // Real amplitude callbacks from the `record` package.
        _amplitudeSub?.cancel();
        _amplitudeSub = _recorder
            .onAmplitudeChanged(const Duration(milliseconds: 60))
            .listen((amp) {
          if (!_amplitudeController.isClosed) {
            _amplitudeController.add(_normalize(amp.current));
          }
        }, onError: (_) {});

        return _currentRecordingPath;
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
    return null;
  }

  Future<RecordingResult?> stopRecording() async {
    try {
      _recordingTimer?.cancel();
      await _amplitudeSub?.cancel();
      _amplitudeSub = null;
      if (!_amplitudeController.isClosed) _amplitudeController.add(0.0);

      final path = await _recorder.stop();
      _isRecording = false;

      if (path != null) {
        final duration = _formatDuration(_recordingSeconds);
        return RecordingResult(
          path: path,
          duration: duration,
          seconds: _recordingSeconds,
        );
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
    return null;
  }

  void cancelRecording() {
    _recordingTimer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    if (!_amplitudeController.isClosed) _amplitudeController.add(0.0);
    _recorder.stop();
    _isRecording = false;
    _recordingSeconds = 0;

    if (_currentRecordingPath != null) {
      final file = File(_currentRecordingPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  Future<void> playRecording(String path, {Function()? onComplete}) async {
    try {
      if (_isPlaying && _currentlyPlayingPath == path) {
        await _audioPlayer.stop();
        _isPlaying = false;
        _currentlyPlayingPath = null;
        return;
      }

      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(path));
      _isPlaying = true;
      _currentlyPlayingPath = path;

      _audioPlayer.onPlayerComplete.listen((event) {
        _isPlaying = false;
        _currentlyPlayingPath = null;
        onComplete?.call();
      });
    } catch (e) {
      debugPrint('Error playing recording: $e');
    }
  }

  Future<void> stopPlayback() async {
    await _audioPlayer.stop();
    _isPlaying = false;
    _currentlyPlayingPath = null;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _recordingTimer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeController.close();
    _elapsedController.close();
    _recorder.dispose();
    _audioPlayer.dispose();
  }

}

class RecordingResult {
  final String path;
  final String duration;
  final int seconds;

  RecordingResult({
    required this.path,
    required this.duration,
    required this.seconds,
  });
}

// ============================================================================
//  6. AUTH WRAPPER
// ============================================================================

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  /// FIXED BUG-16: Use SessionManager (single source of truth) for login state,
  /// not the legacy ChatStorageService which had a separate is_logged_in key.
  Future<void> _checkLoginStatus() async {
    final isLoggedIn = await SessionManager.isLoggedIn();
    if (mounted) setState(() { _isLoggedIn = isLoggedIn; _isLoading = false; });
  }

  void _onLoginSuccess() {
    if (mounted) setState(() => _isLoggedIn = true);
  }

  /// FIXED BUG-02: Clears only auth state, preserving chat cache.
  /// Also signs out of Google if user was a Google user.
  void _onLogout() async {
    final wasGoogleUser = await SessionManager.getIsGoogleUser();
    if (wasGoogleUser) {
      try { await GoogleSignIn().signOut(); } catch (_) {}
    }
    await SessionManager.clearAuthState();
    if (mounted) setState(() => _isLoggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          backgroundColor: AppColors.deepSpace,
          body: Center(child: CircularProgressIndicator(color: AppColors.primaryGradientStart))
      );
    }
    if (_isLoggedIn) return ChatScreen(onLogout: _onLogout);
    return AuthScreen(onLoginSuccess: _onLoginSuccess);
  }
}

// ============================================================================
//  7. AUTH SCREEN (WITH GUEST MODE & FORGET PASSWORD)
// ============================================================================

class AuthScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const AuthScreen({super.key, required this.onLoginSuccess});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  AuthMode _authMode = AuthMode.signIn;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  late AnimationController _backgroundController;
  late AnimationController _formController;
  late Animation<double> _formAnimation;
  Offset _cursorPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _formController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _formAnimation = CurvedAnimation(parent: _formController, curve: Curves.easeOutBack);
    _formController.forward();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _formController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _toggleAuthMode() {
    setState(() {
      _authMode = _authMode == AuthMode.signIn ? AuthMode.signUp : AuthMode.signIn;
    });
    _formController.reset();
    _formController.forward();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final sessionId = await SessionManager.getSessionId();
      Map<String, dynamic> res;

      if (_authMode == AuthMode.signUp) {
        res = await ApiService.register(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          sessionId: sessionId,
        );
      } else {
        res = await ApiService.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          sessionId: sessionId,
        );
      }

      final profile = UserProfile(
        id: res["user_id"]?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: res["name"] ?? (_authMode == AuthMode.signUp ? _nameController.text : _emailController.text.split('@').first),
        email: res["email"] ?? _emailController.text,
        createdAt: DateTime.now(),
        isGoogleUser: false,
        isGuest: false,
      );
      await ChatStorageService().saveUserProfile(profile);
      await ChatStorageService().setLoggedIn(true);
      setState(() => _isLoading = false);
      widget.onLoginSuccess();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    // Windows does not support Firebase Auth — show informative message.
    if (!kIsWeb && Platform.isWindows) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Sign-In is not supported on Windows. Please use email/password login.'),
            backgroundColor: AppColors.accentRed,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Trigger the Google Sign-In flow via the google_sign_in package.
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in dialog
        setState(() => _isLoading = false);
        return;
      }

      // 3. Send Google profile data to our backend to create/link the account.
      final sessionId = await SessionManager.getSessionId();
      final res = await ApiService.googleAuth(
        googleId: googleUser.id,
        email: googleUser.email,
        name: googleUser.displayName ?? googleUser.email,
        profilePhoto: googleUser.photoUrl,
        sessionId: sessionId,
      );

      // 5. Persist auth state via SessionManager.
      await SessionManager.saveUserProfile(
        userId: (res['user_id'] is int) ? res['user_id'] : int.parse(res['user_id'].toString()),
        name: res['name'] ?? googleUser.displayName ?? '',
        email: res['email'] ?? googleUser.email,
        profilePhoto: res['profile_photo'] ?? googleUser.photoUrl,
        isGoogleUser: true,
      );
      await SessionManager.setLoggedIn(true);

      setState(() => _isLoading = false);
      widget.onLoginSuccess();
    } on PlatformException catch (e) {
      setState(() => _isLoading = false);
      String message = e.message ?? 'Google Sign-In failed';
      if (e.code == 'sign_in_canceled') message = 'Sign-in was cancelled';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.accentRed),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _handleGuestLogin() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    await SessionManager.saveUserProfile(
      userId: -1, // Guests have no backend user ID
      name: 'Guest User',
      email: 'guest@maveric.ai',
      isGoogleUser: false,
      isGuest: true,
    );
    await SessionManager.setLoggedIn(true);
    setState(() => _isLoading = false);
    widget.onLoginSuccess();
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ForgotPasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: MouseRegion(
        onHover: (event) { setState(() => _cursorPosition = event.localPosition); },
        child: GestureDetector(
          onPanUpdate: (details) { setState(() => _cursorPosition = details.localPosition); },
          child: Stack(
            children: [
              Positioned.fill(child: CursorFollowingBackground(cursorPosition: _cursorPosition, animationController: _backgroundController)),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ScaleTransition(
                      scale: _formAnimation,
                      child: FadeTransition(
                        opacity: _formAnimation,
                        child: Container(
                          width: Responsive.isMobile(context) ? double.infinity : 400,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: AppColors.sidebarBackground.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.borderLight),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))],
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ShaderMask(
                                  shaderCallback: (bounds) => AppGradients.titleGradient.createShader(bounds),
                                  child: Text(
                                    'Maveric AI',
                                    style: GoogleFonts.fredoka(fontSize: Responsive.fontSize(context, 28), fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _authMode == AuthMode.signIn ? 'Welcome back!' : 'Create your account',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: Responsive.fontSize(context, 14)),
                                ),
                                const SizedBox(height: 32),
                                if (_authMode == AuthMode.signUp) ...[
                                  _buildTextField(
                                    controller: _nameController,
                                    label: 'Full Name',
                                    icon: Icons.person_outline,
                                    validator: (v) => v == null || v.isEmpty ? 'Please enter your name' : null,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                _buildTextField(
                                  controller: _emailController,
                                  label: 'Email',
                                  icon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Please enter your email';
                                    if (!v.contains('@')) return 'Please enter a valid email';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  icon: Icons.lock_outline,
                                  obscureText: _obscurePassword,
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Please enter your password';
                                    if (v.length < 6) return 'Password must be at least 6 characters';
                                    return null;
                                  },
                                ),
                                if (_authMode == AuthMode.signUp) ...[
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _confirmPasswordController,
                                    label: 'Confirm Password',
                                    icon: Icons.lock_outline,
                                    obscureText: _obscureConfirmPassword,
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted),
                                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                    ),
                                    validator: (v) {
                                      if (v != _passwordController.text) return 'Passwords do not match';
                                      return null;
                                    },
                                  ),
                                ],
                                if (_authMode == AuthMode.signIn) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: GestureDetector(
                                      onTap: _showForgotPasswordDialog,
                                      child: Text(
                                        'Forgot Password?',
                                        style: TextStyle(
                                          color: AppColors.primaryGradientStart,
                                          fontSize: Responsive.fontSize(context, 13),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleSubmit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryGradientStart,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : Text(_authMode == AuthMode.signIn ? 'Sign In' : 'Sign Up', style: TextStyle(fontSize: Responsive.fontSize(context, 16), fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Expanded(child: Divider(color: AppColors.borderMedium)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Text('or', style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 13))),
                                    ),
                                    const Expanded(child: Divider(color: AppColors.borderMedium)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: AppColors.borderMedium),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Image.asset(
                                          'assets/google.png',
                                          width: 24,
                                          height: 24,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Icon(Icons.g_mobiledata, color: AppColors.googleRed, size: 24);
                                          },
                                        ),
                                        const SizedBox(width: 12),
                                        Text('Continue with Google', style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: _isLoading ? null : _handleGuestLogin,
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      foregroundColor: AppColors.textSecondary,
                                    ),
                                    child: Text('Continue as Guest', style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                GestureDetector(
                                  onTap: _toggleAuthMode,
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(fontSize: Responsive.fontSize(context, 14)),
                                      children: [
                                        TextSpan(text: _authMode == AuthMode.signIn ? "Don't have an account? " : "Already have an account? ", style: const TextStyle(color: AppColors.textSecondary)),
                                        TextSpan(text: _authMode == AuthMode.signIn ? 'Sign Up' : 'Sign In', style: const TextStyle(color: AppColors.primaryGradientStart, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 15)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.quicksand(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.sidebarSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primaryGradientStart)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accentRed)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accentRed)),
      ),
    );
  }
}

// ============================================================================
//  7.1 FORGOT PASSWORD DIALOG
// ============================================================================

class ForgotPasswordDialog extends StatefulWidget {
  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  int _currentStep = 0;
  final _emailController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _resetToken; // FIXED: stores the signed reset_token from verify-otp response

  @override
  void dispose() {
    _emailController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_emailController.text.isEmpty || !_emailController.text.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ApiService.requestForgotPasswordOtp(_emailController.text.trim());
      setState(() {
        _isLoading = false;
        _currentStep = 1;
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        _focusNodes[0].requestFocus();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll("Exception: ", "");
      });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter complete OTP');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // FIXED: Save the reset_token returned by the server — required to call resetPassword.
      final response = await ApiService.verifyForgotPasswordOtp(_emailController.text.trim(), otp);
      _resetToken = response['reset_token'] as String?;
      setState(() {
        _isLoading = false;
        _currentStep = 2;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_newPasswordController.text.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }
    // FIXED: Ensure we have the reset_token before attempting reset.
    if (_resetToken == null || _resetToken!.isEmpty) {
      setState(() => _errorMessage = 'Session expired. Please request a new OTP.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // FIXED: Pass reset_token (signed JWT) instead of email — matches new backend API.
      await ApiService.resetPassword(
        resetToken: _resetToken!,
        newPassword: _newPasswordController.text,
      );
      setState(() => _isLoading = false);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.neonGreen, size: 20),
                const SizedBox(width: 12),
                Text('Password reset successfully!', style: GoogleFonts.quicksand(color: Colors.white)),
              ],
            ),
            backgroundColor: AppColors.sidebarSurface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebarBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: Responsive.isMobile(context) ? Responsive.w(context) * 0.9 : 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _currentStep == 0 ? 'Forgot Password' :
                  _currentStep == 1 ? 'Verify OTP' : 'Reset Password',
                  style: GoogleFonts.fredoka(color: Colors.white, fontSize: Responsive.fontSize(context, 22)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _currentStep == 0 ? 'Enter your email to receive OTP' :
              _currentStep == 1 ? 'Enter the 6-digit code sent to your email' :
              'Create your new password',
              style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 13)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accentRed.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.accentRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: AppColors.accentRed, fontSize: Responsive.fontSize(context, 13)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_currentStep == 0) ...[
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 15)),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: GoogleFonts.quicksand(color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textMuted, size: 20),
                  filled: true,
                  fillColor: AppColors.sidebarSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primaryGradientStart)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGradientStart,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Send OTP', style: TextStyle(fontSize: Responsive.fontSize(context, 16), fontWeight: FontWeight.bold)),
                ),
              ),
            ],

            if (_currentStep == 1) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 45,
                    child: TextFormField(
                      controller: _otpControllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 20), fontWeight: FontWeight.bold),
                      onChanged: (value) => _onOtpChanged(index, value),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.sidebarSurface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGradientStart, width: 2)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading ? null : () {
                  for (var controller in _otpControllers) {
                    controller.clear();
                  }
                  _sendOtp();
                },
                child: Text('Resend OTP', style: TextStyle(color: AppColors.primaryGradientStart, fontSize: Responsive.fontSize(context, 14))),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGradientStart,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Verify OTP', style: TextStyle(fontSize: Responsive.fontSize(context, 16), fontWeight: FontWeight.bold)),
                ),
              ),
            ],

            if (_currentStep == 2) ...[
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 15)),
                decoration: InputDecoration(
                  labelText: 'New Password',
                  labelStyle: GoogleFonts.quicksand(color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNewPassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted),
                    onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                  ),
                  filled: true,
                  fillColor: AppColors.sidebarSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primaryGradientStart)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 15)),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: GoogleFonts.quicksand(color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  filled: true,
                  fillColor: AppColors.sidebarSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primaryGradientStart)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _resetPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGradientStart,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Reset Password', style: TextStyle(fontSize: Responsive.fontSize(context, 16), fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  8. CURSOR FOLLOWING BACKGROUND
// ============================================================================

class CursorFollowingBackground extends StatelessWidget {
  final Offset cursorPosition;
  final AnimationController animationController;

  const CursorFollowingBackground({super.key, required this.cursorPosition, required this.animationController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animationController,
      builder: (context, child) {
        return CustomPaint(
          painter: _BackgroundPainter(cursorPosition: cursorPosition, animationValue: animationController.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final Offset cursorPosition;
  final double animationValue;

  _BackgroundPainter({required this.cursorPosition, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.deepSpace,
    );

    final orbs = [
      _Orb(
        center: Offset(size.width * 0.2, size.height * 0.3),
        radius: 200,
        color: AppColors.primaryGradientStart.withOpacity(0.15),
        phase: 0,
      ),
      _Orb(
        center: Offset(size.width * 0.8, size.height * 0.7),
        radius: 250,
        color: AppColors.primaryGradientEnd.withOpacity(0.12),
        phase: 0.5,
      ),
      _Orb(
        center: Offset(size.width * 0.5, size.height * 0.5),
        radius: 180,
        color: AppColors.neonCyan.withOpacity(0.08),
        phase: 0.25,
      ),
    ];

    for (final orb in orbs) {
      final animatedCenter = Offset(
        orb.center.dx + math.sin((animationValue + orb.phase) * 2 * math.pi) * 30,
        orb.center.dy + math.cos((animationValue + orb.phase) * 2 * math.pi) * 20,
      );

      final gradient = ui.Gradient.radial(
        animatedCenter,
        orb.radius,
        [orb.color, orb.color.withOpacity(0)],
      );

      canvas.drawCircle(
        animatedCenter,
        orb.radius,
        Paint()..shader = gradient,
      );
    }

    if (cursorPosition != Offset.zero) {
      final cursorGradient = ui.Gradient.radial(
        cursorPosition,
        150,
        [
          AppColors.primaryGradientStart.withOpacity(0.15),
          AppColors.primaryGradientStart.withOpacity(0),
        ],
      );
      canvas.drawCircle(
        cursorPosition,
        150,
        Paint()..shader = cursorGradient,
      );
    }

    final starRandom = math.Random(42);
    for (int i = 0; i < 40; i++) {
      final x = starRandom.nextDouble() * size.width;
      final y = starRandom.nextDouble() * size.height;
      final starSize = starRandom.nextDouble() * 1.5 + 0.5;
      final twinkle = (math.sin((animationValue * 0.5 + i * 0.1) * 2 * math.pi) + 1) / 2;
      final opacity = 0.3 + twinkle * 0.4;

      canvas.drawCircle(
        Offset(x, y),
        starSize,
        Paint()..color = Colors.white.withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) {
    return oldDelegate.cursorPosition != cursorPosition ||
        oldDelegate.animationValue != animationValue;
  }
}

class _Orb {
  final Offset center;
  final double radius;
  final Color color;
  final double phase;

  _Orb({
    required this.center,
    required this.radius,
    required this.color,
    required this.phase,
  });
}

// ============================================================================
//  9. CHAT SCREEN
// ============================================================================

class ChatScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ChatScreen({super.key, required this.onLogout});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecordingService _audioService = AudioRecordingService();
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _spokenText = "";

  List<ChatMessage> _messages = [];
  List<ChatHistoryItem> _chatHistory = [];
  List<String> _searchHistory = [];
  UserProfile? _userProfile;

  bool _hasStartedChat = false;
  bool _isBotTyping = false;
  bool _isGenerating = false;
  bool _isSidebarOpen = false;
  bool _showAttachmentMenu = false;
  bool _showLogoutMenu = false;
  bool _isRecording = false;
  bool _isImageMode = false;

  String? _currentChatId;
  String _searchQuery = '';
  Offset _cursorPosition = Offset.zero;

  Timer? _generationTimer;
  Timer? _recordingDisplayTimer;
  int _recordingDisplaySeconds = 0;

  // ── Advanced Voice Mode state ────────────────────────────────────────────
  // ValueNotifiers keep the per-frame / per-second voice UI updates inside the
  // voice panel itself, so the whole chat page never rebuilds while recording.
  bool _isVoiceMode = false;
  final ValueNotifier<int> _voiceElapsed = ValueNotifier<int>(0);
  final ValueNotifier<String> _voiceTranscript = ValueNotifier<String>('');
  StreamSubscription<int>? _voiceElapsedSub;

  PendingAttachment? _pendingAttachment;

  // NEW: InputMode for image generation toggle
  InputMode _inputMode = InputMode.chat;

  late AnimationController _backgroundController;
  late AnimationController _titleController;
  // ignore: unused_field
  late Animation<double> _titleAnimation;
  late AnimationController _logoutMenuController;
  late Animation<double> _logoutMenuScale;

  // ignore: unused_field
  final List<String> _botResponses = [
    "That's a fascinating question! Let me share my thoughts on this...",
    "I understand your perspective. Here's what I think could help...",
    "Great point! Based on my analysis, I'd suggest the following approach...",
    "Interesting! Let me break this down for you step by step...",
    "I appreciate your curiosity. Here's a comprehensive overview...",
    "That's a complex topic. Let me explain it in simpler terms...",
    "Excellent question! Here are some key insights to consider...",
    "I see where you're coming from. Let me offer some guidance...",
  ];

  final List<IconData> _chatIcons = [
    Icons.chat_bubble_outline,
    Icons.psychology_outlined,
    Icons.lightbulb_outline,
    Icons.science_outlined,
    Icons.code_outlined,
    Icons.calculate_outlined,
    Icons.translate_outlined,
    Icons.school_outlined
  ];

  final List<String> _taglines = [
    "AI is like Electricity, available everywhere soon",
  ];

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadData();
    _speech = stt.SpeechToText();
    _textController.addListener(() {
      setState(() {});
    });
  }

  void _initAnimations() {
    _backgroundController = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _titleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _titleAnimation = CurvedAnimation(parent: _titleController, curve: Curves.easeOutBack);
    _logoutMenuController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _logoutMenuScale = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _logoutMenuController, curve: Curves.easeOutBack));
  }

  Future<void> _loadData() async {
    _chatHistory = await ChatStorageService().loadChatHistory();
    _searchHistory = await ChatStorageService().loadSearchHistory();

    // FIXED BUG-16: Load profile from SessionManager (single source of truth).
    final name = await SessionManager.getUserName();
    final email = await SessionManager.getUserEmail();
    final userId = await SessionManager.getUserId();
    final photo = await SessionManager.getProfilePhoto();
    final isGoogle = await SessionManager.getIsGoogleUser();
    final isGuest = await SessionManager.getIsGuest();

    if (name != null && email != null) {
      _userProfile = UserProfile(
        id: userId?.toString() ?? 'unknown',
        name: name,
        email: email,
        avatarUrl: photo,
        createdAt: DateTime.now(),
        isGoogleUser: isGoogle,
        isGuest: isGuest,
      );
    } else {
      // Fallback to legacy storage
      _userProfile = await ChatStorageService().loadUserProfile();
    }

    if (mounted) setState(() {});
  }

  // ignore: unused_element
  Future<void> _startVoiceInput() async {
    final available = await _speech.initialize();

    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Speech not available")),
      );
      return;
    }

    setState(() => _isListening = true);

    await _speech.listen(
      onResult: (result) async {
        if (result.finalResult) {
          final text = result.recognizedWords;

          _speech.stop();
          setState(() => _isListening = false);

          if (text.trim().isNotEmpty) {
            // 🔥 SAME FLOW AS NORMAL CHAT
            _addUserMessage(text);
          }
        }
      },
    );
  }

  // ── ADVANCED VOICE MODE ──────────────────────────────────────────────────
  // Tap mic  → the input morphs into a floating voice panel (blurred backdrop,
  //            glowing mic, live waveform driven by the REAL mic amplitude,
  //            timer and live transcript).
  // Tap stop → recording stops, the audio file is preserved, speech is turned
  //            into text and BOTH are sent through the existing chat pipeline.
  Future<void> _startVoiceMode() async {
    if (_isGenerating || _isVoiceMode) return;

    // 1️⃣ Mic permission (unchanged behaviour)
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Microphone permission denied")),
      );
      return;
    }

    // 2️⃣ Speech engine (best effort – recording still works without it)
    final speechAvailable = await _speech.initialize(
      onStatus: (s) => debugPrint("🎙️ Speech status: $s"),
      onError: (e) => debugPrint("❌ Speech error: $e"),
    );

    // 3️⃣ Start the real recorder – this is what feeds the live waveform.
    final path = await _audioService.startRecording();
    if (path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not start recording")),
      );
      return;
    }

    _voiceTranscript.value = "";
    _voiceElapsed.value = 0;
    _recordingDisplaySeconds = 0;
    _spokenText = "";

    _voiceElapsedSub?.cancel();
    _voiceElapsedSub = _audioService.elapsedStream.listen((seconds) {
      _recordingDisplaySeconds = seconds;
      _voiceElapsed.value = seconds; // only the panel rebuilds
    });

    if (speechAvailable) {
      _speech.listen(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onResult: (result) {
          _spokenText = result.recognizedWords;
          _voiceTranscript.value = result.recognizedWords; // panel-only rebuild
        },
      );
    }

    setState(() {
      _isVoiceMode = true;
      _isListening = speechAvailable;
    });
  }

  Future<void> _stopVoiceMode({bool cancel = false}) async {
    if (!_isVoiceMode) return;

    await _voiceElapsedSub?.cancel();
    _voiceElapsedSub = null;
    try {
      await _speech.stop();
    } catch (_) {}

    final deviceTranscript = _voiceTranscript.value.trim();

    if (cancel) {
      _audioService.cancelRecording();
      _voiceTranscript.value = "";
      _voiceElapsed.value = 0;
      if (mounted) {
        setState(() {
          _isVoiceMode = false;
          _isListening = false;
        });
      }
      return;
    }

    final result = await _audioService.stopRecording();

    if (mounted) {
      setState(() {
        _isVoiceMode = false;
        _isListening = false;
      });
    }

    _voiceTranscript.value = "";
    _voiceElapsed.value = 0;

    if (result == null) return;

    // Speech → text. On-device result first; existing backend endpoint as a
    // fallback so a message is never lost.
    String transcript = deviceTranscript;
    if (transcript.isEmpty) {
      try {
        final res = await ApiService.transcribeAudio(result.path);
        transcript = (res['text'] ?? res['transcript'] ?? '').toString().trim();
      } catch (e) {
        debugPrint('Transcription fallback failed: $e');
      }
    }
    if (transcript.isEmpty) transcript = 'Voice message';

    // Sends the transcript (for AI understanding) AND keeps/uploads the
    // original audio file (for playback) through the existing pipeline.
    _handleVoiceSend(
      result.duration,
      result.path,
      transcript: transcript,
      seconds: result.seconds,
    );
  }

  /// Entry point used by the mic button – toggles the immersive voice panel.
  Future<void> _toggleVoiceInput() async {
    if (_isVoiceMode) {
      await _stopVoiceMode();
    } else {
      await _startVoiceMode();
    }
  }

  @override
  void dispose() {
    _generationTimer?.cancel();
    _recordingDisplayTimer?.cancel();
    _voiceElapsedSub?.cancel();
    _voiceElapsed.dispose();
    _voiceTranscript.dispose();
    _backgroundController.dispose();
    _titleController.dispose();
    _logoutMenuController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    // The recorder is a singleton shared with the rest of the app: release the
    // active session instead of destroying the platform recorder.
    if (_audioService.isRecording) _audioService.cancelRecording();
    _audioService.stopPlayback();
    super.dispose();
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
      if (_isSidebarOpen) _showAttachmentMenu = false;
    });
  }

  void _closeSidebar() {
    if (_isSidebarOpen) setState(() => _isSidebarOpen = false);
    if (_showAttachmentMenu) setState(() => _showAttachmentMenu = false);
    if (_showLogoutMenu) _hideLogoutMenu();
  }

  void _toggleLogoutMenu() {
    setState(() {
      _showLogoutMenu = !_showLogoutMenu;
      if (_showLogoutMenu) _logoutMenuController.forward();
      else _logoutMenuController.reverse();
    });
  }

  void _hideLogoutMenu() {
    if (_showLogoutMenu) {
      _logoutMenuController.reverse();
      setState(() => _showLogoutMenu = false);
    }
  }

  void _handleLogout() {
    _hideLogoutMenu();
    showDialog(
        context: context,
        builder: (context) => LogoutConfirmationDialog(
            onConfirm: () async {
              Navigator.pop(context);
              // FIXED BUG-02: clearAuthState() preserves local chat history.
              // Calling clearAllData() was wiping all conversations.
              await SessionManager.clearAuthState();
              widget.onLogout();
            }
        )
    );
  }

  // Toggle image generation mode
  void _toggleImageMode() {
    setState(() {
      _inputMode = _inputMode == InputMode.chat ? InputMode.image : InputMode.chat;
    });
  }

  void _handleSendMessage(String text) {
    if (_isGenerating) return;

    // Handle pending attachment with optional text
    if (_pendingAttachment != null) {
      final attachment = _pendingAttachment!;
      final messageContent = text.trim().isEmpty
          ? attachment.fileName
          : '${attachment.fileName}\n${text.trim()}';

      MessageType messageType;
      if (attachment.type == AttachmentType.image || attachment.type == AttachmentType.camera) {
        messageType = MessageType.image;
      } else {
        messageType = MessageType.file;
      }

      _textController.clear();
      setState(() => _pendingAttachment = null);
      _addUserMessage(
          messageContent,
          type: messageType,
          filePath: attachment.filePath,
          fileName: attachment.fileName,
          fileBytes: attachment.fileBytes,
      );
      return;
    }

    if (text.trim().isEmpty) return;
    _textController.clear();

    // Route message based on InputMode
    if (_inputMode == InputMode.image) {
      _handleImageGenerationRequest(text);
    } else {
      _addUserMessage(text);
    }
  }

  // Handle image generation request
  Future<void> _handleImageGenerationRequest(String prompt) async {
    if (!_hasStartedChat) {
      setState(() => _hasStartedChat = true);
      _titleController.forward();
      _currentChatId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    // 1️⃣ Add user message
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: prompt,
      type: MessageType.user,
      sender: 'user',
      timestamp: DateTime.now(),
      hasAnimated: true,
    );

    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
    });

    _scrollToBottom();

    try {
      // 🔥 REAL BACKEND CALL
      final imageUrl = await ApiService.generateImage(prompt, conversationId: _currentChatId);

      // 2️⃣ Add IMAGE message
      final imageMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: '',
        type: MessageType.image, // 🖼️ IMPORTANT
        sender: 'bot',
        imageUrl: imageUrl,
        timestamp: DateTime.now(),
        isAnimating: true,
        hasAnimated: false,
      );

      setState(() {
        _messages.add(imageMessage);
        _isGenerating = false;
        _inputMode = InputMode.chat; // 🔁 Reset back to chat
      });

      _scrollToBottom();
      _saveChatToHistory(userMessage: userMessage, botMessage: imageMessage);
    } catch (e) {
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Image generation failed")),
      );
    }
  }


  void _handleVoiceSend(
      String duration,
      String? filePath, {
        String? transcript,
        int? seconds,
      }) {
    if (_isGenerating) return;
    final text = (transcript != null && transcript.trim().isNotEmpty)
        ? transcript.trim()
        : "Voice message";
    _addUserMessage(
      text,
      type: MessageType.voice,
      voiceDuration: duration,
      filePath: filePath,
      transcript: text,
      audioSeconds: seconds,
    );
  }

  void _stopGeneration() {
    _generationTimer?.cancel();
    setState(() {
      _isGenerating = false;
      _isBotTyping = false;
    });
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) return true;
      final status = await Permission.storage.request();
      if (!status.isGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission is required'), backgroundColor: AppColors.accentRed)
        );
      }
      return status.isGranted;
    }
    return true;
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required'), backgroundColor: AppColors.accentRed)
      );
    }
    return status.isGranted;
  }

  Future<bool> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required'), backgroundColor: AppColors.accentRed)
      );
    }
    return status.isGranted;
  }

  Future<bool> _requestFilePermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) return true;
      final status = await Permission.storage.request();
      return status.isGranted;
    }
    return true;
  }

  Future<void> _handleAttachmentSend(AttachmentType type) async {
    setState(() => _showAttachmentMenu = false);
    try {
      if (type == AttachmentType.image) {
        final hasPermission = await _requestStoragePermission();
        if (!hasPermission) return;
        final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
        if (image != null) {
          Uint8List? bytes;
          if (kIsWeb) bytes = await image.readAsBytes();
          setState(() {
            _pendingAttachment = PendingAttachment(
              type: type,
              filePath: image.path,
              fileName: image.name,
              fileBytes: bytes,
            );
          });
        }
      } else if (type == AttachmentType.camera) {
        final hasPermission = await _requestCameraPermission();
        if (!hasPermission) return;
        final XFile? photo = await _imagePicker.pickImage(source: ImageSource.camera);
        if (photo != null) {
          Uint8List? bytes;
          if (kIsWeb) bytes = await photo.readAsBytes();
          setState(() {
            _pendingAttachment = PendingAttachment(
              type: type,
              filePath: photo.path,
              fileName: photo.name,
              fileBytes: bytes,
            );
          });
        }
      } else if (type == AttachmentType.file) {
        final hasPermission = await _requestFilePermission();
        if (!hasPermission) return;
        final result = await FilePicker.platform.pickFiles(type: FileType.any);
        if (result != null && result.files.single.path != null) {
          setState(() {
            _pendingAttachment = PendingAttachment(
              type: type,
              filePath: result.files.single.path!,
              fileName: result.files.single.name,
              fileBytes: kIsWeb ? result.files.single.bytes : null,
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.accentRed)
        );
      }
    }
  }

  void _removePendingAttachment() {
    setState(() => _pendingAttachment = null);
  }

  // ignore: unused_element
  Future<void> _handleMicPress() async {
    if (_isGenerating) return;
    final hasPermission = await _requestMicrophonePermission();
    if (!hasPermission) return;

    final started = await _audioService.startRecording();
    if (started != null) {
      setState(() {
        _isRecording = true;
        _recordingDisplaySeconds = 0;
      });

      _recordingDisplayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDisplaySeconds++;
          });
        }
      });
    }
  }

  void _cancelRecording() {
    _recordingDisplayTimer?.cancel();
    _audioService.cancelRecording();
    setState(() {
      _isRecording = false;
      _recordingDisplaySeconds = 0;
    });
  }

  Future<void> _sendVoiceRecording() async {
    _recordingDisplayTimer?.cancel();
    final result = await _audioService.stopRecording();

    setState(() => _isRecording = false);

    if (result != null) {
      _handleVoiceSend(result.duration, result.path);
    }
  }


  void _addUserMessage(
      String content, {
        MessageType type = MessageType.user,
        String? voiceDuration,
        String? filePath,
        String? fileName,
        Uint8List? fileBytes,
        String? transcript,
        int? audioSeconds,
      }) async {
    // FIXED ARCH-04: Create the conversation on the backend BEFORE sending any messages.
    if (!_hasStartedChat) {
      setState(() => _hasStartedChat = true);
      _titleController.forward();
      _currentChatId = DateTime.now().millisecondsSinceEpoch.toString();
      // Create conversation on backend (non-blocking, idempotent)
      ApiService.createConversation(id: _currentChatId!, title: content.length > 30 ? '${content.substring(0, 30)}...' : content)
          .catchError((_) => <String, dynamic>{});
    }

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      type: type,
      sender: 'user',
      timestamp: DateTime.now(),
      voiceDuration: voiceDuration,
      filePath: filePath,
      fileName: fileName,
      fileBytes: fileBytes,
      transcript: transcript,
      audioSeconds: audioSeconds,
      hasAnimated: true,
    );

    setState(() {
      _messages.add(userMessage);
      _isRecording = false;
      _isBotTyping = true;
      _isGenerating = true;
    });

    _scrollToBottom();

    try {
      if (_isImageMode) {
        // 🖼️ IMAGE MODE
        final imageUrl = await ApiService.generateImage(content, conversationId: _currentChatId);
        final botMessage = _addBotImage(imageUrl);
        _saveChatToHistory(userMessage: userMessage, botMessage: botMessage);
      } else {
        // 💬 TEXT MODE WITH ATTACHMENT EXTRACTION
        String? extractedFileText;
        String? backendFilePath;
        if (filePath != null && filePath.isNotEmpty && type != MessageType.voice) {
          try {
            final uploadResult = await ApiService.uploadAttachment(filePath, fileBytes: fileBytes, fileName: fileName);
            if (uploadResult['extracted_text'] != null) {
              extractedFileText = uploadResult['extracted_text'];
            }
            if (uploadResult['file_path'] != null) {
              backendFilePath = uploadResult['file_path'];
            }
          } catch (err) {
            debugPrint('Attachment extraction error: $err');
          }
        }

        // FIXED: Pass conversationId so the backend can associate the message correctly.
        // For vision requests, send only the user's question — not the filename prefix.
        String chatPrompt = content;
        if (type == MessageType.image && fileName != null) {
          if (content.startsWith('$fileName\n')) {
            chatPrompt = content.substring(fileName.length + 1).trim();
          } else if (content == fileName) {
            chatPrompt = 'Describe this image.';
          }
        }

        final reply = await ApiService.sendChat(
          chatPrompt,
          fileText: extractedFileText,
          fileName: fileName,
          filePath: backendFilePath,
          conversationId: _currentChatId,
        );

        final botMessage = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: reply,
          type: MessageType.bot,
          sender: 'bot',
          timestamp: DateTime.now(),
          isAnimating: true,
          hasAnimated: false,
        );

        setState(() {
          _messages.add(botMessage);
        });

        // FIXED BUG-10: Batch-save user+bot messages in one request (runs in background)
        _saveChatToHistory(userMessage: userMessage, botMessage: botMessage).catchError((e) {
          debugPrint("Background save error: $e");
        });
      }

      setState(() {
        _isBotTyping = false;
        _isGenerating = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isBotTyping = false;
        _isGenerating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request failed: $e')),
        );
      }
    }
  }

  ChatMessage _addBotImage(String imageUrl) {
    final botImage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: "",
      type: MessageType.image, // 🖼️ IMPORTANT
      timestamp: DateTime.now(),
      imageUrl: imageUrl,
      isAnimating: true,
      hasAnimated: false,
    );

    setState(() {
      _isBotTyping = false;
      _isGenerating = false;
      _messages.add(botImage);
    });

    _scrollToBottom();
    return botImage;
  }


  /// FIXED BUG-10: Batch-save both user and bot messages in one API call.
  /// Previously only the last message was saved, causing conversation loss.
  Future<void> _saveChatToHistory({ChatMessage? userMessage, ChatMessage? botMessage}) async {
    if (_messages.isEmpty || _currentChatId == null) return;
    final firstUserMessage = _messages.firstWhere(
            (m) => m.type == MessageType.user || m.type == MessageType.voice || m.type == MessageType.image,
        orElse: () => _messages.first
    );
    String title = firstUserMessage.content;
    if (firstUserMessage.type == MessageType.voice) title = 'Voice Note';
    else if (firstUserMessage.type == MessageType.image) title = 'Image Upload';
    else if (title.length > 30) title = '${title.substring(0, 30)}...';

    final icon = _chatIcons[math.Random().nextInt(_chatIcons.length)];
    final lastMessage = _messages.last;
    final preview = lastMessage.content.length > 50 ? '${lastMessage.content.substring(0, 50)}...' : lastMessage.content;
    final existingIndex = _chatHistory.indexWhere((h) => h.id == _currentChatId);
    final historyItem = ChatHistoryItem(
        id: _currentChatId!,
        title: title,
        icon: existingIndex >= 0 ? _chatHistory[existingIndex].icon : icon,
        createdAt: existingIndex >= 0 ? _chatHistory[existingIndex].createdAt : DateTime.now(),
        lastUpdated: DateTime.now(),
        messages: List.from(_messages),
        preview: preview
    );
    setState(() {
      if (existingIndex >= 0) _chatHistory.removeAt(existingIndex);
      _chatHistory.insert(0, historyItem);
    });
    await ChatStorageService().saveChatHistory(_chatHistory);

    // FIXED BUG-10: Batch-save both messages (user + bot) in a single API call.
    if (userMessage != null || botMessage != null) {
      try {
        final batch = <Map<String, dynamic>>[];
        void addToB(ChatMessage m, String explicitSender) {
          String typeStr = 'text';
          if (m.type == MessageType.image) typeStr = 'image';
          else if (m.type == MessageType.voice) typeStr = 'voice';
          else if (m.type == MessageType.file) typeStr = 'file';
          batch.add({
            'id': m.id,
            'sender': explicitSender,
            'content': m.content,
            'type': typeStr,
            'file_path': m.filePath,
            'file_name': m.fileName,
            'voice_duration': m.voiceDuration,
            'image_url': m.imageUrl,
            'like_status': m.likeStatus,
          });
        }
        if (userMessage != null) addToB(userMessage, 'user');
        if (botMessage != null) addToB(botMessage, 'bot');
        if (batch.isNotEmpty) {
          await ApiService.batchSaveMessages(_currentChatId!, batch);
        }
      } catch (_) {}
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutQuart
        );
      }
    });
  }

  void _handleNewChat() {
    _stopGeneration();
    if (_messages.isNotEmpty) _saveChatToHistory();
    setState(() {
      _messages.clear();
      _hasStartedChat = false;
      _isSidebarOpen = false;
      _isBotTyping = false;
      _textController.clear();
      _currentChatId = null;
      _pendingAttachment = null;
      _inputMode = InputMode.chat; // Reset input mode
    });
    _titleController.reset();
  }

  void _loadChatFromHistory(ChatHistoryItem item) {
    _stopGeneration();
    setState(() {
      _messages = item.messages.map((m) => m.copyWith(hasAnimated: true)).toList();
      _currentChatId = item.id;
      _hasStartedChat = true;
      _isSidebarOpen = false;
      _inputMode = InputMode.chat; // Reset input mode
    });
    _titleController.forward();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  Future<void> _deleteChatFromHistory(String chatId) async {
    setState(() {
      _chatHistory.removeWhere((h) => h.id == chatId);
      if (_currentChatId == chatId) {
        _messages.clear();
        _hasStartedChat = false;
        _currentChatId = null;
        _titleController.reset();
      }
    });
    await ChatStorageService().saveChatHistory(_chatHistory);

    try {
      await ApiService.deleteConversation(chatId);
    } catch (_) {}
  }

  void _handleSearch(String query) {
    setState(() => _searchQuery = query);
  }

  List<ChatHistoryItem> get _filteredHistory {
    if (_searchQuery.isEmpty) return _chatHistory;
    final lowerQuery = _searchQuery.toLowerCase();
    return _chatHistory.where((item) =>
    item.title.toLowerCase().contains(lowerQuery) ||
        item.preview.toLowerCase().contains(lowerQuery)
    ).toList();
  }

  Future<void> _addToSearchHistory(String term) async {
    if (term.trim().isEmpty) return;
    await ChatStorageService().addSearchTerm(term);
    final searches = await ChatStorageService().loadSearchHistory();
    setState(() => _searchHistory = searches);
  }

  void _toggleAttachmentMenu() {
    setState(() => _showAttachmentMenu = !_showAttachmentMenu);
  }

  void _toggleMessageLike(String id, int status) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == id);
      if (index != -1) {
        final current = _messages[index].likeStatus;
        _messages[index] = _messages[index].copyWith(likeStatus: (current == status) ? null : status);
      }
    });
  }

  void _toggleMessagePlayback(String id) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      final message = _messages[index];
      if (message.filePath != null) {
        _audioService.playRecording(message.filePath!, onComplete: () {
          if (mounted) {
            setState(() {
              for (int i = 0; i < _messages.length; i++) {
                if (_messages[i].isPlaying) {
                  _messages[i] = _messages[i].copyWith(isPlaying: false);
                }
              }
            });
          }
        });

        setState(() {
          for (int i = 0; i < _messages.length; i++) {
            if (i != index && _messages[i].isPlaying) {
              _messages[i] = _messages[i].copyWith(isPlaying: false);
            }
          }
          _messages[index] = _messages[index].copyWith(isPlaying: !_messages[index].isPlaying);
        });
      }
    }
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: AppColors.neonGreen, size: 20),
              const SizedBox(width: 12),
              Text('Copied to clipboard', style: GoogleFonts.quicksand(color: Colors.white))
            ]),
            backgroundColor: AppColors.sidebarSurface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2)
        )
    );
  }

  void _onMessageAnimationComplete(String id) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      setState(() {
        _messages[index] = _messages[index].copyWith(hasAnimated: true, isAnimating: false);
      });
    }
  }

  Future<void> _openFile(String? filePath) async {
    if (filePath == null) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await OpenFile.open(filePath);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File not found'), backgroundColor: AppColors.accentRed)
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot open file: $e'), backgroundColor: AppColors.accentRed)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: MouseRegion(
        onHover: (event) { setState(() => _cursorPosition = event.localPosition); },
        child: GestureDetector(
          onPanUpdate: (details) { setState(() => _cursorPosition = details.localPosition); },
          onTap: _closeSidebar,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              Positioned.fill(child: CursorFollowingBackground(cursorPosition: _cursorPosition, animationController: _backgroundController)),
              SafeArea(
                child: Column(
                  children: [
                    _buildAppBar(context),
                    Expanded(
                      child: _hasStartedChat
                          ? _buildMessageList(context)
                          : _buildTagline(context),
                    ),
                    _buildInputArea(isMobile),
                  ],
                ),
              ),
              _buildSidebarOverlay(),
              // Immersive Advanced Voice Mode panel (blurred backdrop + live waveform)
              if (_isVoiceMode)
                VoiceModePanel(
                  amplitudeStream: _audioService.amplitudeStream,
                  elapsed: _voiceElapsed,
                  transcript: _voiceTranscript,
                  onCancel: () => _stopVoiceMode(cancel: true),
                  onStop: () => _stopVoiceMode(),
                ),
              if (_showLogoutMenu) _buildLogoutMenuOverlay(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 28),
            onPressed: _toggleSidebar,
          ),
          const Spacer(),
          _buildUserProfileBadge(context),
        ],
      ),
    );
  }

  Widget _buildUserProfileBadge(BuildContext context) {
    return GestureDetector(
      onTap: _toggleLogoutMenu,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _showLogoutMenu ? AppColors.primaryGradientStart.withOpacity(0.5) : Colors.white12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Text(
              _userProfile?.name ?? "User",
              style: GoogleFonts.quicksand(fontWeight: FontWeight.bold, color: Colors.white, fontSize: Responsive.fontSize(context, 14)),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primaryGradientStart,
              backgroundImage: _userProfile?.avatarUrl != null ? (kIsWeb ? NetworkImage(_userProfile!.avatarUrl!) as ImageProvider : FileImage(File(_userProfile!.avatarUrl!))) : null,
              child: _userProfile?.avatarUrl == null
                  ? Text(
                (_userProfile?.name ?? "U").substring(0, 1).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              )
                  : null,
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              duration: const Duration(milliseconds: 200),
              turns: _showLogoutMenu ? 0.5 : 0,
              child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutMenuOverlay(BuildContext context) {
    return Positioned(
      top: 60,
      right: 16,
      child: AnimatedBuilder(
        animation: _logoutMenuController,
        builder: (context, child) {
          return Transform.scale(
            scale: _logoutMenuScale.value,
            alignment: Alignment.topRight,
            child: Opacity(
              opacity: _logoutMenuController.value,
              child: child,
            ),
          );
        },
        child: Container(
          width: 200,
          decoration: BoxDecoration(
            color: AppColors.sidebarBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primaryGradientStart,
                      backgroundImage: _userProfile?.avatarUrl != null ? (kIsWeb ? NetworkImage(_userProfile!.avatarUrl!) as ImageProvider : FileImage(File(_userProfile!.avatarUrl!))) : null,
                      child: _userProfile?.avatarUrl == null
                          ? Text(
                        (_userProfile?.name ?? "U").substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userProfile?.name ?? "User",
                            style: GoogleFonts.quicksand(color: Colors.white, fontWeight: FontWeight.bold, fontSize: Responsive.fontSize(context, 14)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _userProfile?.email ?? "user@maveric.ai",
                            style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 11)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.borderLight),
              ListTile(
                leading: const Icon(Icons.person_outline, color: AppColors.textSecondary, size: 20),
                title: Text('Profile', style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 14))),
                onTap: () {
                  _hideLogoutMenu();
                  showDialog(
                      context: context,
                      builder: (_) => ProfileDialog(
                          profile: _userProfile,
                          onSave: (p) async {
                            await ChatStorageService().saveUserProfile(p);
                            setState(() => _userProfile = p);
                          }
                      )
                  );
                },
                dense: true,
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.logoutRed, size: 20),
                title: Text('Log Out', style: TextStyle(color: AppColors.logoutRed, fontSize: Responsive.fontSize(context, 14))),
                onTap: _handleLogout,
                dense: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagline(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => AppGradients.titleGradient.createShader(bounds),
              child: Text(
                'Maveric AI',
                style: GoogleFonts.fredoka(
                  fontSize: Responsive.fontSize(context, 36),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 48,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.sidebarSurface.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bolt, color: Color(0xFFFFD700), size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _taglines[0],
                        style: GoogleFonts.quicksand(
                          color: AppColors.textPrimary,
                          fontSize: Responsive.fontSize(context, 14),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length + (_isBotTyping ? 1 : 0) + (_isGenerating && _inputMode == InputMode.image ? 1 : 0),
      itemBuilder: (context, index) {
        // Show image generating placeholder
        if (_isGenerating && _inputMode == InputMode.image && index == _messages.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 220,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          );
        }

        if (index == _messages.length && _isBotTyping) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TypingIndicator(),
            ),
          );
        }
        final message = _messages[index];
        return MessageBubble(
          message: message,
          isLast: index == _messages.length - 1,
          onLike: () => _toggleMessageLike(message.id, 1),
          onDislike: () => _toggleMessageLike(message.id, -1),
          onCopy: () => _copyMessage(message.content),
          onPlay: () => _toggleMessagePlayback(message.id),
          onOpenFile: () => _openFile(message.filePath),
          onAnimationComplete: () => _onMessageAnimationComplete(message.id),
        );
      },
    );
  }

  Widget _buildInputArea(bool isMobile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showAttachmentMenu)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: AttachmentMenuWithPermissions(onSelect: _handleAttachmentSend),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, isMobile ? 8 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: _isRecording
                    ? KeyedSubtree(
                  key: const ValueKey('recording-bar'),
                  child: _buildRecordingUI(),
                )
                    : KeyedSubtree(
                  key: const ValueKey('text-input'),
                  child: _buildTextInput(isMobile),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Maveric AI can make mistakes. Check important info.',
            style: TextStyle(color: AppColors.disclaimerText, fontSize: Responsive.fontSize(context, 11)),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return RecordingIndicatorBar(
      elapsedSeconds: _recordingDisplaySeconds,
      onCancel: _cancelRecording,
      onSend: _sendVoiceRecording,
    );
  }

  Widget _buildTextInput(bool isMobile) {
    // Get hint text based on input mode
    String getHintText() {
      if (_pendingAttachment != null) {
        return "Add a message (optional)...";
      }
      return _inputMode == InputMode.image
          ? "Describe the image..."
          : "";
    }

    return Column(
      children: [
        // Show pending attachment above text input
        if (_pendingAttachment != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.sidebarSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryGradientStart.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Builder(
                  builder: (context) {
                    final isImg = _pendingAttachment!.type == AttachmentType.image ||
                        _pendingAttachment!.type == AttachmentType.camera ||
                        ['.png', '.jpg', '.jpeg', '.webp'].any((ext) =>
                            _pendingAttachment!.filePath.toLowerCase().endsWith(ext));
                    final bool fileExists = kIsWeb ? _pendingAttachment!.fileBytes != null : File(_pendingAttachment!.filePath).existsSync();
                    if (isImg && fileExists) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: (kIsWeb && _pendingAttachment!.fileBytes != null)
                            ? Image.memory(
                                _pendingAttachment!.fileBytes!,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(_pendingAttachment!.filePath),
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                              ),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGradientStart.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _pendingAttachment!.type == AttachmentType.file
                            ? Icons.attach_file_rounded
                            : Icons.image_rounded,
                        color: AppColors.primaryGradientStart,
                        size: 20,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pendingAttachment!.fileName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: Responsive.fontSize(context, 13),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _pendingAttachment!.type == AttachmentType.camera
                            ? 'Camera photo'
                            : _pendingAttachment!.type == AttachmentType.image
                            ? 'Image'
                            : 'File',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: Responsive.fontSize(context, 11),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                  onPressed: _removePendingAttachment,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.inputBackground,
            borderRadius: BorderRadius.circular(28),
            // Add border when in image mode
            border: _inputMode == InputMode.image
                ? Border.all(color: AppColors.imageModeActive.withOpacity(0.5), width: 1.5)
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _showAttachmentMenu ? Icons.close_rounded : Icons.add_rounded,
                  color: _showAttachmentMenu ? AppColors.primaryGradientStart : Colors.white54,
                ),
                onPressed: _toggleAttachmentMenu,
              ),
              // Image generation toggle button
              GestureDetector(
                onTap: _toggleImageMode,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: _inputMode == InputMode.image
                        ? AppColors.imageModeActive.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.image_outlined,
                    color: _inputMode == InputMode.image
                        ? AppColors.imageModeActive
                        : Colors.white54,
                    size: 22,
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Show typewriter hint only in chat mode without pending attachment
                    if (_textController.text.isEmpty && !_inputFocusNode.hasFocus && _pendingAttachment == null && _inputMode == InputMode.chat)
                      TypewriterHint(
                        hints: const [
                          "How can I help you?",
                          "What's on your mind?",
                          "Ask me a question...",
                        ],
                      ),
                    TextField(
                      controller: _textController,
                      focusNode: _inputFocusNode,
                      style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 15)),
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _handleSendMessage,
                      decoration: InputDecoration(
                        hintText: getHintText(),
                        hintStyle: TextStyle(color: AppColors.textMuted),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onLongPress: _handleMicPress,
                onTap: _toggleVoiceInput,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: PulsingMicButton(isActive: _isVoiceMode || _isListening),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 6, top: 6),
                child: GestureDetector(
                  onTap: _isGenerating ? _stopGeneration : () => _handleSendMessage(_textController.text),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: _isGenerating ? null : AppGradients.primary,
                      color: _isGenerating ? AppColors.accentRed : null,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isGenerating ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarOverlay() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      left: _isSidebarOpen ? 0 : -280,
      top: 0,
      bottom: 0,
      width: 280,
      child: SidebarDrawer(
        onClose: _closeSidebar,
        onNewChat: _handleNewChat,
        onSettings: () {
          _closeSidebar();
          showDialog(context: context, builder: (_) => const SettingsDialog());
        },
        onHelp: () {
          _closeSidebar();
          showDialog(context: context, builder: (_) => const HelpDialog());
        },
        onLogout: _handleLogout,
        chatHistory: _filteredHistory,
        searchQuery: _searchQuery,
        searchHistory: _searchHistory,
        onSearch: _handleSearch,
        onSearchSubmit: _addToSearchHistory,
        onLoadChat: _loadChatFromHistory,
        onDeleteChat: _deleteChatFromHistory,
      ),
    );
  }
}

// ============================================================================
//  10. TYPEWRITER HINT
// ============================================================================

class TypewriterHint extends StatefulWidget {
  final List<String> hints;
  const TypewriterHint({super.key, required this.hints});
  @override
  State<TypewriterHint> createState() => _TypewriterHintState();
}

class _TypewriterHintState extends State<TypewriterHint> {
  Timer? _typeTimer;
  String _displayedText = "";
  int _charIndex = 0;
  int _currentHintIndex = 0;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    super.dispose();
  }

  void _startTyping() {
    _typeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      final fullText = widget.hints[_currentHintIndex];

      setState(() {
        if (_isDeleting) {
          if (_charIndex > 0) {
            _charIndex--;
            _displayedText = fullText.substring(0, _charIndex);
          } else {
            _isDeleting = false;
            _currentHintIndex = (_currentHintIndex + 1) % widget.hints.length;
          }
        } else {
          if (_charIndex < fullText.length) {
            _charIndex++;
            _displayedText = fullText.substring(0, _charIndex);
          } else {
            _typeTimer?.cancel();
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                _isDeleting = true;
                _startTyping();
              }
            });
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: GoogleFonts.quicksand(
        color: AppColors.textMuted,
        fontSize: Responsive.fontSize(context, 15),
      ),
    );
  }
}

// ============================================================================
//  11. PROFILE DIALOG
// ============================================================================

class ProfileDialog extends StatefulWidget {
  final UserProfile? profile;
  final Function(UserProfile) onSave;
  const ProfileDialog({super.key, this.profile, required this.onSave});
  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late TextEditingController _nameController;
  bool _isEditing = false;
  String? _avatarPath;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile?.name ?? '');
    _avatarPath = widget.profile?.avatarUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _avatarPath = image.path);
    }
  }

  void _handleSave() {
    if (widget.profile != null) {
      final updatedProfile = UserProfile(
        id: widget.profile!.id,
        name: _nameController.text,
        email: widget.profile!.email,
        avatarUrl: _avatarPath,
        createdAt: widget.profile!.createdAt,
        isGoogleUser: widget.profile!.isGoogleUser,
        isGuest: widget.profile!.isGuest,
      );
      widget.onSave(updatedProfile);
      setState(() => _isEditing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebarBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: Responsive.isMobile(context) ? Responsive.w(context) * 0.9 : 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Profile", style: GoogleFonts.fredoka(color: Colors.white, fontSize: Responsive.fontSize(context, 24))),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 24),
            if (_isEditing) ...[
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primaryGradientStart,
                      backgroundImage: _avatarPath != null ? (kIsWeb ? NetworkImage(_avatarPath!) as ImageProvider : FileImage(File(_avatarPath!))) : null,
                      child: _avatarPath == null
                          ? Text(
                        (widget.profile?.name ?? "U").substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32),
                      )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryGradientStart,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 15)),
                decoration: InputDecoration(
                  labelText: "Name",
                  labelStyle: GoogleFonts.quicksand(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.sidebarSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: TextEditingController(text: widget.profile?.email ?? ''),
                enabled: false,
                style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 15)),
                decoration: InputDecoration(
                  labelText: "Email (cannot be changed)",
                  labelStyle: GoogleFonts.quicksand(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.sidebarSurface.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGradientStart,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _handleSave,
                  child: Text("Save Changes", style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
                ),
              ),
            ] else ...[
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primaryGradientStart,
                backgroundImage: _avatarPath != null ? (kIsWeb ? NetworkImage(_avatarPath!) as ImageProvider : FileImage(File(_avatarPath!))) : null,
                child: _avatarPath == null
                    ? Text(
                  (widget.profile?.name ?? "U").substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32),
                )
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                widget.profile?.name ?? "User",
                style: GoogleFonts.quicksand(color: Colors.white, fontWeight: FontWeight.bold, fontSize: Responsive.fontSize(context, 20)),
              ),
              const SizedBox(height: 4),
              Text(
                widget.profile?.email ?? "user@maveric.ai",
                style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 14)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.borderMedium),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => setState(() => _isEditing = true),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text("Edit Profile", style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  12. ATTACHMENT MENU
// ============================================================================

class AttachmentMenuWithPermissions extends StatefulWidget {
  final Function(AttachmentType) onSelect;
  const AttachmentMenuWithPermissions({super.key, required this.onSelect});
  @override
  State<AttachmentMenuWithPermissions> createState() => _AttachmentMenuWithPermissionsState();
}

class _AttachmentMenuWithPermissionsState extends State<AttachmentMenuWithPermissions> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: Alignment.bottomLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.sidebarBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAttachmentButton(context, Icons.image_outlined, 'Photo', () => widget.onSelect(AttachmentType.image)),
              const SizedBox(width: 4),
              _buildAttachmentButton(context, Icons.camera_alt_outlined, 'Camera', () => widget.onSelect(AttachmentType.camera)),
              const SizedBox(width: 4),
              _buildAttachmentButton(context, Icons.attach_file_rounded, 'File', () => widget.onSelect(AttachmentType.file)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentButton(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 24),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 11))),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  13. MESSAGE BUBBLE - UPDATED WITH FULLSCREEN, DOWNLOAD, LOADING
// ============================================================================

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isLast;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback onCopy;
  final VoidCallback onPlay;
  final VoidCallback onOpenFile;
  final VoidCallback onAnimationComplete;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isLast,
    required this.onLike,
    required this.onDislike,
    required this.onCopy,
    required this.onPlay,
    required this.onOpenFile,
    required this.onAnimationComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == 'user';
    final isVoice = message.type == MessageType.voice;
    final isImageType = message.type == MessageType.image;
    final isFileType = message.type == MessageType.file;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isUser ? AppGradients.primary : null,
                color: isUser ? null : AppColors.sidebarSurface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                border: isUser ? null : Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isVoice) _buildVoiceContent(context)
                  else if (isImageType && message.imageUrl != null) _buildImageContent(context)
                  else if (isImageType && message.filePath != null) _buildUserImageAttachment(context)
                  else if (isFileType && message.filePath != null) _buildFileContent(context)
                    else if (!isUser && message.isAnimating && !message.hasAnimated)
                        TypewriterText(
                          text: message.content,
                          onComplete: onAnimationComplete,
                        )
                      else Text(
                          message.content,
                          style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 14), height: 1.4),
                        ),
                ],
              ),
            ),
            if (!isUser) _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceContent(BuildContext context) {
    final transcript = (message.transcript ?? '').trim();
    final hasFile = (message.filePath ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasFile)
          VoiceMessagePlayer(
            key: ValueKey('player-${message.id}'),
            messageId: message.id,
            filePath: message.filePath!,
            fallbackDuration: message.voiceDuration,
            seconds: message.audioSeconds,
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                message.voiceDuration ?? "Voice message",
                style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 13)),
              ),
            ],
          ),
        if (transcript.isNotEmpty && transcript != 'Voice message') ...[
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              transcript,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: Responsive.fontSize(context, 14),
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUserImageAttachment(BuildContext context) {
    // Extract prompt without filename
    String promptText = message.content;
    if (message.fileName != null && promptText.startsWith('${message.fileName}\n')) {
      promptText = promptText.substring(message.fileName!.length + 1);
    } else if (promptText == message.fileName) {
      promptText = "";
    }

    void openFullScreen() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FullScreenImage(
            filePath: message.filePath,
            fileBytes: message.fileBytes,
          ),
        ),
      );
    }

    Widget buildThumbnail() {
      if (kIsWeb && message.fileBytes != null) {
        return Image.memory(
          message.fileBytes!,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
        );
      }
      if (!kIsWeb && message.filePath != null) {
        return Image.file(
          File(message.filePath!),
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _attachmentImagePlaceholder(),
        );
      }
      return _attachmentImagePlaceholder();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: openFullScreen,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: buildThumbnail(),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message.fileName ?? "Attached Image",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: Responsive.fontSize(context, 14),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (promptText.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            promptText,
            style: TextStyle(
              color: Colors.white,
              fontSize: Responsive.fontSize(context, 14),
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _attachmentImagePlaceholder() {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.image_rounded, color: Colors.white70, size: 28),
    );
  }

  // ✅ NEW: Updated _buildImageContent with loading, fullscreen, and download
  Widget _buildImageContent(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 👉 Fullscreen preview
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _FullScreenImage(
              imageUrl: message.imageUrl,
              filePath: message.filePath,
              fileBytes: message.fileBytes,
            ),
          ),
        );
      },
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: message.imageUrl != null
                ? Image.network(
              message.imageUrl!,
              width: 220,
              height: 160,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 220,
                  height: 160,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const CircularProgressIndicator(),
                );
              },
              errorBuilder: (_, __, ___) {
                return Container(
                  width: 220,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.broken_image, size: 40, color: AppColors.textMuted),
                );
              },
            )
                : (kIsWeb && message.fileBytes != null
                ? Image.memory(
              message.fileBytes!,
              width: 220,
              height: 160,
              fit: BoxFit.cover,
            )
                : Image.file(
              File(message.filePath!),
              width: 220,
              height: 160,
              fit: BoxFit.cover,
            )),
          ),

          // ⬇️ DOWNLOAD BUTTON
          if (message.imageUrl != null)
            Positioned(
              bottom: 8,
              right: 8,
              child: InkWell(
                onTap: () => _downloadImage(context, message.imageUrl!),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.download_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ✅ NEW: Download image function
  void _downloadImage(BuildContext context, String url) async {
    try {
      // For web, use url_launcher to open in new tab
      if (kIsWeb) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        // For mobile, open URL which triggers download
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.download_done, color: AppColors.neonGreen, size: 20),
              const SizedBox(width: 12),
              Text("Image download started", style: GoogleFonts.quicksand(color: Colors.white)),
            ],
          ),
          backgroundColor: AppColors.sidebarSurface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Download failed: $e"),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  Widget _buildFileContent(BuildContext context) {
    return GestureDetector(
      onTap: onOpenFile,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.insert_drive_file_outlined, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? "File",
                  style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 14), fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text("Tap to open", style: TextStyle(color: Colors.white70, fontSize: Responsive.fontSize(context, 12))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            icon: Icons.thumb_up_outlined,
            activeIcon: Icons.thumb_up,
            isActive: message.likeStatus == 1,
            onTap: onLike,
          ),
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.thumb_down_outlined,
            activeIcon: Icons.thumb_down,
            isActive: message.likeStatus == -1,
            onTap: onDislike,
          ),
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.copy_outlined,
            onTap: onCopy,
          ),
        ],
      ),
    );
  }
}

// ✅ NEW: Full Screen Image View Widget
class _FullScreenImage extends StatelessWidget {
  final String? imageUrl;
  final String? filePath;
  final Uint8List? fileBytes;

  const _FullScreenImage({this.imageUrl, this.filePath, this.fileBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (imageUrl != null)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () async {
                final uri = Uri.parse(imageUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Downloading image...')),
                );
              },
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4,
          child: imageUrl != null
              ? Image.network(imageUrl!)
              : (kIsWeb && fileBytes != null)
              ? Image.memory(fileBytes!)
              : (kIsWeb && filePath != null)
              ? Image.network(filePath!)
              : Image.file(File(filePath!)),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final bool isActive;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.activeIcon,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            isActive ? (activeIcon ?? icon) : icon,
            size: 18,
            color: isActive ? AppColors.primaryGradientStart : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  14. TYPEWRITER TEXT
// ============================================================================

class TypewriterText extends StatefulWidget {
  final String text;
  final VoidCallback onComplete;

  const TypewriterText({super.key, required this.text, required this.onComplete});

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  Timer? _timer;
  String displayedText = "";
  int _charIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTyping() {
    _timer = Timer.periodic(const Duration(milliseconds: 15), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_charIndex < widget.text.length) {
        setState(() {
          _charIndex++;
          displayedText = widget.text.substring(0, _charIndex);
        });
      } else {
        timer.cancel();
        widget.onComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(displayedText, style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 14), height: 1.4));
  }
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});
  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.sidebarSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final double t = _controller.value;
              final double offset = index * 0.2;
              final double wave = math.sin((t - offset) * 2 * math.pi) * 0.5 + 0.5;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.primaryGradientStart.withOpacity(0.3 + (wave * 0.7)),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

// ============================================================================
//  14.1 BLINKING DOT & WAVEFORM
// ============================================================================

/// Smooth, GPU-friendly voice waveform driven by a single AnimationController.
/// Repaints only the painter (no widget-tree rebuilds) so it holds 60 FPS.
class VoiceWaveform extends StatefulWidget {
  final bool isActive;
  final Color color;
  final double height;
  final int barCount;
  const VoiceWaveform({
    super.key,
    required this.isActive,
    this.color = AppColors.accentRed,
    this.height = 36,
    this.barCount = 28,
  });
  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.isActive) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant VoiceWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: CustomPaint(
          painter: _WaveformPainter(
            progress: _controller,
            color: widget.color,
            barCount: widget.barCount,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;
  final int barCount;

  _WaveformPainter({required this.progress, required this.color, required this.barCount})
      : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final double t = progress.value * 2 * math.pi;
    final double slot = size.width / barCount;
    final double barWidth = math.min(3.0, slot * 0.45);
    final double cy = size.height / 2;
    final double maxAmp = size.height / 2;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final double phase = i * 0.42;
      // Layered sines give an organic, speech-like motion.
      final double wave = 0.55 * math.sin(t + phase) +
          0.30 * math.sin(t * 1.7 + phase * 1.9) +
          0.15 * math.sin(t * 2.6 + phase * 0.7);
      // Envelope keeps the edges shorter, like Siri / Gemini Live.
      final double envelope = math.sin((i + 0.5) / barCount * math.pi);
      final double amp = (0.18 + 0.82 * wave.abs()) * envelope * maxAmp;
      final double h = math.max(barWidth, amp * 2);
      final double x = slot * i + (slot - barWidth) / 2;

      paint.color = color.withOpacity(0.45 + 0.45 * envelope);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, cy - h / 2, barWidth, h),
          Radius.circular(barWidth),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.barCount != barCount;
}

/// Microphone icon with a breathing glow ring, used inside the text input.
class PulsingMicButton extends StatefulWidget {
  final bool isActive;
  const PulsingMicButton({super.key, required this.isActive});

  @override
  State<PulsingMicButton> createState() => _PulsingMicButtonState();
}

class _PulsingMicButtonState extends State<PulsingMicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    if (widget.isActive) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PulsingMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return const Icon(Icons.mic_none_rounded, color: Colors.white54);
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final double v = Curves.easeInOut.transform(_controller.value);
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentRed.withOpacity(0.10 + 0.10 * v),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentRed.withOpacity(0.25 + 0.25 * v),
                  blurRadius: 10 + 10 * v,
                  spreadRadius: 1 + 2 * v,
                ),
              ],
            ),
            child: Transform.scale(scale: 1.0 + 0.10 * v, child: child),
          );
        },
        child: const Icon(Icons.mic_rounded, color: AppColors.accentRed),
      ),
    );
  }
}

/// The full recording bar: glowing pulsing mic, "Recording..." label,
/// elapsed time and a live waveform. All animation is local to this widget,
/// so the chat page is never rebuilt per frame.
class RecordingIndicatorBar extends StatefulWidget {
  final int elapsedSeconds;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const RecordingIndicatorBar({
    super.key,
    required this.elapsedSeconds,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<RecordingIndicatorBar> createState() => _RecordingIndicatorBarState();
}

class _RecordingIndicatorBarState extends State<RecordingIndicatorBar>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _ring;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    _ring.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final m = widget.elapsedSeconds ~/ 60;
    final s = widget.elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          RepaintBoundary(
            child: SizedBox(
              width: 42,
              height: 42,
              child: AnimatedBuilder(
                animation: Listenable.merge([_breath, _ring]),
                builder: (context, child) {
                  final double b = Curves.easeInOut.transform(_breath.value);
                  return CustomPaint(
                    painter: _GlowRingPainter(ringProgress: _ring.value, breath: b),
                    child: Center(
                      child: Transform.scale(scale: 1.0 + 0.08 * b, child: child),
                    ),
                  );
                },
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: AppColors.accentRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic_rounded, color: Colors.white, size: 15),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recording...',
                style: TextStyle(
                  color: AppColors.accentRed,
                  fontSize: Responsive.fontSize(context, 11),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formattedTime,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: Responsive.fontSize(context, 13),
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          const Expanded(child: VoiceWaveform(isActive: true)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white54),
            onPressed: widget.onCancel,
            tooltip: 'Cancel recording',
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: widget.onSend,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(gradient: AppGradients.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// Expanding glow rings behind the recording mic (Siri / ChatGPT Voice feel).
class _GlowRingPainter extends CustomPainter {
  final double ringProgress;
  final double breath;

  _GlowRingPainter({required this.ringProgress, required this.breath});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double maxRadius = size.width / 2;

    // Two ripples offset in time.
    for (int i = 0; i < 2; i++) {
      final double p = (ringProgress + i * 0.5) % 1.0;
      final double radius = 13 + (maxRadius - 13) * p;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.accentRed.withOpacity((1 - p) * 0.45);
      canvas.drawCircle(center, radius, paint);
    }

    // Soft breathing halo.
    final halo = Paint()
      ..color = AppColors.accentRed.withOpacity(0.12 + 0.12 * breath)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, 14 + 3 * breath, halo);
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter oldDelegate) =>
      oldDelegate.ringProgress != ringProgress || oldDelegate.breath != breath;
}

// ============================================================================
//  15. SIDEBAR DRAWER
// ============================================================================

class SidebarDrawer extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onNewChat;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final List<ChatHistoryItem> chatHistory;
  final String searchQuery;
  final List<String> searchHistory;
  final Function(String) onSearch;
  final Function(String) onSearchSubmit;
  final Function(ChatHistoryItem) onLoadChat;
  final Function(String) onDeleteChat;

  const SidebarDrawer({
    super.key,
    required this.onClose,
    required this.onNewChat,
    required this.onSettings,
    required this.onHelp,
    required this.onLogout,
    required this.chatHistory,
    required this.searchQuery,
    required this.searchHistory,
    required this.onSearch,
    required this.onSearchSubmit,
    required this.onLoadChat,
    required this.onDeleteChat,
  });

  @override
  State<SidebarDrawer> createState() => _SidebarDrawerState();
}

class _SidebarDrawerState extends State<SidebarDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  // ignore: unused_field
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
    _searchFocusNode.addListener(() {
      setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inDays > 7) return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.sidebarBackground,
        borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(5, 0))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(gradient: AppGradients.primary, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('Maveric AI', style: GoogleFonts.fredoka(color: Colors.white, fontSize: Responsive.fontSize(context, 18), fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: widget.onClose),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: widget.onNewChat,
              icon: const Icon(Icons.add, size: 18),
              label: Text('New Chat', style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGradientStart,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 14)),
              onChanged: widget.onSearch,
              onSubmitted: widget.onSearchSubmit,
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 14)),
                prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                filled: true,
                fillColor: AppColors.sidebarSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Recent', style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 12), fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.chatHistory.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, color: AppColors.textMuted.withOpacity(0.5), size: 48),
                  const SizedBox(height: 16),
                  Text(
                    widget.searchQuery.isNotEmpty ? "No results found" : "No conversations yet",
                    style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 14)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.searchQuery.isNotEmpty ? "Try different keywords" : "Start a new chat to begin",
                    style: TextStyle(color: AppColors.textMuted.withOpacity(0.7), fontSize: Responsive.fontSize(context, 12)),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.chatHistory.length,
              itemBuilder: (context, index) {
                final item = widget.chatHistory[index];
                return Dismissible(
                  key: Key(item.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (direction) async {
                    final result = await showDialog<bool>(
                        context: context,
                        builder: (_) => DeleteConfirmationDialog(title: item.title)
                    );
                    return result ?? false;
                  },
                  onDismissed: (direction) => widget.onDeleteChat(item.id),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: AppColors.accentRed.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete_outline, color: AppColors.accentRed),
                  ),
                  child: _ChatHistoryTile(
                    item: item,
                    formatTimeAgo: _formatTimeAgo,
                    onTap: () => widget.onLoadChat(item),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildMenuTile(Icons.settings_outlined, 'Settings', widget.onSettings),
                _buildMenuTile(Icons.help_outline, 'Help & Support', widget.onHelp),
                _buildMenuTile(Icons.logout, 'Log Out', widget.onLogout, isDestructive: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Maveric AI v1.2.0',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted.withOpacity(0.5), fontSize: Responsive.fontSize(context, 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    final color = isDestructive ? AppColors.logoutRed : AppColors.textSecondary;
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(title, style: TextStyle(color: isDestructive ? AppColors.logoutRed : AppColors.textPrimary, fontWeight: isDestructive ? FontWeight.w600 : FontWeight.normal, fontSize: Responsive.fontSize(context, 14))),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

class _ChatHistoryTile extends StatelessWidget {
  final ChatHistoryItem item;
  final String Function(DateTime) formatTimeAgo;
  final VoidCallback onTap;

  const _ChatHistoryTile({required this.item, required this.formatTimeAgo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.sidebarSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: AppColors.textSecondary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 14), fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.preview,
                    style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 12)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatTimeAgo(item.lastUpdated),
              style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 11)),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  16. DIALOGS
// ============================================================================

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _pushNotifications = true;
  bool _soundEffects = true;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebarBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: Responsive.isMobile(context) ? Responsive.w(context) * 0.9 : 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Settings", style: GoogleFonts.fredoka(color: Colors.white, fontSize: Responsive.fontSize(context, 24))),
            const SizedBox(height: 24),
            Text("GENERAL", style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 11), fontWeight: FontWeight.bold, letterSpacing: 1)),
            _buildSwitch("Sound Effects", _soundEffects, (v) => setState(() => _soundEffects = v)),
            const SizedBox(height: 16),
            Text("NOTIFICATIONS", style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 11), fontWeight: FontWeight.bold, letterSpacing: 1)),
            _buildSwitch("Push Notifications", _pushNotifications, (v) => setState(() => _pushNotifications = v)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGradientStart,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text("Done", style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch(String title, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 14))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primaryGradientStart,
          ),
        ],
      ),
    );
  }
}

class HelpDialog extends StatelessWidget {
  const HelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebarBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: Responsive.isMobile(context) ? Responsive.w(context) * 0.9 : 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Help & Support", style: GoogleFonts.fredoka(color: Colors.white, fontSize: Responsive.fontSize(context, 24))),
            const SizedBox(height: 24),
            _buildHelpItem(context, Icons.chat_bubble_outline, "Chat Support", "Get help from our team"),
            _buildHelpItem(context, Icons.article_outlined, "Documentation", "Read our guides"),
            _buildHelpItem(context, Icons.feedback_outlined, "Send Feedback", "Help us improve"),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGradientStart,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text("Close", style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(BuildContext context, IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.sidebarSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryGradientStart, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.white, fontSize: Responsive.fontSize(context, 14), fontWeight: FontWeight.w500)),
                Text(subtitle, style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 12))),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class LogoutConfirmationDialog extends StatelessWidget {
  final VoidCallback onConfirm;
  const LogoutConfirmationDialog({super.key, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebarBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: Responsive.isMobile(context) ? Responsive.w(context) * 0.9 : 360,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.logoutRed.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout, color: AppColors.logoutRed, size: 32),
            ),
            const SizedBox(height: 20),
            Text("Log Out?", style: GoogleFonts.fredoka(color: Colors.white, fontSize: Responsive.fontSize(context, 22))),
            const SizedBox(height: 8),
            Text(
              "Are you sure you want to log out? All your local data will be cleared.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 14)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.borderMedium),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text("Cancel", style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.logoutRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text("Log Out", style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DeleteConfirmationDialog extends StatelessWidget {
  final String title;
  const DeleteConfirmationDialog({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebarBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: Responsive.isMobile(context) ? Responsive.w(context) * 0.9 : 360,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accentRed.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: AppColors.accentRed, size: 32),
            ),
            const SizedBox(height: 20),
            Text("Delete Chat?", style: GoogleFonts.fredoka(color: Colors.white, fontSize: Responsive.fontSize(context, 22))),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to delete "$title"? This cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: Responsive.fontSize(context, 14)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.borderMedium),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text("Cancel", style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text("Delete", style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  ADVANCED VOICE MODE — floating panel, live mic waveform, playback
//  All animation is confined to these widgets (RepaintBoundary + ValueNotifier)
//  so the chat page never rebuilds while recording.
// ============================================================================

class VoiceModePanel extends StatefulWidget {
  final Stream<double> amplitudeStream;
  final ValueNotifier<int> elapsed;
  final ValueNotifier<String> transcript;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  const VoiceModePanel({
    super.key,
    required this.amplitudeStream,
    required this.elapsed,
    required this.transcript,
    required this.onCancel,
    required this.onStop,
  });

  @override
  State<VoiceModePanel> createState() => _VoiceModePanelState();
}

class _VoiceModePanelState extends State<VoiceModePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _scale = CurvedAnimation(parent: _enter, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: Stack(
          children: [
            // Blurred, dimmed backdrop
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(color: Colors.black.withOpacity(0.55)),
              ),
            ),
            Center(
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.85, end: 1.0).animate(_scale),
                child: Container(
                  width: math.min(MediaQuery.of(context).size.width - 40, 420),
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1B1F2A).withOpacity(0.96),
                        const Color(0xFF10131B).withOpacity(0.96),
                      ],
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.25),
                        blurRadius: 60,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Listening label
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF5F6D),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Listening…',
                            style: GoogleFonts.inter(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // REAL microphone waveform
                      RepaintBoundary(
                        child: LiveAmplitudeWaveform(
                          amplitudeStream: widget.amplitudeStream,
                          height: 96,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Timer — only this text rebuilds each second
                      ValueListenableBuilder<int>(
                        valueListenable: widget.elapsed,
                        builder: (_, seconds, __) => Text(
                          _fmt(seconds),
                          style: GoogleFonts.robotoMono(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Live transcript
                      ValueListenableBuilder<String>(
                        valueListenable: widget.transcript,
                        builder: (_, text, __) => AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            key: ValueKey(text.isEmpty),
                            constraints: const BoxConstraints(minHeight: 48),
                            alignment: Alignment.center,
                            child: Text(
                              text.isEmpty ? 'Start speaking…' : text,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: text.isEmpty
                                    ? Colors.white.withOpacity(0.4)
                                    : Colors.white.withOpacity(0.92),
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _circleAction(
                            icon: Icons.close_rounded,
                            color: Colors.white.withOpacity(0.12),
                            iconColor: Colors.white70,
                            size: 54,
                            onTap: widget.onCancel,
                            tooltip: 'Cancel',
                          ),
                          _circleAction(
                            icon: Icons.stop_rounded,
                            color: const Color(0xFF6C63FF),
                            iconColor: Colors.white,
                            size: 68,
                            onTap: widget.onStop,
                            tooltip: 'Send',
                            glow: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleAction({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required double size,
    required VoidCallback onTap,
    required String tooltip,
    bool glow = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: glow
                ? [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 24,
                spreadRadius: 2,
              )
            ]
                : null,
          ),
          child: Icon(icon, color: iconColor, size: size * 0.42),
        ),
      ),
    );
  }
}

/// Waveform driven by the REAL microphone amplitude stream.
/// Keeps a rolling history buffer and repaints only itself.
class LiveAmplitudeWaveform extends StatefulWidget {
  final Stream<double> amplitudeStream;
  final double height;
  final int barCount;

  const LiveAmplitudeWaveform({
    super.key,
    required this.amplitudeStream,
    this.height = 90,
    this.barCount = 42,
  });

  @override
  State<LiveAmplitudeWaveform> createState() => _LiveAmplitudeWaveformState();
}

class _LiveAmplitudeWaveformState extends State<LiveAmplitudeWaveform>
    with SingleTickerProviderStateMixin {
  late final List<double> _levels;
  late final AnimationController _ticker;
  StreamSubscription<double>? _sub;
  double _target = 0.0;
  double _current = 0.0;

  @override
  void initState() {
    super.initState();
    _levels = List<double>.filled(widget.barCount, 0.02, growable: false);
    _sub = widget.amplitudeStream.listen((v) => _target = v);
    // A single 60fps ticker smooths the ~16Hz amplitude callbacks.
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _ticker.addListener(_onTick);
  }

  void _onTick() {
    // Exponential smoothing → organic, non-jittery motion.
    _current += (_target - _current) * 0.28;
    for (int i = 0; i < _levels.length - 1; i++) {
      _levels[i] = _levels[i + 1];
    }
    _levels[_levels.length - 1] = _current.clamp(0.02, 1.0);
  }

  @override
  void dispose() {
    _ticker.removeListener(_onTick);
    _ticker.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (_, __) => CustomPaint(
          painter: _LiveWavePainter(levels: _levels),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _LiveWavePainter extends CustomPainter {
  final List<double> levels;
  _LiveWavePainter({required this.levels});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final barCount = levels.length;
    final slot = size.width / barCount;
    final barWidth = slot * 0.5;

    for (int i = 0; i < barCount; i++) {
      final level = levels[i];
      // Center bars are taller for a natural "voice bloom" shape.
      final positional =
          0.55 + 0.45 * math.sin((i / (barCount - 1)) * math.pi);
      final h = (level * positional * size.height).clamp(4.0, size.height);
      final x = i * slot + (slot - barWidth) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, centerY - h / 2, barWidth, h),
        Radius.circular(barWidth),
      );

      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8B7BFF), Color(0xFF4ED8C4)],
        ).createShader(Rect.fromLTWH(x, centerY - h / 2, barWidth, h));

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveWavePainter oldDelegate) => true;
}

/// Voice message bubble player: play/pause, seekable progress, duration and a
/// deterministic waveform thumbnail derived from the message id.
class VoiceMessagePlayer extends StatefulWidget {
  final String messageId;
  final String filePath;
  final String? fallbackDuration;
  final int? seconds;

  const VoiceMessagePlayer({
    super.key,
    required this.messageId,
    required this.filePath,
    this.fallbackDuration,
    this.seconds,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription> _subs = [];

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final List<double> _bars;

  @override
  void initState() {
    super.initState();
    _bars = _barsFor(widget.messageId);
    if (widget.seconds != null) {
      _duration = Duration(seconds: widget.seconds!);
    }
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _isPlaying = s == PlayerState.playing);
    }));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (!mounted || d == Duration.zero) return;
      setState(() => _duration = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    }));
  }

  /// Stable pseudo-waveform so the same message always looks the same.
  List<double> _barsFor(String id) {
    final rnd = math.Random(id.hashCode);
    return List<double>.generate(
      28,
          (i) => 0.25 + rnd.nextDouble() * 0.75,
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_position > Duration.zero && _position < _duration) {
        await _player.resume();
      } else {
        await _player.play(DeviceFileSource(widget.filePath));
      }
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1;
    final progress = (_position.inMilliseconds / total).clamp(0.0, 1.0);

    return SizedBox(
      width: 250,
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Seekable waveform
                LayoutBuilder(
                  builder: (context, c) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      final ratio = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
                      _player.seek(Duration(milliseconds: (total * ratio).round()));
                    },
                    onHorizontalDragUpdate: (d) {
                      final ratio = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
                      _player.seek(Duration(milliseconds: (total * ratio).round()));
                    },
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size(c.maxWidth, 28),
                        painter: _PlaybackWavePainter(
                          bars: _bars,
                          progress: progress,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _duration == Duration.zero
                      ? (widget.fallbackDuration ?? '0:00')
                      : '${_fmt(_position)} / ${_fmt(_duration)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackWavePainter extends CustomPainter {
  final List<double> bars;
  final double progress;

  _PlaybackWavePainter({required this.bars, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / bars.length;
    final barWidth = slot * 0.55;
    final centerY = size.height / 2;
    final playedUntil = size.width * progress;

    for (int i = 0; i < bars.length; i++) {
      final h = (bars[i] * size.height).clamp(3.0, size.height);
      final x = i * slot + (slot - barWidth) / 2;
      final played = x <= playedUntil;

      final paint = Paint()
        ..color = played
            ? Colors.white
            : Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY - h / 2, barWidth, h),
          Radius.circular(barWidth),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlaybackWavePainter old) =>
      old.progress != progress;
}
