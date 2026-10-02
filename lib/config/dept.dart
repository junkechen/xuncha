// lib/config/dept.dart
// 科室（业务域）定义 —— 多科室隔离的唯一配置出处
//
// 与电脑端 env_inspection_desktop/app/js/dept.js 严格对应，改一处要同步另一处。
//
// 设计约束（来自「业务类别体系改造方案」）：
//   1. 科室是身份属性，不是会话选项 —— 登录时不让用户选，由后台配置的 users.deptCode 决定。
//   2. 只有同时归属多个科室的人才看得到切换入口。
//   3. 切换必须清掉本地缓存 —— 否则会读到另一个科室的旧数据。
//   4. 类别字典已按「业务」分组，迁移到 models/business_type.dart（CATEGORY_BY_BUSINESS），
//      本文件只保留科室隔离相关逻辑。隐患归属科室由「业务 → 科室」推导（见 hazardDeptOf）。

import 'package:shared_preferences/shared_preferences.dart';

import '../models/business_type.dart';
import '../services/config_service.dart';

class DeptInfo {
  final String code;
  final String name;
  final String short;
  final int color; // ARGB
  final String icon;

  const DeptInfo({
    required this.code,
    required this.name,
    required this.short,
    required this.color,
    required this.icon,
  });
}

class AppDept {
  static const String defaultCode = 'JN';

  /// 环保节能科：绿色。安全科：橙色（视觉上一眼能分辨当前在哪一侧操作）
  static const List<DeptInfo> _builtin = [
    DeptInfo(code: 'JN', name: '环保节能科', short: '环保', color: 0xFF2E9E5B, icon: '🌿'),
    DeptInfo(code: 'AQ', name: '安全科', short: '安全', color: 0xFFE8823C, icon: '⚠'),
  ];

  /// 云端动态科室（由 ConfigProvider 在字典刷新后注入）。
  /// 为空时回退内置 JN/AQ；注入后所有引用点（切换器/校验/反查）自动生效，无需发版。
  static List<DeptInfo> _dynamic = const [];

  /// 云端字典就绪后由 ConfigProvider 调用，传入 appConfig 的 depts 列表。
  /// 含「已停用」科室——停用只是界面不再列出，历史隐患/业务仍须能反查到该科室。
  static void setDynamicDepts(List<Department> depts) {
    if (depts.isEmpty) {
      _dynamic = const [];
      return;
    }
    _dynamic = depts.map((d) => DeptInfo(
      code: d.code,
      name: d.name,
      short: d.short.isNotEmpty ? d.short : d.name,
      color: d.colorValue,
      icon: d.icon,
    )).toList();
    print('⚙️ 动态科室已注入：${_dynamic.length} 个（${_dynamic.map((e) => e.code).join(', ')}）');
  }

  /// 当前生效的科室列表（动态优先，内置兜底）
  static List<DeptInfo> get all => _dynamic.isNotEmpty ? _dynamic : _builtin;

  static const _key = 'current_dept';

  static List<String> get codes => all.map((d) => d.code).toList();

  static bool isValid(String code) => codes.contains(code);

  static DeptInfo info(String code) =>
      all.firstWhere((d) => d.code == code, orElse: () => all.first);

  /// 当前激活科室（异步：读本地持久化）
  static Future<String> current() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    return isValid(v ?? '') ? v! : defaultCode;
  }

  static Future<void> setCurrent(String code) async {
    if (!isValid(code)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
  }

  /// 退出登录时清掉，避免下一个人落到上一个用户的科室视图
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// 该用户可访问的科室。服务端未下发时兜底给默认科室。
  static List<String> availableFor(String? deptCode, List<String>? deptCodes) {
    final valid = (deptCodes ?? []).where(isValid).toList();
    if (valid.isNotEmpty) return valid;
    if (deptCode != null && isValid(deptCode)) return [deptCode];
    return [defaultCode];
  }

  /// 登录后同步：只在当前值越界时纠正，单人单科室的用户不会被改写
  static Future<void> syncFromUser(List<String> available) async {
    final cur = await current();
    if (!available.contains(cur)) await setCurrent(available.first);
  }

  // ============================================================
  // 隐患类别字典已迁至 models/business_type.dart（CATEGORY_BY_BUSINESS）。
  // 本文件仅保留「科室」隔离逻辑。
  // ============================================================

  /// 上报页/筛选器要用的类别中文列表（按业务裁剪，对接 CATEGORY_BY_BUSINESS）。
  static List<String> categoriesForBusiness(String businessCode) =>
      CATEGORY_BY_BUSINESS[businessCode] ?? CATEGORY_BY_BUSINESS[defaultCode]!;

  /// 上报页的常用描述预设，按业务隔离。
  static const Map<String, List<String>> presetDescriptionsByBusiness = {
    'SAFE': [
      '消防通道被占用/堵塞',
      '灭火器过期或压力不足',
      '配电箱未上锁、线路裸露',
      '安全防护罩缺失',
      '危化品未专区存放、标识不清',
      '动火/高处/有限空间作业未开票',
      '未按规定佩戴劳保用品',
      '安全警示标识缺失',
    ],
    'SAVING': [
      '跑冒滴漏造成水资源浪费',
      '设备空转/待机能耗偏高',
      '压缩空气管道漏气',
      '燃气燃烧效率偏低',
      '高耗能设备未及时关停',
      '余热余压未回收利用',
    ],
    'ENV': [
      '废水排放超标',
      '废气治理设施未正常运行',
      '固废堆存不规范，未分类暂存',
      '危废暂存间标识缺失',
      '粉尘/噪声异常',
      '环保设施台账记录不完整',
    ],
  };

  static List<String> presetDescriptions(String businessCode) =>
      presetDescriptionsByBusiness[businessCode] ?? presetDescriptionsByBusiness['ENV']!;

  /// 隐患归属哪个科室。
  /// 判定顺序（与桌面端 dept.js hazardDeptOf 一致）：
  ///   1. 记录自带 deptCode
  ///   2. businessType 反查（SAFE→AQ，SAVING/ENV→JN）
  ///   3. 中文类别反查（businessOfCategoryName）
  ///   4. 默认 JN
  static String hazardDeptOf(String? deptCode, String? businessType, String? category) {
    if (deptCode != null && isValid(deptCode)) return deptCode;
    if (businessType != null && businessType.isNotEmpty && BUSINESS_TO_DEPT.containsKey(businessType)) {
      return BUSINESS_TO_DEPT[businessType]!;
    }
    if (category != null && category.isNotEmpty) {
      final biz = businessOfCategoryName(category);
      if (BUSINESS_TO_DEPT.containsKey(biz)) return BUSINESS_TO_DEPT[biz]!;
    }
    return defaultCode;
  }
}
