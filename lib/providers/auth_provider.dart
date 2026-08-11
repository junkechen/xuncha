// lib/providers/auth_provider.dart
// 认证状态管理 - 腾讯云CloudBase集成版

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/user.dart';
import '../services/cloudbase_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  List<User> _localUsers = [];
  SharedPreferences? _prefs;

  // 腾讯云CloudBase配置统一从 constants.dart 读取
  static String get apiBaseUrl => AppConstants.cloudBaseApiUrl;
  static const String _publishableKey = 'eyJhbGciOiJSUzI1NiIsImtpZCI6IjlkMWRjMzFlLWI0ZDAtNDQ4Yi1hNzZmLWIwY2M2M2Q4MTQ5OCJ9.eyJpc3MiOiJodHRwczovL2FudWFuYnUxLTEtNmdqcWF5ZHdkMDY3ZGJiMS5hcC1zaGFuZ2hhaS50Y2ItYXBpLnRlbmNlbnRjbG91ZGFwaS5jb20iLCJzdWIiOiJhbm9uIiwiYXVkIjoiYW51YW5idTEtMS02Z2pxYXlkd2QwNjdkYmIxIiwiZXhwIjo0MDc5ODQwODY0LCJpYXQiOjE3NzYxNTc2NjQsIm5vbmNlIjoiUEE2em4wcnpUVlNCTDFHYi1zQWhpQSIsImF0X2hhc2giOiJQQTZ6bjByelRWU0JMMUdiLXNBaGlBIiwibmFtZSI6IkFub255bW91cyIsInNjb3BlIjoiYW5vbnltb3VzIiwicHJvamVjdF9pZCI6ImFudWFuYnUxLTEtNmdqcWF5ZHdkMDY3ZGJiMSIsIm1ldGEiOnsicGxhdGZvcm0iOiJQdWJsaXNoYWJsZUtleSJ9LCJ1c2VyX3R5cGUiOiIiLCJjbGllbnRfdHlwZSI6ImNsaWVudF91c2VyIiwiaXNfc3lzdGVtX2FkbWluIjpmYWxzZX0.mUlPQJg_VdB5TX61qQ9trqBKm721Vy75WesEXnpExNlLXwRubzS8I4vPz2YeeWyeBWNzSIyJYst87gr1VUdk6RewP1qRBQPrVNKKoaLDfswfyaK_5DJQs3bl-C6wuTTzz9K5JBhVqhsrHBnZjRNP-_FM2tFcv4xGgIt61YAXfXGEL5-9COpv6KuqvrWA7rYDe-bnrpM8yShdRcjJEVKawyk40_Xi8TnNbPIznqj_9MvOkVxKT4-ZvQC4jZZPMHSYVw6fz77rUL6bFV2pPgVYRosnhDiK0aXNHnUdChe9oLztWW2zvOx2tN2YUQjq_x50WqxvNEb-hZ6o4S7N4jckMw';

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAdmin => _currentUser?.role == UserRole.admin;

  /// 是否有保存的登录信息（用于后台保活检测）
  bool get hasSavedLogin {
    final username = _prefs?.getString('saved_login_username');
    final password = _prefs?.getString('saved_login_password');
    return username != null && username.isNotEmpty && password != null && password.isNotEmpty;
  }

  /// 恢复登录状态（用于后台保活）
  Future<bool> restoreLogin() async {
    if (_currentUser != null) return true; // 已经登录

    final savedUsername = _prefs?.getString('saved_login_username');
    final savedPassword = _prefs?.getString('saved_login_password');

    if (savedUsername == null || savedPassword == null) {
      print('📱 没有保存的登录信息');
      return false;
    }

    print('📱 正在恢复登录状态: $savedUsername');

    // 尝试从本地用户列表中找到匹配的用户
    try {
      final localUser = _localUsers.firstWhere(
        (u) => u.username == savedUsername && u.password == savedPassword && (u.isActive ?? true),
        orElse: () => User(id: '', username: '', password: '', name: '', phone: '', department: '', role: ''),
      );
      if (localUser.username.isNotEmpty) {
        _currentUser = localUser;
        notifyListeners();
        print('📱 本地会话恢复成功: ${localUser.name}');
        return true;
      }
    } catch (e) {
      print('📱 本地用户查找失败: $e');
    }

    // 本地没有，尝试从云端获取
    try {
      final cloudUser = await _fetchUserFromCloudBase(savedUsername);
      // 修复：isActive 为 null 时默认视为 true（兼容旧数据），避免因字段缺失误退出
      final isActive = cloudUser?.isActive ?? true;
      if (cloudUser != null && cloudUser.password == savedPassword && isActive) {
        _currentUser = cloudUser;
        // 更新本地用户列表
        final index = _localUsers.indexWhere((u) => u.id == cloudUser.id);
        if (index >= 0) {
          _localUsers[index] = cloudUser;
        }
        notifyListeners();
        print('📱 云端会话恢复成功: ${cloudUser.name}');
        return true;
      }
      // 云端找到用户但密码/状态不匹配，尝试本地（避免网络抖动导致退出）
      if (cloudUser == null) {
        // 云端查不到（网络问题），回退到本地验证
        try {
          final localUser = _localUsers.firstWhere(
            (u) => u.username == savedUsername && u.password == savedPassword,
            orElse: () => User(id: '', username: '', password: '', name: '', phone: '', department: '', role: ''),
          );
          if (localUser.username.isNotEmpty) {
            _currentUser = localUser;
            notifyListeners();
            print('📱 网络异常，使用本地缓存恢复登录: ${localUser.name}');
            return true;
          }
        } catch (_) {}
      }
    } catch (e) {
      print('📱 云端会话恢复失败: $e');
      // 网络异常时，回退本地验证而不是直接返回 false
      try {
        final localUser = _localUsers.firstWhere(
          (u) => u.username == savedUsername && u.password == savedPassword,
          orElse: () => User(id: '', username: '', password: '', name: '', phone: '', department: '', role: ''),
        );
        if (localUser.username.isNotEmpty) {
          _currentUser = localUser;
          notifyListeners();
          print('📱 网络异常，使用本地缓存恢复登录: ${localUser.name}');
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  AuthProvider() {
    _initServices();
  }

  Future<void> _initServices() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadLocalUsers();

    // 恢复登录会话
    final savedUsername = _prefs?.getString('saved_login_username');
    final savedPassword = _prefs?.getString('saved_login_password');
    if (savedUsername != null && savedUsername.isNotEmpty && savedPassword != null) {
      print('📱 尝试恢复登录会话: $savedUsername');
      // 静默登录：尝试云端验证
      try {
        final cloudUser = await _fetchUserFromCloudBase(savedUsername);
        // isActive 为 null 时默认视为 true（兼容旧数据）
        final isActive = cloudUser?.isActive ?? true;
        if (cloudUser != null && cloudUser.password == savedPassword && isActive) {
          _currentUser = cloudUser;
          print('📱 云端会话恢复成功: ${cloudUser.name}');
          notifyListeners(); // 修复：恢复后通知UI更新，避免显示登录页
        } else if (cloudUser == null) {
          // 云端查不到（网络问题），回退本地
          final localUser = _localUsers.firstWhere(
            (u) => u.username == savedUsername && u.password == savedPassword && (u.isActive ?? true),
            orElse: () => User(id: '', username: '', password: '', name: '', phone: '', department: '', role: ''),
          );
          if (localUser.username.isNotEmpty) {
            _currentUser = localUser;
            print('📱 网络不可用，使用本地缓存恢复登录: ${localUser.name}');
            notifyListeners(); // 修复：恢复后通知UI更新
          }
        }
      } catch (e) {
        print('📱 云端会话恢复异常($e)，尝试本地验证...');
        // 网络异常，回退本地
        final localUser = _localUsers.firstWhere(
          (u) => u.username == savedUsername && u.password == savedPassword && (u.isActive ?? true),
          orElse: () => User(id: '', username: '', password: '', name: '', phone: '', department: '', role: ''),
        );
        if (localUser.username.isNotEmpty) {
          _currentUser = localUser;
          print('📱 本地会话恢复成功: ${localUser.name}');
          notifyListeners(); // 修复：恢复后通知UI更新
        }
      }
    }

    if (_localUsers.isEmpty) {
      // 本地为空，尝试从云端同步用户
      print('📱 本地用户为空，尝试从云端同步...');
      await _syncUsersFromCloud();
      
      // 云端同步后仍然为空，才创建默认admin
      if (_localUsers.isEmpty) {
        print('📱 云端同步失败，创建默认admin用户');
        await _addDefaultUsers();
        // 同时同步admin到云端
        await _syncAdminToCloud();
      }
    } else {
      // 本地有用户，检查是否需要同步admin到云端
      if (!_localUsers.any((u) => u.username == 'admin')) {
        print('📱 本地缺少admin，创建并同步到云端');
        await _addDefaultUsers();
        await _syncAdminToCloud();
      }
    }
  }

  /// 将admin用户同步到云端
  Future<void> _syncAdminToCloud() async {
    try {
      final adminUser = _localUsers.firstWhere((u) => u.username == 'admin');
      
      final response = await http.post(
        Uri.parse(apiBaseUrl),
        headers: AppConstants.cloudBaseHeaders,
        body: jsonEncode({
          'action': 'add',
          'collection': 'users',
          'data': {
            'id': adminUser.id,
            'username': adminUser.username,
            'password': adminUser.password,
            'name': adminUser.name,
            'phone': adminUser.phone,
            'role': adminUser.role.name,
            'department': adminUser.department,
            'status': adminUser.status,
            'isActive': adminUser.isActive,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          print('✅ admin用户已同步到云端');
        } else {
          print('⚠️ admin同步到云端失败: ${data['message']}');
        }
      }
    } catch (e) {
      print('❌ admin同步到云端异常: $e');
    }
  }

  /// 从云端同步所有用户到本地
  Future<void> _syncUsersFromCloud() async {
    try {
      final response = await http.post(
        Uri.parse(apiBaseUrl),
        headers: AppConstants.cloudBaseHeaders,
        body: jsonEncode({
          'action': 'query',
          'collection': 'users',
          'query': {},
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('📥 云端用户同步响应: code=${data['code']}');
        
        List<dynamic>? cloudUsers;
        if (data['data'] != null) {
          cloudUsers = data['data'] as List;
        } else if (data['result'] != null && data['result']['data'] != null) {
          cloudUsers = data['result']['data'] as List;
        }
        
        if (cloudUsers != null && cloudUsers.isNotEmpty) {
          // 过滤出有效用户（有username和password的用户）
          final validUsers = cloudUsers.where((u) => 
            u['username'] != null && 
            u['username'].toString().isNotEmpty &&
            u['password'] != null
          ).toList();
          
          print('📥 云端有效用户: ${validUsers.length} 个');
          
          _localUsers = validUsers.map((u) => User(
            id: u['_id'] ?? u['id'] ?? '',
            username: u['username']?.toString() ?? '',
            password: u['password']?.toString() ?? '',
            name: u['name']?.toString() ?? '',
            phone: u['phone']?.toString() ?? '',
            department: u['department']?.toString() ?? '',
            role: u['role']?.toString() ?? 'inspector',
            status: u['status']?.toString() ?? 'active',
            isActive: u['isActive'] ?? true,
          )).toList();
          
          // 如果没有admin用户，添加默认admin
          if (!_localUsers.any((u) => u.username == 'admin')) {
            print('📥 云端无admin用户，添加本地admin');
            await _addDefaultUsers();
            await _syncAdminToCloud();
          }
          
          await _saveLocalUsers();
          print('✅ 云端同步成功，共 ${_localUsers.length} 个用户');
          notifyListeners();
        } else {
          print('⚠️ 云端用户列表为空');
        }
      }
    } catch (e) {
      print('❌ 云端用户同步失败: $e');
    }
  }

  Future<void> _loadLocalUsers() async {
    final usersJson = _prefs?.getString('local_users');
    if (usersJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(usersJson);
        _localUsers = decoded.map((e) => User.fromJson(e)).toList();
      } catch (e) {
        print('加载本地用户失败: $e');
      }
    }
  }

  Future<void> _saveLocalUsers() async {
    final usersJson = jsonEncode(_localUsers.map((e) => e.toJson()).toList());
    await _prefs?.setString('local_users', usersJson);
  }

  Future<void> _addDefaultUsers() async {
    _localUsers = [
      User(
        id: 'user_admin_001',
        username: 'admin',
        password: 'admin123',
        name: '系统管理员',
        phone: '15194007893',
        role: 'admin',
        department: '节能环保安全保卫部',
        status: 'active',
        isActive: true,
      ),
    ];
    await _saveLocalUsers();
  }

  /// 从腾讯云数据库查询用户（通过云函数API）
  Future<User?> _fetchUserFromCloudBase(String username) async {
    try {
      final response = await http.post(
        Uri.parse(apiBaseUrl),
        headers: AppConstants.cloudBaseHeaders,
        body: jsonEncode({
          'action': 'query',
          'collection': 'users',
          'query': {'username': username},
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null && data['data'].isNotEmpty) {
          final userData = data['data'][0];
          return User(
            id: userData['_id'] ?? '',
            username: userData['username'] ?? username,
            password: userData['password'] ?? '',
            name: userData['name'] ?? '',
            phone: userData['phone'] ?? '',
            role: userData['role'] ?? 'user',
            department: userData['department'] ?? '',
            status: userData['status'] ?? 'active',
            isActive: userData['isActive'] ?? true,
          );
        }
      }
      return null;
    } catch (e) {
      print('腾讯云查询失败: $e');
      return null;
    }
  }

  /// 检查用户名是否已存在
  Future<bool> _checkUserExists(String username) async {
    try {
      final response = await http.post(
        Uri.parse(apiBaseUrl),
        headers: AppConstants.cloudBaseHeaders,
        body: jsonEncode({
          'action': 'query',
          'collection': 'users',
          'query': {'username': username},
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null && data['data'].isNotEmpty) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 添加用户到腾讯云数据库
  Future<bool> _addUserToCloudBase(User user) async {
    try {
      final response = await http.post(
        Uri.parse(apiBaseUrl),
        headers: AppConstants.cloudBaseHeaders,
        body: jsonEncode({
          'action': 'add',
          'collection': 'users',
          'data': {
            'username': user.username,
            'password': user.password,
            'name': user.name,
            'phone': user.phone,
            'role': user.role.name,  // 关键：用.name获取字符串值，如"inspector"
            'department': user.department,
            'status': user.status,
            'isActive': user.isActive,
            'createdAt': DateTime.now().toIso8601String().split('T')[0],
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ 腾讯云添加用户成功: ${user.username}');
        return data['code'] == 0;
      }
      print('❌ 腾讯云响应异常: ${response.statusCode}');
      return false;
    } catch (e) {
      print('添加用户到腾讯云失败: $e');
      return false;
    }
  }

  /// 登录
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_prefs == null) {
        await _initServices();
      }

      // 优先从腾讯云验证
      final cloudUser = await _fetchUserFromCloudBase(username);
      if (cloudUser != null) {
        // 验证密码
        if (cloudUser.password.isEmpty) {
          // 如果腾讯云没有返回密码，使用本地验证
          final localUser = _localUsers.firstWhere(
            (u) => u.username == username && u.password == password,
            orElse: () => User(id: '', username: '', password: '', name: '', phone: '', department: '', role: ''),
          );
          if (localUser.username.isEmpty) {
            _error = '用户名或密码错误';
            _isLoading = false;
            notifyListeners();
            return false;
          }
          _currentUser = localUser;
        } else if (cloudUser.password == password) {
          _currentUser = cloudUser;
        } else {
          _error = '用户名或密码错误';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        // 保存登录会话（切后台后恢复）
        await _prefs?.setString('saved_login_username', username);
        await _prefs?.setString('saved_login_password', password);

        _isLoading = false;
        notifyListeners();
        return true;
      }

      // 腾讯云连接失败，使用本地验证
      User? foundUser;
      for (final u in _localUsers) {
        if (u.username == username && u.password == password) {
          foundUser = u;
          break;
        }
      }

      if (foundUser != null) {
        if (!foundUser.isActive!) {
          _error = '账号已被禁用，请联系管理员';
          _isLoading = false;
          notifyListeners();
          return false;
        }
        _currentUser = foundUser;
        await _prefs?.setString('saved_login_username', username);
        await _prefs?.setString('saved_login_password', password);
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _error = '用户名或密码错误';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      // 网络错误时使用本地验证
      User? foundUser;
      for (final u in _localUsers) {
        if (u.username == username && u.password == password) {
          foundUser = u;
          break;
        }
      }

      if (foundUser != null) {
        _currentUser = foundUser;
        await _prefs?.setString('saved_login_username', username);
        await _prefs?.setString('saved_login_password', password);
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _error = '用户名或密码错误';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String password,
    required String name,
    required String phone,
    required String department,
    required String role,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 先检查腾讯云是否已有该用户名
      final existsInCloud = await _checkUserExists(username);
      if (existsInCloud) {
        _error = '用户名已存在';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 检查本地是否已有
      if (_localUsers.any((u) => u.username == username)) {
        _error = '用户名已存在';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 创建新用户对象
      final newUser = User(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        username: username,
        password: password,
        name: name,
        phone: phone,
        role: role,
        department: department,
        status: 'pending',
        isActive: false,
      );

      // 同时保存到腾讯云和本地
      final cloudSuccess = await _addUserToCloudBase(newUser);
      
      if (cloudSuccess) {
        // 腾讯云保存成功
        _localUsers.add(newUser);
        await _saveLocalUsers();
      } else {
        // 腾讯云保存失败，只保存本地
        _localUsers.add(newUser);
        await _saveLocalUsers();
        print('警告: 腾讯云保存失败，仅本地保存成功');
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // 网络错误时仍保存本地
      if (_localUsers.any((u) => u.username == username)) {
        _error = '用户名已存在';
      } else {
        final newUser = User(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          username: username,
          password: password,
          name: name,
          phone: phone,
          role: role,
          department: department,
          status: 'pending',
          isActive: false,
        );
        _localUsers.add(newUser);
        await _saveLocalUsers();
      }
      _error = '注册失败: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 获取待审核用户列表 - 从腾讯云获取 + 合并本地pending用户
  Future<List<User>> getPendingUsers() async {
    final List<User> pendingUsers = [];
    
    // 1. 从腾讯云获取
    try {
      final response = await http.post(
        Uri.parse(apiBaseUrl),
        headers: AppConstants.cloudBaseHeaders,
        body: jsonEncode({
          'action': 'query',
          'collection': 'users',
          'query': {},
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null) {
          final cloudPending = (data['data'] as List)
              .where((u) => 
                  u['status'] == 'pending' || 
                  u['isActive'] == false || 
                  u['status'] == null || 
                  u['status'] == ''
              )
              .map((u) => User(
                    id: u['_id'] ?? '',
                    username: u['username'] ?? '',
                    password: u['password'] ?? '',
                    name: u['name'] ?? '',
                    phone: u['phone'] ?? '',
                    role: u['role'] ?? 'inspector',
                    department: u['department'] ?? '',
                    status: u['status'] ?? 'pending',
                    isActive: u['isActive'] ?? false,
                  ))
              .toList();
          
          // 排除admin用户
          cloudPending.removeWhere((u) => u.username == 'admin');
          
          pendingUsers.addAll(cloudPending);
          
          // 同步到本地
          for (var cloudUser in cloudPending) {
            if (!_localUsers.any((u) => u.username == cloudUser.username)) {
              _localUsers.add(cloudUser);
            }
          }
          await _saveLocalUsers();
          
          print('从云端获取到 ${cloudPending.length} 个待审核用户');
        }
      }
    } catch (e) {
      print('获取云端待审核用户失败: $e');
    }
    
    // 2. 合并本地待审核用户（云端可能因分页限制未返回所有用户）
    final localPending = _localUsers
        .where((u) => 
            u.username != 'admin' && 
            (u.status == 'pending' || !u.isActive) &&
            !pendingUsers.any((p) => p.username == u.username)
        )
        .toList();
    
    if (localPending.isNotEmpty) {
      print('合并 ${localPending.length} 个本地待审核用户');
      pendingUsers.addAll(localPending);
    }
    
    return pendingUsers;
  }

  List<User> getAllUsers() {
    return _localUsers.toList();
  }



  /// Fetch all users from cloud
  Future<List<User>> fetchAllUsersFromCloud() async {
    try {
      final response = await http.post(
        Uri.parse(apiBaseUrl),
        headers: AppConstants.cloudBaseHeaders,
        body: jsonEncode({
          'action': 'query',
          'collection': 'users',
          'query': {},
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('📥 fetchAllUsersFromCloud 响应: code=${data['code']}');
        
        List<dynamic>? cloudUsers;
        if (data['data'] != null) {
          cloudUsers = data['data'] as List;
        } else if (data['result'] != null && data['result']['data'] != null) {
          cloudUsers = data['result']['data'] as List;
        }
        
        if (cloudUsers != null && cloudUsers.isNotEmpty) {
          // 正确解析云端用户数据
          for (var u in cloudUsers) {
            final username = u['username']?.toString() ?? '';
            if (username.isEmpty) continue;
            
            final cloudUser = User(
              id: u['_id'] ?? u['id'] ?? '',
              username: username,
              password: u['password']?.toString() ?? '',
              name: u['name']?.toString() ?? '',
              phone: u['phone']?.toString() ?? '',
              department: u['department']?.toString() ?? '',
              role: u['role']?.toString() ?? 'inspector',
              status: u['status']?.toString() ?? 'active',
              isActive: u['isActive'] ?? true,
            );
            
            final localIndex = _localUsers.indexWhere((u) => u.username == username);
            if (localIndex == -1) {
              _localUsers.add(cloudUser);
            } else {
              _localUsers[localIndex] = cloudUser;
            }
          }
          
          print('✅ 从云端同步 ${cloudUsers.length} 个用户到本地');
        } else {
          print('⚠️ 云端用户列表为空');
        }
        
        await _saveLocalUsers();
        // 按姓名拼音/字母顺序排序，方便用户查找
        _localUsers.sort((a, b) => a.name.compareTo(b.name));
        notifyListeners();
        return _localUsers.toList();
      } else {
        print('❌ HTTP 错误: ${response.statusCode}');
      }
    } catch (e) {
      print('fetchAllUsersFromCloud error: ' + e.toString());
    }
    return _localUsers.toList();
  }

  Future<bool> addUser({
    required String username,
    required String password,
    required String name,
    required String phone,
    required String department,
    required String role,
  }) async {
    try {
      // 检查是否已存在
      final existsInCloud = await _checkUserExists(username);
      if (existsInCloud) {
        _error = '用户名已存在';
        notifyListeners();
        return false;
      }

      if (_localUsers.any((u) => u.username == username)) {
        _error = '用户名已存在';
        notifyListeners();
        return false;
      }

      final newUser = User(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        username: username,
        password: password,
        name: name,
        phone: phone,
        role: role,
        department: department,
        status: 'active',
        isActive: true,
      );

      // 同时保存到腾讯云
      final cloudSuccess = await _addUserToCloudBase(newUser);
      if (!cloudSuccess) {
        _error = '云端保存失败，请检查网络或腾讯云状态';
        notifyListeners();
        return false;
      }

      // 保存本地
      _localUsers.add(newUser);
      await _saveLocalUsers();
      notifyListeners();
      return true;
    } catch (e) {
      _error = '添加用户失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 批准用户
  Future<bool> approveUser(String username) async {
    try {
      print('🔄 正在批准用户: $username');
      
      // 更新本地
      final index = _localUsers.indexWhere((u) => u.username == username);
      if (index != -1) {
        _localUsers[index].status = 'active';
        _localUsers[index].isActive = true;
        await _saveLocalUsers();
      }

      // 同步更新到腾讯云 - query 和 data 作为独立参数传递
      final cloudService = CloudBaseService.instance;
      final result = await cloudService.callApi(
        'update',
        collection: 'users',
        query: {'username': username},
        data: {
          'status': 'active',
          'isActive': true,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
      print('📋 approveUser 云端结果: code=${result['code']}, msg=${result['message']}');
      
      notifyListeners();
      
      if (result['code'] == 0) {
        print('✅ 批准成功');
        return true;
      } else {
        print('⚠️ 云端更新失败，但本地已更新: ${result['message']}');
        return true;  // 本地已更新
      }
    } catch (e) {
      print('⚠️ 批准异常: $e');
      notifyListeners();
      return true;
    }
  }
  
  /// 获取用户的云端ID
  String? _getCloudUserId(String username) {
    final user = _localUsers.firstWhere(
      (u) => u.username == username,
      orElse: () => User(id: '', username: '', password: '', name: '', phone: '', role: '', department: ''),
    );
    return user.id.isNotEmpty ? user.id : null;
  }

  /// 拒绝用户（云端禁用，本地删除）
  Future<bool> rejectUser(String username) async {
    try {
      print('🔄 正在拒绝用户: $username');
      
      // 从本地删除
      _localUsers.removeWhere((u) => u.username == username);
      await _saveLocalUsers();

      // 同步更新到腾讯云 - query 和 data 作为独立参数传递
      final cloudService = CloudBaseService.instance;
      final result = await cloudService.callApi(
        'update',
        collection: 'users',
        query: {'username': username},
        data: {
          'status': 'disabled',
          'isActive': false,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
      print('📋 rejectUser 云端结果: code=${result['code']}, msg=${result['message']}');
      
      notifyListeners();
      
      if (result['code'] == 0) {
        print('✅ 拒绝成功');
        return true;
      } else {
        print('⚠️ 云端更新失败，但本地已处理: ${result['message']}');
        return true;  // 本地已处理
      }
    } catch (e) {
      print('⚠️ 拒绝异常: $e');
      notifyListeners();
      return true;
    }
  }


  /// Enable a disabled user
  Future<bool> enableUser(String username) async {
    try {
      print('enableUser: ' + username);

      final localIndex = _localUsers.indexWhere((u) => u.username == username);
      if (localIndex != -1) {
        _localUsers[localIndex].status = 'active';
        _localUsers[localIndex].isActive = true;
        await _saveLocalUsers();
      }

      final cloudService = CloudBaseService.instance;
      final result = await cloudService.callApi(
        'update',
        collection: 'users',
        query: {'username': username},
        data: {
          'status': 'active',
          'isActive': true,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
      print('enableUser 云端结果: code=${result['code']}, msg=${result['message']}');

      notifyListeners();
      return true;
    } catch (e) {
      print('enableUser error: ' + e.toString());
      notifyListeners();
      return false;
    }
  }


  /// 删除用户（云端禁用，本地删除）
  Future<bool> deleteUser(String username) async {
    try {
      print('deleteUser: ' + username);

      _localUsers.removeWhere((u) => u.username == username);
      await _saveLocalUsers();
      print('local user deleted');

      // 同步更新到腾讯云 - query 和 data 作为独立参数传递
      final cloudService = CloudBaseService.instance;
      final result = await cloudService.callApi(
        'update',
        collection: 'users',
        query: {'username': username},
        data: {
          'status': 'disabled',
          'isActive': false,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
      print('📋 deleteUser 云端结果: code=${result['code']}, msg=${result['message']}');

      notifyListeners();
      return true;
    } catch (e) {
      print('deleteUser error: ' + e.toString());
      notifyListeners();
      return false;
    }
  }

  /// Admin update user info
  Future<bool> adminUpdateUser({
    required String username,
    required String name,
    required String phone,
    required String department,
    required String role,
  }) async {
    try {
      print('adminUpdateUser: ' + username);

      final localIndex = _localUsers.indexWhere((u) => u.username == username);
      if (localIndex != -1) {
        _localUsers[localIndex].name = name;
        _localUsers[localIndex].phone = phone;
        _localUsers[localIndex].department = department;
        _localUsers[localIndex].role = role;
        await _saveLocalUsers();
        print('local user updated');
      }

      final cloudService = CloudBaseService.instance;
      final result = await cloudService.callApi(
        'update',
        collection: 'users',
        query: {'username': username},
        data: {
          'name': name,
          'phone': phone,
          'department': department,
          'role': role,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
      print('adminUpdateUser 云端结果: code=${result['code']}, msg=${result['message']}');

      notifyListeners();
      return true;
    } catch (e) {
      print('adminUpdateUser error: ' + e.toString());
      notifyListeners();
      return false;
    }
  }

  bool changePassword(String oldPassword, String newPassword) {
    if (_currentUser == null) return false;

    try {
      final index = _localUsers.indexWhere((u) => u.username == _currentUser!.username);
      if (index == -1) return false;

      if (_localUsers[index].password != oldPassword) {
        _error = '原密码错误';
        notifyListeners();
        return false;
      }

      _localUsers[index].password = newPassword;
      _currentUser = _localUsers[index];
      _saveLocalUsers();
      notifyListeners();
      return true;
    } catch (e) {
      _error = '修改密码失败: $e';
      notifyListeners();
      return false;
    }
  }

  bool updateProfile({required String name, required String phone}) {
    if (_currentUser == null) return false;

    try {
      final index = _localUsers.indexWhere((u) => u.username == _currentUser!.username);
      if (index == -1) return false;

      _localUsers[index].name = name;
      _localUsers[index].phone = phone;
      _currentUser = _localUsers[index];
      _saveLocalUsers();
      
      // 同步更新到腾讯云
      _updateUserToCloudBase(_currentUser!);
      
      notifyListeners();
      return true;
    } catch (e) {
      _error = '更新失败: $e';
      notifyListeners();
      return false;
    }
  }
  
  /// 更新用户到腾讯云数据库
  Future<bool> _updateUserToCloudBase(User user) async {
    try {
      // 先查询用户ID
      final response = await http.post(
        Uri.parse(apiBaseUrl),
        headers: AppConstants.cloudBaseHeaders,
        body: jsonEncode({
          'action': 'query',
          'collection': 'users',
          'query': {'username': user.username},
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null && data['data'].isNotEmpty) {
          final cloudId = data['data'][0]['_id'];
          
          // 更新云端数据 - 使用正确的云数据库更新格式
          final updateResponse = await http.post(
            Uri.parse(apiBaseUrl),
            headers: AppConstants.cloudBaseHeaders,
            body: jsonEncode({
              'action': 'update',
              'collection': 'users',
              'query': {'username': user.username},
              'data': {
                'docId': cloudId,
                'updateData': {
                  'name': user.name,
                  'phone': user.phone,
                },
              },
            }),
          ).timeout(const Duration(seconds: 15));
          
          if (updateResponse.statusCode == 200) {
            final updateResult = jsonDecode(updateResponse.body);
            print('云端更新结果: ${updateResult}');
            return updateResult['code'] == 0;
          } else {
            print('云端更新失败: ${updateResponse.body}');
          }
        } else {
          print('未找到用户: ${data}');
        }
      } else {
        print('查询用户失败: ${response.statusCode}');
      }
      return false;
    } catch (e) {
      print('同步到腾讯云失败: $e');
      return false;
    }
  }

  void logout() {
    _currentUser = null;
    // 清除登录会话（下次启动不自动登录）
    _prefs?.remove('saved_login_username');
    _prefs?.remove('saved_login_password');
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
