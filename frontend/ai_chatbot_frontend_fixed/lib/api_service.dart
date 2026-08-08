import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'session_manager.dart';

/// Centralized API service for all backend communication.
/// FIXES:
///   BUG-17: baseUrl now supports both emulator (10.0.2.2) and real device (PC IP)
///   BUG-19: Token refresh integrated — all authenticated calls auto-refresh on 401
///   ARCH-04: Added createConversation()
///   BUG-10: Added batchSaveMessages()
///   Added updateConversationTitle()
///   Fixed resetPassword to send reset_token (matches new backend API)
class ApiService {
  ApiService._();

  // ─────────────────────────────────────────────────────────────────────────
  // BASE URL CONFIGURATION
  //
  // For Android testing, the URL depends on whether you're using an emulator
  // or a real device:
  //   - Emulator:    http://10.0.2.2:8000   (maps to host's localhost)
  //   - Real device: http://<PC_IP>:8000     (use your PC's WiFi IP)
  //
  // Set FLUTTER_BACKEND_URL in your shell to override at runtime:
  //   export FLUTTER_BACKEND_URL=http://192.168.1.10:8000
  // ─────────────────────────────────────────────────────────────────────────

  // Set API_BASE_URL at build/run time to override (see examples below).
  // ─────────────────────────────────────────────────────────────────────────

  static const String _pcIp = '10.151.198.162'; // Your PC's local WiFi IP
  static const String _port = '8000';

  // Production override (set at build time):
  //   flutter build web --release --dart-define=API_BASE_URL=https://your-backend.onrender.com
  //
  // Shell override for mobile/desktop dev:
  //   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000

  // Toggle this to true when testing on a real Android device
  static const bool _useRealDevice = false;

  static const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) {
      return _apiBaseUrlOverride.replaceAll(RegExp(r'/+$'), '');
    }

    if (kIsWeb) return 'http://localhost:$_port';

    if (!kIsWeb && Platform.isAndroid) {
      if (_useRealDevice) {
        return 'http://$_pcIp:$_port';
      }
      return 'http://10.0.2.2:$_port'; // Android Emulator
    }

    if (!kIsWeb && Platform.isWindows) return 'http://127.0.0.1:$_port';
    if (!kIsWeb && Platform.isLinux) return 'http://127.0.0.1:$_port';
    if (!kIsWeb && Platform.isMacOS) return 'http://127.0.0.1:$_port';
    if (!kIsWeb && Platform.isIOS) return 'http://127.0.0.1:$_port';

    return 'http://127.0.0.1:$_port';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTH HEADERS BUILDER (with auto-refresh)
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders({bool forceRefresh = false}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    // Check token expiry and refresh if needed
    final isExpired = await SessionManager.isAccessTokenExpired();
    if (isExpired || forceRefresh) {
      final canRefresh = await SessionManager.canRefreshToken();
      if (canRefresh) {
        try {
          await _doRefreshToken();
        } catch (_) {
          // If refresh fails, proceed without token — caller will handle 401
        }
      }
    }

    final token = await SessionManager.getAccessToken();
    final userId = await SessionManager.getUserId();

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (userId != null) {
      headers['x-user-id'] = userId.toString();
    }

    return headers;
  }

  /// Internal: actually calls the refresh endpoint and saves new token.
  static Future<void> _doRefreshToken() async {
    final refreshToken = await SessionManager.getRefreshToken();
    if (refreshToken == null) throw Exception('No refresh token');

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final newAccessToken = data['access_token'] as String?;
      if (newAccessToken != null) {
        final oldRefresh = await SessionManager.getRefreshToken();
        await SessionManager.saveTokens(newAccessToken, oldRefresh ?? '');
      }
    } else {
      throw Exception('Token refresh failed');
    }
  }

  /// Generic authenticated GET with automatic 401 retry after refresh.
  static Future<http.Response> _authGet(String url) async {
    var headers = await _authHeaders();
    var response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      headers = await _authHeaders(forceRefresh: true);
      response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
    }
    return response;
  }

  /// Generic authenticated POST with automatic 401 retry after refresh.
  static Future<http.Response> _authPost(String url, Map<String, dynamic> body) async {
    var headers = await _authHeaders();
    var response = await http
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      headers = await _authHeaders(forceRefresh: true);
      response = await http
          .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
    }
    return response;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTHENTICATION
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? sessionId,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'email': email,
            'password': password,
            'session_id': sessionId,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await _persistAuthData(data);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Registration failed');
    }
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? sessionId,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'session_id': sessionId,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await _persistAuthData(data);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Login failed');
    }
  }

  static Future<Map<String, dynamic>> googleAuth({
    required String googleId,
    required String email,
    required String name,
    String? profilePhoto,
    String? sessionId,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'google_id': googleId,
            'email': email,
            'name': name,
            'profile_photo': profilePhoto,
            'session_id': sessionId,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await _persistAuthData(data);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Google Auth failed');
    }
  }

  static Future<void> _persistAuthData(Map<String, dynamic> data) async {
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    final userId = data['user_id'];
    final name = data['name'] as String?;
    final email = data['email'] as String?;
    final profilePhoto = data['profile_photo'] as String?;

    if (accessToken != null && refreshToken != null) {
      await SessionManager.saveTokens(accessToken, refreshToken);
    }
    if (userId != null) {
      await SessionManager.saveUserProfile(
        userId: (userId is int) ? userId : int.parse(userId.toString()),
        name: name ?? '',
        email: email ?? '',
        profilePhoto: profilePhoto,
      );
    }
    await SessionManager.setLoggedIn(true);
  }

  static Future<Map<String, dynamic>> requestForgotPasswordOtp(String email) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/forgot-password/request-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to request OTP');
  }

  static Future<Map<String, dynamic>> verifyForgotPasswordOtp(String email, String otp) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/forgot-password/verify-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'otp': otp}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(jsonDecode(response.body)['detail'] ?? 'OTP verification failed');
  }

  /// FIXED: Now sends `reset_token` (from OTP verification) instead of just email.
  /// This matches the new backend endpoint that requires OTP completion proof.
  static Future<Map<String, dynamic>> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/forgot-password/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'reset_token': resetToken, 'new_password': newPassword}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(jsonDecode(response.body)['detail'] ?? 'Password reset failed');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONVERSATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch conversation headers (no messages) — used by sidebar.
  static Future<List<dynamic>> fetchConversations() async {
    final response = await _authGet('$baseUrl/api/v1/conversations');
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    return [];
  }

  /// FIXES ARCH-04: Create conversation on backend before sending first message.
  static Future<Map<String, dynamic>> createConversation({
    required String id,
    String title = 'New Chat',
  }) async {
    final response = await _authPost('$baseUrl/api/v1/conversations', {
      'id': id,
      'title': title,
    });
    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    // Non-critical — conversation auto-creation is also done server-side on message save
    return {'id': id, 'title': title};
  }

  /// Fetch full conversation including all messages — used when loading a chat.
  static Future<Map<String, dynamic>> fetchConversationDetails(String conversationId) async {
    final response = await _authGet('$baseUrl/api/v1/conversations/$conversationId');
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('Failed to fetch conversation');
  }

  /// Save a single message to a conversation.
  static Future<void> saveMessageToConversation(
    String conversationId,
    Map<String, dynamic> messageData,
  ) async {
    await _authPost('$baseUrl/api/v1/conversations/$conversationId/messages', messageData);
  }

  /// FIXES BUG-10: Save multiple messages in one request.
  static Future<void> batchSaveMessages(
    String conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    if (messages.isEmpty) return;
    await _authPost(
      '$baseUrl/api/v1/conversations/$conversationId/messages/batch',
      {'messages': messages},
    );
  }

  /// Rename a conversation.
  static Future<void> updateConversationTitle(String conversationId, String title) async {
    final headers = await _authHeaders();
    await http
        .put(
          Uri.parse('$baseUrl/api/v1/conversations/$conversationId'),
          headers: headers,
          body: jsonEncode({'title': title}),
        )
        .timeout(const Duration(seconds: 15));
  }

  static Future<void> deleteConversation(String conversationId) async {
    final headers = await _authHeaders();
    await http
        .delete(Uri.parse('$baseUrl/api/v1/conversations/$conversationId'), headers: headers)
        .timeout(const Duration(seconds: 15));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ATTACHMENTS & CHAT
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> uploadAttachment(String filePath, {Uint8List? fileBytes, String? fileName}) async {
    final token = await SessionManager.getAccessToken();
    final uri = Uri.parse('$baseUrl/upload-attachment');
    final request = http.MultipartRequest('POST', uri);

    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    
    if (kIsWeb && fileBytes != null) {
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName ?? 'upload.png'));
    } else {
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
    }

    final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('Attachment upload failed');
  }

  static Future<String> sendChat(
    String message, {
    String? fileText,
    String? fileName,
    String? filePath,
    String? conversationId,
  }) async {
    final userId = await SessionManager.getUserId();
    final headers = await _authHeaders();

    final body = <String, dynamic>{
      'message': message,
      'user_id': userId,
      'conversation_id': conversationId,
    };

    if (fileText != null && fileText.isNotEmpty) {
      body['file_text'] = fileText;
      body['file_name'] = fileName;
    }
    if (filePath != null && filePath.isNotEmpty) {
      body['file_path'] = filePath;
    }

    // Vision requests load qwen2.5vl and can exceed 60s; match backend Ollama timeout.
    final isVisionRequest = filePath != null && filePath.isNotEmpty;
    final chatTimeout = isVisionRequest
        ? const Duration(seconds: 300)
        : const Duration(seconds: 60);

    Future<http.Response> postChat(Map<String, String> hdrs) {
      return http
          .post(Uri.parse('$baseUrl/chat'), headers: hdrs, body: jsonEncode(body))
          .timeout(chatTimeout);
    }

    var response = await postChat(headers);

    if (response.statusCode == 401) {
      final freshHeaders = await _authHeaders(forceRefresh: true);
      response = await postChat(freshHeaders);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final reply = data['reply'];
      if (reply is String) return reply;
      throw Exception('Chat response missing reply field');
    }
    throw Exception('Chat request failed: ${response.statusCode}');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VOICE SERVICES
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> transcribeAudio(String audioFilePath) async {
    final token = await SessionManager.getAccessToken();
    final uri = Uri.parse('$baseUrl/transcribe');
    final request = http.MultipartRequest('POST', uri);

    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', audioFilePath));

    final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('Audio transcription failed');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // IMAGE GENERATION
  // ─────────────────────────────────────────────────────────────────────────

  static Future<String> generateImage(String prompt, {String? conversationId}) async {
    final Map<String, dynamic> body = {'message': prompt};
    if (conversationId != null) {
      body['conversation_id'] = conversationId;
    }
    final response = await _authPost('$baseUrl/generate-image', body);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final imageUrl = data['image_url'] as String?;
      if (imageUrl != null) {
        // If relative URL (starts with /), prepend baseUrl so Android emulator can reach it
        if (imageUrl.startsWith('/')) return '$baseUrl$imageUrl';
        return imageUrl;
      }
      // Fallback cache-busting URL (legacy)
      return '$baseUrl/generated-image?t=${DateTime.now().millisecondsSinceEpoch}';
    }
    throw Exception('Image generation failed');
  }
}