import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified session management — single source of truth for all auth state.
/// FIXES BUG-16 (dual singletons), BUG-19 (no JWT expiry check).
class SessionManager {
  static const String _sessionIdKey = 'session_id';
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';
  static const String _userEmailKey = 'user_email';
  static const String _profilePhotoKey = 'profile_photo';
  static const String _loggedInKey = 'is_logged_in';
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _isGoogleUserKey = 'is_google_user';
  static const String _isGuestKey = 'is_guest';

  // ===========================================================
  // SESSION ID
  // ===========================================================

  static Future<String> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    String? sessionId = prefs.getString(_sessionIdKey);
    if (sessionId == null) {
      sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString(_sessionIdKey, sessionId);
    }
    return sessionId;
  }

  // ===========================================================
  // USER PROFILE
  // ===========================================================

  static Future<void> saveUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, userId);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  static Future<void> saveUserProfile({
    required int userId,
    required String name,
    required String email,
    String? profilePhoto,
    bool isGoogleUser = false,
    bool isGuest = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, userId);
    await prefs.setString(_userNameKey, name);
    await prefs.setString(_userEmailKey, email);
    if (profilePhoto != null) await prefs.setString(_profilePhotoKey, profilePhoto);
    await prefs.setBool(_isGoogleUserKey, isGoogleUser);
    await prefs.setBool(_isGuestKey, isGuest);
  }

  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userEmailKey);
  }

  static Future<String?> getProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_profilePhotoKey);
  }

  static Future<bool> getIsGoogleUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isGoogleUserKey) ?? false;
  }

  static Future<bool> getIsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isGuestKey) ?? false;
  }

  // ===========================================================
  // JWT TOKENS
  // ===========================================================

  static Future<void> saveTokens(String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  // ===========================================================
  // JWT EXPIRY CHECK (BUG-19 FIX)
  // ===========================================================

  /// Decodes a JWT token and returns its payload WITHOUT verifying the signature.
  /// Signature verification is the server's job. We use this to check `exp` locally.
  static Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // JWT uses Base64URL encoding — add padding
      String payload = parts[1];
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64.decode(payload));
      return json.decode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Returns true if the access token is expired or malformed.
  static Future<bool> isAccessTokenExpired() async {
    final token = await getAccessToken();
    if (token == null || token.isEmpty) return true;

    final payload = _decodeJwtPayload(token);
    if (payload == null) return true;

    final exp = payload['exp'];
    if (exp == null) return false; // No expiry = never expires

    final expiryTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    // Consider expired if less than 60 seconds remaining
    return DateTime.now().isAfter(expiryTime.subtract(const Duration(seconds: 60)));
  }

  /// Returns true if a refresh token exists and is not expired.
  static Future<bool> canRefreshToken() async {
    final token = await getRefreshToken();
    if (token == null || token.isEmpty) return false;

    final payload = _decodeJwtPayload(token);
    if (payload == null) return false;

    final exp = payload['exp'];
    if (exp == null) return true;

    final expiryTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return DateTime.now().isBefore(expiryTime);
  }

  // ===========================================================
  // LOGIN STATE
  // ===========================================================

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, value);
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  // ===========================================================
  // LOGOUT — ONLY CLEARS AUTH STATE (preserves chat cache)
  // ===========================================================

  /// FIXES BUG-02/BUG-03: Clears ONLY auth-related keys.
  /// Local chat history in SharedPreferences is preserved so it's available
  /// immediately after re-login without waiting for a backend sync.
  static Future<void> clearAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionIdKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_profilePhotoKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_isGoogleUserKey);
    await prefs.remove(_isGuestKey);
    await prefs.setBool(_loggedInKey, false);
    // NOTE: chat_history key is intentionally NOT removed here.
  }

  /// Full clear — removes everything including chat history.
  /// Use only for "Clear All Data" in settings, not for logout.
  static Future<void> clearEverything() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // ===========================================================
  // DEPRECATED — kept for backward compatibility with ChatStorageService
  // ===========================================================

  /// @deprecated Use clearAuthState() instead.
  static Future<void> clearSession() => clearAuthState();
}
