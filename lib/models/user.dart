// lib/models/user.dart
// 用户数据模型 - 完整版

import 'business_type.dart';

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

  /// 所属科室编码（JN=环保节能科 / AQ=安全科）。
  /// 由服务端下发，不由用户选择 —— 科室是身份属性，不是会话选项。
  /// 存量用户尚未回填时服务端会兜底给 JN。
  String deptCode;

  /// 可访问的科室列表。长度 > 1 时才显示切换入口。
  List<String> deptCodes;

  /// 业务归属标签（SAFE / ENERGY / SITE / EQUIP），可多选。
  /// 仅作展示与统计维度，不参与数据过滤——数据可见范围由 deptCode 决定。
  /// 空数组表示「全部业务」。
  List<String> businessTypes;

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
    String? deptCode,
    List<String>? deptCodes,
    List<String>? businessTypes,
  })  : _roleString = role,
        deptCode = deptCode ?? '',
        deptCodes = deptCodes ?? const [],
        businessTypes = businessTypes ?? const [];

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
      'deptCode': deptCode,
      'deptCodes': deptCodes,
      'businessTypes': businessTypes,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    // deptCodes 优先取服务端在登录返回体顶层给的数组；
    // 兼容直接从 user 文档上读（迁移后 users 表会带这个字段）。
    List<String> codes = const [];
    final rawCodes = json['deptCodes'];
    if (rawCodes is List) {
      codes = rawCodes.map((e) => e.toString()).toList();
    }
    final single = json['deptCode']?.toString() ?? '';
    if (codes.isEmpty && single.isNotEmpty) codes = [single];

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
      deptCode: single,
      deptCodes: codes,
      businessTypes: parseBusinessTypes(json['businessTypes']),
    );
  }
}
