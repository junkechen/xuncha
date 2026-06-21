// lib/models/user.dart
// 用户数据模型 - 完整版

enum UserRole { admin, inspector, rectifier, supervisor, viewer }

class User {
  final String id;
  String username;
  String password;
  String name;
  String phone;
  String department;
  String _roleString; // 存储角色字符串
  String status; // 'active', 'pending', 'disabled'
  String? avatar;
  bool isActive;

  User({
    required this.id,
    required this.username,
    required this.password,
    required this.name,
    required this.phone,
    required this.department,
    required String role,
    this.status = 'active',
    this.avatar,
    this.isActive = true,
  }) : _roleString = role;

  UserRole get role {
    switch (_roleString) {
      case 'admin': return UserRole.admin;
      case 'inspector': return UserRole.inspector;
      case 'rectifier': return UserRole.rectifier;
      case 'supervisor': return UserRole.supervisor;
      case 'viewer': return UserRole.viewer;
      case 'leader': return UserRole.supervisor; // 领导角色映射为督查员
      default: return UserRole.inspector;
    }
  }

  set role(dynamic value) {
    if (value is String) {
      _roleString = value;
    } else if (value is UserRole) {
      _roleString = value.name;
    }
  }

  String get roleName {
    switch (_roleString) {
      case 'admin': return '管理员';
      case 'inspector': return '巡检员';
      case 'rectifier': return '整改负责人';
      case 'supervisor': return '督查员';
      case 'viewer': return '只读查看员';
      case 'leader': return '部门领导';
      default: return _roleString.isNotEmpty ? _roleString : '巡检员';
    }
  }

  bool get canCreateIssue => role == UserRole.admin || role == UserRole.inspector;
  bool get canRectify => role == UserRole.admin || role == UserRole.rectifier;
  bool get canReview => role == UserRole.admin || role == UserRole.supervisor;
  bool get canManageUsers => role == UserRole.admin;
  bool get canViewStats => true;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'name': name,
      'phone': phone,
      'department': department,
      'role': _roleString,
      'status': status,
      'avatar': avatar,
      'isActive': isActive,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] ?? json['id'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      department: json['department'] ?? '',
      role: json['role']?.toString() ?? 'inspector',
      status: json['status'] ?? 'active',
      avatar: json['avatar'],
      isActive: json['isActive'] ?? true,
    );
  }
}
