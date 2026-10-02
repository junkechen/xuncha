// lib/models/business_type.dart
// 业务类型定义 —— 与桌面端 app/js/business.js 严格对齐的唯一配置出处。
//
// 设计要点（来自「业务类别体系改造方案」）：
//   1. 业务类型（安全/节能/环保）是用户/隐患的【标签】，不参与数据隔离；
//   2. 数据隔离维度是「科室」(deptCode: AQ/JN)，由「业务 → 科室」映射推导；
//   3. 隐患类别按业务分组，库里存中文本身（历史数据零迁移）。
//
// 桌面端口径：businessTypes 为空数组时视为「全部业务」（不是「未分配」）。

class BusinessType {
  final String code; // SAFE / SAVING / ENV
  final String name; // 全名：安全业务
  final String shortName; // 短名：安全（徽章用）
  final int colorValue; // ARGB，与桌面端 hex 一致
  final String icon;

  /// 科室 code（云端 appConfig 下发）；空串表示由 BUSINESS_TO_DEPT 兜底
  final String dept;

  /// 是否启用（管理员可在电脑端停用；停用项不在下拉展示，但反查仍可用）
  final bool enabled;

  /// 排序号（升序）
  final int sort;

  const BusinessType({
    required this.code,
    required this.name,
    required this.shortName,
    required this.colorValue,
    required this.icon,
    this.dept = '',
    this.enabled = true,
    this.sort = 0,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'short': shortName,
        'color': colorValue,
        'icon': icon,
        'dept': dept,
        'enabled': enabled,
        'sort': sort,
      };

  factory BusinessType.fromJson(Map<String, dynamic> json) => BusinessType(
        code: (json['code'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        shortName: (json['short'] ?? json['name'] ?? '').toString(),
        colorValue: json['color'] is int ? json['color'] as int : 0xFF9E9E9E,
        icon: (json['icon'] ?? '').toString(),
        dept: (json['dept'] ?? '').toString(),
        enabled: json['enabled'] == true,
        sort: json['sort'] is int ? json['sort'] as int : 0,
      );
}

/// ============================================================
/// 云端动态字典钩子
///
/// 管理员在电脑端新增业务类型 / 隐患类别后，手机端启动时由 ConfigProvider
/// 把云端字典注入这里。硬编码字典（kBusinessTypes / CATEGORY_BY_BUSINESS）
/// 仍是兜底：钩子未注入或未命中时，行为与改造前完全一致。
/// 这样做是为了避免把 Provider 逐层透传到纯函数/模型层。
/// ============================================================

/// 中文类别 → 业务 code（含停用项）；未命中返回 null 走硬编码兜底
BusinessType? Function(String code)? dynamicBusinessTypeOf;

/// 业务 code → 科室；未命中返回 null 走 BUSINESS_TO_DEPT 兜底
String? Function(String code)? dynamicDeptOfBusiness;

/// 中文类别 → 业务 code（含停用项）；未命中返回 null 走硬编码兜底
String? Function(String category)? dynamicBizOfCategoryName;

/// 云端下发的全部业务 code（含停用项）
List<String> Function()? dynamicBusinessCodes;

/// 业务类型全集（顺序与桌面端 BUSINESS_TYPES 一致）
const List<BusinessType> kBusinessTypes = [
  BusinessType(
    code: 'SAFE',
    name: '安全业务',
    shortName: '安全',
    colorValue: 0xFFE8823C, // #e8823c
    icon: '⚠',
  ),
  BusinessType(
    code: 'SAVING',
    name: '节能业务',
    shortName: '节能',
    colorValue: 0xFF2E9E5B, // #2e9e5b
    icon: '🌿',
  ),
  BusinessType(
    code: 'ENV',
    name: '环保业务',
    shortName: '环保',
    colorValue: 0xFF38BDF8, // #38bdf8
    icon: '♻',
  ),
];

/// 全部 code —— 桌面端新增/未设置用户默认全选
List<String> get kBusinessAllCodes =>
    kBusinessTypes.map((b) => b.code).toList();

/// 按 code 取定义，脏值返回 null。
/// 优先命中云端字典（含管理员新增的业务），未命中再退回硬编码。
BusinessType? businessTypeOf(String code) {
  if (code.isEmpty) return null;
  final dyn = dynamicBusinessTypeOf?.call(code);
  if (dyn != null) return dyn;
  for (final b in kBusinessTypes) {
    if (b.code == code) return b;
  }
  return null;
}

/// 业务 code 是否合法（硬编码三业务 + 云端新增业务）。
/// 脏值（ENERGY / EQUIP / SITE 等历史遗留）一律 false，由 parseBusinessTypes 处理。
bool isValidBusinessCode(String code) {
  if (code.isEmpty) return false;
  if (businessTypeOf(code) != null) return true;
  return dynamicBusinessCodes?.call().contains(code) ?? false;
}

/// 业务全名（如「安全业务」）；脏值返回原 code，空返回『全部业务』
String businessNameOf(String code) {
  if (code.isEmpty) return '全部业务';
  return businessTypeOf(code)?.name ?? code;
}

/// 业务短名（如「安全」）；脏值返回原 code，空返回『全部业务』
String businessShortOf(String code) {
  if (code.isEmpty) return '全部业务';
  return businessTypeOf(code)?.shortName ?? code;
}

/// 业务配色（ARGB）；脏值/空返回灰色
int businessColorOf(String code) {
  if (code.isEmpty) return 0xFF9E9E9E;
  return businessTypeOf(code)?.colorValue ?? 0xFF9E9E9E;
}

/// 业务 → 科室（数据隔离），与 dept.js 的 DEPTS.code 对应
const Map<String, String> BUSINESS_TO_DEPT = {
  'SAFE': 'AQ',
  'SAVING': 'JN',
  'ENV': 'JN',
};

/// 科室默认兜底（找不到归属时）
const String kDefaultDeptForBusiness = 'JN';

/// 由业务反查科室 code；脏值/空返回默认 JN。
/// 云端下发了 dept 时以云端为准（管理员新增业务可能归属其它科室）。
String deptOfBusiness(String code) {
  if (code.isEmpty) return kDefaultDeptForBusiness;
  final dyn = dynamicDeptOfBusiness?.call(code);
  if (dyn != null && dyn.isNotEmpty) return dyn;
  return BUSINESS_TO_DEPT[code] ?? kDefaultDeptForBusiness;
}

/// 按业务划分的隐患类别字典（库里仍存中文本身，历史数据零迁移）。
/// 安全 13 项（含其他）、节能 10 项、环保 5 项。
const Map<String, List<String>> CATEGORY_BY_BUSINESS = {
  'SAFE': [
    '工艺', '电气仪表', '消防应急', '设备隐患', '规章制度', '特种设备',
    '培训教育', '安全投入', '违章操作', '职业卫生', '有限空间', '外来施工', '其他'
  ],
  'SAVING': [
    '节水', '节电', '压风', '氢气', '氮气', '燃气', '耗能设备',
    '工艺节能', '浪费损耗', '碳排管理'
  ],
  'ENV': [
    '废水排放', '废气排放', '固废管理', '噪音污染', '其他'
  ],
};

/// 类别 → 业务 反查（旧隐患无 businessType，靠中文类别归业务；再映射科室）
/// 未命中默认 ENV（与桌面端 BUSINESS_OF_CATEGORY 默认口径一致）。
///
/// 云端字典优先：管理员新增的类别、以及被停用但历史数据仍在用的类别，
/// 都能正确反查到业务；云端未命中再走硬编码，最后兜底 ENV。
String businessOfCategoryName(String? category) {
  if (category == null || category.isEmpty) return 'ENV';
  final dyn = dynamicBizOfCategoryName?.call(category);
  if (dyn != null && dyn.isNotEmpty) return dyn;
  for (final entry in CATEGORY_BY_BUSINESS.entries) {
    if (entry.value.contains(category)) return entry.key;
  }
  return 'ENV';
}

/// 该中文类别是否为「已知类别」（云端字典或硬编码字典收录过）。
/// 完全陌生的类别反查业务时会兜底 ENV，调用方可据此保留原业务。
bool isKnownCategoryName(String? category) {
  if (category == null || category.isEmpty) return false;
  if (dynamicBizOfCategoryName?.call(category) != null) return true;
  for (final entry in CATEGORY_BY_BUSINESS.entries) {
    if (entry.value.contains(category)) return true;
  }
  return false;
}

/// 从云端任意形态（数组 / 单值 / 缺失 / null）解析出合法 code 列表，过滤脏值。
/// 兼容第一批迁移前的脏值：
///   · ENERGY → 拆成 [SAVING, ENV]（原能源环保业务已拆为节能+环保）
///   · EQUIP / SITE → 直接忽略（云端已迁移，仅作本地兜底）
List<String> parseBusinessTypes(dynamic raw) {
  final List<String> out = [];
  void add(String c) {
    if (c == 'ENERGY') {
      // 能源环保拆分为节能 + 环保
      if (!out.contains('SAVING')) out.add('SAVING');
      if (!out.contains('ENV')) out.add('ENV');
      return;
    }
    if (c == 'EQUIP' || c == 'SITE') {
      // 已废弃，忽略
      return;
    }
    if (businessTypeOf(c) != null && !out.contains(c)) out.add(c);
  }

  if (raw is List) {
    for (final e in raw) {
      final s = e?.toString() ?? '';
      if (s.isNotEmpty) add(s);
    }
  } else if (raw is String && raw.isNotEmpty) {
    add(raw);
  }
  return out;
}

/// 列表/详情用：全名拼接，如「安全业务 / 节能业务」；空数组视为「全部业务」
String businessNames(List<String> codes) {
  final names = codes
      .map((c) => businessNameOf(c))
      .where((n) => n.isNotEmpty && n != '全部业务')
      .toList();
  return names.isEmpty ? '全部业务' : names.join(' / ');
}

/// 徽章用：短名拼接，如「安全 / 节能」；空数组视为「全部业务」
String businessShortLabel(List<String> codes) {
  final shorts = codes
      .map((c) => businessShortOf(c))
      .where((n) => n.isNotEmpty && n != '全部业务')
      .toList();
  return shorts.isEmpty ? '全部业务' : shorts.join(' / ');
}
