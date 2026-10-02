// lib/providers/config_provider.dart
// 云端字典（业务类型 / 隐患类别）状态管理。
//
// 策略与 announcement_provider 一致：
//   · 构造时立刻读缓存 → 首屏即可用（不阻塞启动）；
//   · 随后静默拉云端刷新，成功写缓存并通知 UI；失败保留缓存，不报错；
//   · 云端字典缺失/拉取失败 → 全部回退硬编码字典（CATEGORY_BY_BUSINESS /
//     kBusinessTypes），类别列表永不变空。
//
// 手机端不提供任何增删改能力，管理员只在电脑端维护。

import 'package:flutter/foundation.dart';

import '../config/dept.dart';
import '../models/business_type.dart';
import '../services/config_service.dart';

class ConfigProvider extends ChangeNotifier {
  final ConfigService _service = ConfigService.instance;

  AppConfig? _config;
  bool _refreshing = false;
  bool _disposed = false;
  DateTime? _lastRefreshAt;

  /// 静默刷新最小间隔（避免每次进页面都打一次云端）
  static const Duration _minRefreshInterval = Duration(minutes: 10);

  ConfigProvider() {
    // 注入动态反查钩子：字典未就绪时返回 null，模型层自动回退硬编码
    dynamicBusinessTypeOf = (code) => _config?.businessOf(code);
    dynamicDeptOfBusiness = (code) => _config?.deptOfBusiness(code);
    dynamicBizOfCategoryName = (name) => _config?.businessOfCategory(name);
    dynamicBusinessCodes = () => _config?.businessTypes.map((b) => b.code).toList() ?? <String>[];
    _bootstrap();
  }

  /// 云端字典是否已就绪（未就绪时各查询接口回退硬编码）
  bool get isReady => _config != null;

  // ================= 启动引导 =================

  /// 缓存优先 + 后台刷新；全程异步，不阻塞 runApp。
  Future<void> _bootstrap() async {
    await loadFromCache();
    await refresh();
  }

  /// 读本地缓存（首帧前/字典未就绪时用）
  Future<void> loadFromCache() async {
    final cached = await _service.loadCache();
    if (cached == null || cached.isEmpty) return;
    _config = cached;
    _notify();
    AppDept.setDynamicDepts(cached.departments);
    print('⚙️ 字典缓存已载入：业务 ${cached.businessTypes.length} 项 / '
        '类别 ${cached.categories.length} 项 / 科室 ${cached.departments.length} 项');
  }

  /// 拉云端刷新。失败时保留现有字典（缓存或硬编码），绝不置空。
  Future<void> refresh({bool force = false}) async {
    if (_refreshing) return;
    if (!force &&
        _config != null &&
        _lastRefreshAt != null &&
        DateTime.now().difference(_lastRefreshAt!) < _minRefreshInterval) {
      return;
    }
    _refreshing = true;
    try {
      final fetched = await _service.fetchConfig();
      if (fetched == null) {
        // 请求失败 / items 为空：保留缓存内容，由查询接口回退硬编码
        print('⚠️ 云端字典刷新失败，保留现有字典');
        return;
      }
      _config = fetched;
      _lastRefreshAt = DateTime.now();
      _notify();
      AppDept.setDynamicDepts(fetched.departments);
      await _service.saveCache(fetched);
    } catch (e) {
      print('❌ 云端字典刷新异常: $e');
    } finally {
      _refreshing = false;
    }
  }

  // ================= 对外查询 =================

  /// 指定业务下的类别中文名（仅启用项，按 sort 升序）。
  /// 云端字典为空时回退硬编码 CATEGORY_BY_BUSINESS。
  List<String> categoriesFor(String businessCode) {
    final dyn = _config?.enabledCategoriesFor(businessCode) ?? const <String>[];
    if (dyn.isNotEmpty) return dyn;
    return CATEGORY_BY_BUSINESS[businessCode] ?? const <String>[];
  }

  /// 全部业务下的启用类别（去重、按 sort），供详情页编辑下拉使用。
  /// 云端字典为空时回退硬编码全集。
  List<String> allCategories() {
    final dyn = _config?.enabledCategories ?? const <String>[];
    if (dyn.isNotEmpty) return dyn;
    final out = <String>[];
    for (final list in CATEGORY_BY_BUSINESS.values) {
      for (final name in list) {
        if (!out.contains(name)) out.add(name);
      }
    }
    return out;
  }

  /// 业务类型列表（仅启用项，按 sort）；云端字典为空时回退 kBusinessTypes。
  List<BusinessType> businessTypes() {
    final dyn = _config?.enabledBusinessTypes ?? const <BusinessType>[];
    if (dyn.isNotEmpty) return dyn;
    return kBusinessTypes;
  }

  /// 类别中文名 → 业务 code（**含停用项**：历史隐患可能用了被停用的旧类别）。
  /// 未命中时回退硬编码反查（默认 ENV）。
  String bizOfCategoryName(String category) =>
      businessOfCategoryName(category);

  /// 业务 code 是否合法（含云端新增业务）
  bool isValidBusiness(String code) => isValidBusinessCode(code);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
