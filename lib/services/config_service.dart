// lib/services/config_service.dart
// 云端字典配置（业务类型 / 隐患类别）读取 + 本地缓存。
//
// 设计约束（与 announcement_service.dart 完全一致）：
//  1. 只读，不做任何增删改（管理员在电脑端维护）；
//  2. 统一走 CloudBaseService.instance.callApi，云函数零改动；
//  3. 取不到 / items 为空 → 返回 null，由上层回退硬编码字典，
//     绝不让类别列表变空；
//  4. 缓存用 SharedPreferences（工程既有本地存储方案），带 savedAt 时间戳。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../models/business_type.dart';
import 'cloudbase_service.dart';

/// appConfig 集合里的文档 key
const String kAppConfigKeyBusiness = 'business_types';
const String kAppConfigKeyIssueCategory = 'issue_categories';
const String kAppConfigKeyDept = 'depts';

/// 云端隐患类别条目
class ConfigCategory {
  final String name;
  final String business;
  final bool enabled;
  final int sort;

  const ConfigCategory({
    required this.name,
    required this.business,
    this.enabled = true,
    this.sort = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'business': business,
        'enabled': enabled,
        'sort': sort,
      };

  factory ConfigCategory.fromJson(Map<String, dynamic> json) => ConfigCategory(
        name: (json['name'] ?? '').toString().trim(),
        business: (json['business'] ?? '').toString().trim(),
        enabled: json['enabled'] == true,
        sort: json['sort'] is int ? json['sort'] as int : 0,
      );
}

/// 云端科室条目（数据隔离维度）
class Department {
  final String code;
  final String name;
  final String short;
  final int colorValue;
  final String icon;
  final bool enabled;
  final int sort;

  const Department({
    required this.code,
    required this.name,
    this.short = '',
    this.colorValue = 0xFF9E9E9E,
    this.icon = '',
    this.enabled = true,
    this.sort = 0,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'short': short,
        'color': _colorToHex(colorValue),
        'icon': icon,
        'enabled': enabled,
        'sort': sort,
      };

  factory Department.fromJson(Map<String, dynamic> json) => Department(
        code: (json['code'] ?? '').toString().trim(),
        name: (json['name'] ?? '').toString().trim(),
        short: (json['short'] ?? '').toString().trim(),
        colorValue: AppConfig._parseColorHex(json['color']),
        icon: (json['icon'] ?? '').toString(),
        enabled: json['enabled'] == true,
        sort: json['sort'] is int ? json['sort'] as int : 0,
      );

  static String _colorToHex(int v) =>
      '#${v.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// 云端字典快照（业务类型 + 隐患类别）。
///
/// 两类条目都保留**全部**条目（含 enabled=false），
/// 因为历史隐患可能仍在使用被停用的类别/业务，反查时必须能命中。
class AppConfig {
  /// 业务类型全集（含停用），按 sort 升序
  final List<BusinessType> businessTypes;

  /// 隐患类别全集（含停用），按 sort 升序
  final List<ConfigCategory> categories;

  /// 科室全集（含停用），按 sort 升序
  final List<Department> departments;

  /// 云端 version（两条文档取最大值），仅用于日志排查
  final int version;

  const AppConfig({
    required this.businessTypes,
    required this.categories,
    this.departments = const [],
    this.version = 0,
  });

  bool get isEmpty => businessTypes.isEmpty && categories.isEmpty && departments.isEmpty;
  bool get hasBusinessTypes => businessTypes.isNotEmpty;
  bool get hasCategories => categories.isNotEmpty;
  bool get hasDepartments => departments.isNotEmpty;

  /// 启用的业务类型（下拉/选择器用）
  List<BusinessType> get enabledBusinessTypes =>
      businessTypes.where((b) => b.enabled).toList();

  /// 指定业务下**启用**的类别中文名（下拉用，按 sort）
  List<String> enabledCategoriesFor(String businessCode) => categories
      .where((c) => c.business == businessCode && c.enabled)
      .map((c) => c.name)
      .toList();

  /// 全部业务下**启用**的类别中文名（详情页编辑下拉用，去重保序）
  List<String> get enabledCategories {
    final out = <String>[];
    for (final c in categories) {
      if (!c.enabled) continue;
      if (c.name.isEmpty || out.contains(c.name)) continue;
      out.add(c.name);
    }
    return out;
  }

  /// 类别中文名 → 业务 code（含停用条目，反查用）；未命中返回 null
  String? businessOfCategory(String name) {
    if (name.isEmpty) return null;
    for (final c in categories) {
      if (c.name == name) return c.business;
    }
    return null;
  }

  /// 业务 code → 定义（含停用，反查用）；未命中返回 null
  BusinessType? businessOf(String code) {
    if (code.isEmpty) return null;
    for (final b in businessTypes) {
      if (b.code == code) return b;
    }
    return null;
  }

  /// 业务 code → 科室（云端 dept 优先，缺失走硬编码 BUSINESS_TO_DEPT）
  String? deptOfBusiness(String code) {
    final b = businessOf(code);
    if (b == null) return null;
    if (b.dept.isNotEmpty) return b.dept;
    return null;
  }

  /// 启用中的科室（切换器/下拉用）
  List<Department> get enabledDepartments =>
      departments.where((d) => d.enabled).toList();

  /// 科室 code → 定义（含停用）；未命中返回 null
  Department? deptInfoOf(String code) {
    if (code.isEmpty) return null;
    for (final d in departments) {
      if (d.code == code) return d;
    }
    return null;
  }

  /// 科室 code 列表（动态）
  List<String> get deptCodes => departments.map((d) => d.code).toList();

  Map<String, dynamic> toJson() => {
        'version': version,
        'businessTypes': businessTypes.map((b) => b.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'departments': departments.map((d) => d.toJson()).toList(),
      };

  /// 由 callApi 返回的文档列表解析；两条文档都缺失/都为空时返回 null
  static AppConfig? fromDocs(List<dynamic> docs) {
    final biz = <BusinessType>[];
    final cats = <ConfigCategory>[];
    final depts = <Department>[];
    var version = 0;

    for (final doc in docs) {
      if (doc is! Map) continue;
      final map = Map<String, dynamic>.from(doc);
      final key = (map['key'] ?? '').toString();
      final v = map['version'] is int ? map['version'] as int : 0;
      if (v > version) version = v;

      final items = map['items'];
      if (items is! List) continue;

      if (key == kAppConfigKeyBusiness) {
        for (final raw in items) {
          if (raw is! Map) continue;
          final e = Map<String, dynamic>.from(raw);
          final code = (e['code'] ?? '').toString().trim();
          if (code.isEmpty) continue;
          final name = (e['name'] ?? '').toString().trim();
          biz.add(BusinessType(
            code: code,
            name: name.isEmpty ? code : name,
            shortName: ((e['short'] ?? '').toString().trim()).isEmpty
                ? (name.isEmpty ? code : name)
                : (e['short'] ?? '').toString().trim(),
            colorValue: AppConfig._parseColorHex(e['color']),
            icon: (e['icon'] ?? '').toString(),
            dept: (e['dept'] ?? '').toString().trim(),
            enabled: e['enabled'] == true,
            sort: e['sort'] is int ? e['sort'] as int : 0,
          ));
        }
      } else if (key == kAppConfigKeyIssueCategory) {
        for (final raw in items) {
          if (raw is! Map) continue;
          final c = ConfigCategory.fromJson(Map<String, dynamic>.from(raw));
          if (c.name.isEmpty) continue;
          cats.add(c);
        }
      } else if (key == kAppConfigKeyDept) {
        for (final raw in items) {
          if (raw is! Map) continue;
          final e = Map<String, dynamic>.from(raw);
          final code = (e['code'] ?? '').toString().trim();
          if (code.isEmpty) continue;
          final name = (e['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          depts.add(Department.fromJson(e));
        }
      }
    }

    if (biz.isEmpty && cats.isEmpty && depts.isEmpty) return null;
    biz.sort(_bySort);
    cats.sort((a, b) => a.sort.compareTo(b.sort));
    depts.sort((a, b) => a.sort.compareTo(b.sort));
    return AppConfig(businessTypes: biz, categories: cats, departments: depts, version: version);
  }

  static int _bySort(BusinessType a, BusinessType b) => a.sort.compareTo(b.sort);

  factory AppConfig.fromCacheJson(Map<String, dynamic> json) {
    final bizRaw = json['businessTypes'];
    final catRaw = json['categories'];
    final depRaw = json['departments'];
    final biz = <BusinessType>[];
    final cats = <ConfigCategory>[];
    final depts = <Department>[];
    if (bizRaw is List) {
      for (final raw in bizRaw) {
        if (raw is Map) biz.add(BusinessType.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    if (catRaw is List) {
      for (final raw in catRaw) {
        if (raw is Map) cats.add(ConfigCategory.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    if (depRaw is List) {
      for (final raw in depRaw) {
        if (raw is Map) depts.add(Department.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    if (biz.isEmpty && cats.isEmpty && depts.isEmpty) {
      throw const FormatException('appConfig 缓存为空');
    }
    return AppConfig(
      businessTypes: biz,
      categories: cats,
      departments: depts,
      version: json['version'] is int ? json['version'] as int : 0,
    );
  }

  /// '#e8823c' / 'e8823c' / 0xFFE8823C → ARGB int；脏值返回灰色
  static int _parseColorHex(dynamic raw) {
    const fallback = 0xFF9E9E9E;
    if (raw is int) return raw;
    final s = (raw?.toString() ?? '').trim().replaceAll('#', '');
    if (s.length == 6) {
      return int.tryParse('FF$s', radix: 16) ?? fallback;
    }
    if (s.length == 8) {
      return int.tryParse(s, radix: 16) ?? fallback;
    }
    return fallback;
  }
}

/// 云端字典服务：拉取 + 缓存。
class ConfigService {
  ConfigService._();

  static ConfigService? _instance;
  static ConfigService get instance {
    _instance ??= ConfigService._();
    return _instance!;
  }

  /// 缓存 key（字典对全员一致，全局共享即可）
  static const String cacheKey = 'gz_appconfig_v1';

  /// 缓存体积上限；字典很小，给个宽松上限防止异常数据拖慢 SharedPreferences
  static const int _cacheSizeLimit = 256 * 1024;

  // ================= 云端读取 =================

  /// 拉取 appConfig 全量文档。
  /// 返回 null 表示「没取到有效字典」，调用方应回退硬编码。
  Future<AppConfig?> fetchConfig() async {
    try {
      final result = await CloudBaseService.instance.callApi(
        'query',
        collection: AppConstants.appConfigCollection,
        query: {},
      );
      if (result['code'] == 0 && result['data'] is List) {
        final cfg = AppConfig.fromDocs(List<dynamic>.from(result['data'] as List));
        if (cfg == null || cfg.isEmpty) {
          print('⚠️ appConfig 无有效条目，回退硬编码字典');
          return null;
        }
        print('⚙️ 云端字典已加载：业务 ${cfg.businessTypes.length} 项 / '
            '类别 ${cfg.categories.length} 项 / 科室 ${cfg.departments.length} 项（version=${cfg.version}）');
        return cfg;
      }
      print('⚠️ 拉取 appConfig 失败: code=${result['code']}, msg=${result['message']}');
      return null;
    } catch (e) {
      print('❌ 拉取 appConfig 异常: $e');
      return null;
    }
  }

  // ================= 本地缓存 =================

  /// 读取缓存字典；无缓存 / 缓存损坏返回 null
  Future<AppConfig?> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AppConfig.fromCacheJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      print('⚠️ 读取字典缓存失败: $e');
      return null;
    }
  }

  /// 缓存写入时间戳（毫秒），无缓存返回 null
  Future<int?> cacheSavedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['savedAt'] is int) {
        return decoded['savedAt'] as int;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> saveCache(AppConfig config) async {
    try {
      final payload = jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        ...config.toJson(),
      });
      if (payload.length > _cacheSizeLimit) {
        print('⚠️ 字典缓存超限，跳过缓存');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, payload);
      print('💾 云端字典已缓存（${(payload.length / 1024).toInt()}KB）');
    } catch (e) {
      print('❌ 写入字典缓存失败: $e');
    }
  }
}
