import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/models.dart';

class AuthState {
  final AppUser? user;
  final bool isLoading;

  const AuthState({this.user, this.isLoading = false});

  bool get isLoggedIn => user != null;
  String get role => user?.role ?? '';
  bool get isAdmin => role == 'admin';

  AuthState copyWith({AppUser? user, bool? isLoading}) => AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return const AuthState();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    final name = prefs.getString('name');
    final email = prefs.getString('email');
    if (role != null && name != null) {
      state = AuthState(user: AppUser(
        name: name,
        email: email ?? '',
        role: role,
        initials: _initials(name),
      ));
    }
  }

  Future<void> login(String name, String email, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role', role);
    await prefs.setString('name', name);
    await prefs.setString('email', email);
    state = AuthState(user: AppUser(
      name: name,
      email: email,
      role: role,
      initials: _initials(name),
    ));
  }

  Future<void> switchRole(String role) async {
    if (state.user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role', role);
    state = AuthState(user: AppUser(
      name: state.user!.name,
      email: state.user!.email,
      role: role,
      initials: state.user!.initials,
    ));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('role');
    await prefs.remove('name');
    await prefs.remove('email');
    state = const AuthState();
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
