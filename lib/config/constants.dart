// lib/config/constants.dart
// 系统配置常量

class AppConstants {
  // ============================================
  // 腾讯云开发配置（请在配置腾讯云后填写）
  // ============================================
  
  // 腾讯云开发环境ID
  // 环境ID在腾讯云控制台 → 云开发 → 环境设置 中查看
  static const String cloudBaseEnvId = 'anuanbu1-1-6gjqaydwd067dbb1';
  
  // API配置（云开发自动生成的API地址）
  static const String baseUrl = 'https://\${cloudBaseEnvId}.cloudbase.cn';
  
  // 数据库集合名称
  static const String usersCollection = 'users';
  static const String issuesCollection = 'issues';
  static const String departmentsCollection = 'departments';
  
  // 问题分类
  static const Map<String, String> issueCategories = {
    'wastewater': '废水排放',
    'wastegas': '废气排放',
    'solidWaste': '固废管理',
    'noise': '噪音污染',
    'other': '其他'
  };
  
  // 严重程度
  static const Map<String, String> severityLevels = {
    'general': '一般',
    'serious': '较重',
    'critical': '严重'
  };
  
  // 问题状态
  static const Map<String, String> issueStatus = {
    'pending': '待处理',
    'processing': '整改中',
    'reviewing': '待验收',
    'closed': '已关闭'
  };
  
  // 用户角色
  static const Map<String, String> userRoles = {
    'admin': '管理员',
    'inspector': '检查员',
    'rectifier': '整改负责人',
    'supervisor': '督查员',
    'viewer': '只读查看员'
  };
}

class AppColors {
  static const int primaryGreen = 0xFF10B981;
  static const int primaryDark = 0xFF059669;
  static const int warningYellow = 0xFFFFC107;
  static const int dangerRed = 0xFFF44336;
  static const int infoBlue = 0xFF2196F3;
  static const int successGreen = 0xFF4CAF50;
  
  static const int statusPending = 0xFFFFF3CD;
  static const int statusProcessing = 0xFFCCE5FF;
  static const int statusReviewing = 0xFFE2D9F3;
  static const int statusClosed = 0xFFD4EDDA;
  static const int statusOverdue = 0xFFF8D7DA;
}