// lib/screens/profile_screen.dart
// 个人中心页面 - 完整修复版

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/issue_provider.dart';
import '../providers/settings_provider.dart';
import '../models/user.dart';
import '../models/issue.dart';
import '../providers/issue_provider.dart';
import '../services/audio_service.dart';
import 'issue_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // 设置项状态（本地临时，用于编辑中预览）
  bool _pushEnabled = true;
  bool _soundEnabled = true;
  bool _vibrateEnabled = false;
  bool _darkMode = false;
  bool _largeFont = false;
  bool _autoSync = true;
  bool _wifiSync = true;

  // 通知设置
  bool _newIssueNotify = true;
  bool _overdueNotify = true;
  bool _auditNotify = true;
  bool _dailyReport = false;

  @override
  void initState() {
    super.initState();
    // 初始化时从 SettingsProvider 读取当前值
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsProvider>();
      setState(() {
        _pushEnabled = settings.pushEnabled;
        _soundEnabled = settings.soundEnabled;
        _vibrateEnabled = settings.vibrateEnabled;
        _darkMode = settings.darkMode;
        _largeFont = settings.largeFont;
        _autoSync = settings.autoSync;
        _wifiSync = settings.wifiSync;
        _newIssueNotify = settings.newIssueNotify;
        _overdueNotify = settings.overdueNotify;
        _auditNotify = settings.auditNotify;
        _dailyReport = settings.dailyReport;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        actions: [
          // 管理员：用户管理入口
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (auth.isAdmin) {
                return IconButton(
                  icon: const Icon(Icons.manage_accounts),
                  onPressed: () => _showUserManagement(context),
                  tooltip: '用户管理',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final user = auth.currentUser;
          return LayoutBuilder(
            builder: (context, constraints) {
              final isSmallScreen = constraints.maxWidth < 360;
              return ListView(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                children: [
                  // 用户信息卡片
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF059669)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: isSmallScreen ? 30 : 36,
                          backgroundColor: Colors.white,
                          child: Text(
                            user?.name.isNotEmpty == true ? user!.name.substring(0, 1) : '?',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: isSmallScreen ? 12 : 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.name ?? '未登录',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  user?.roleName ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user?.department ?? '',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white),
                          onPressed: () => _showEditProfileDialog(context),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 16 : 24),

                  // 功能菜单
                  _buildSectionTitle('设置', isSmallScreen),
                  SizedBox(height: isSmallScreen ? 8 : 12),
                  
                  // 只有管理员才能看到用户管理菜单
                  if (auth.isAdmin) ...[
                    _buildMenuItem(
                      context,
                      Icons.manage_accounts,
                      '用户管理',
                      '添加、审批、禁用用户',
                      () => _showUserManagement(context),
                      isSmallScreen,
                    ),
                  ],
                  _buildMenuItem(
                    context,
                    Icons.settings,
                    '系统设置',
                    '消息推送、界面偏好、账号安全',
                    () => _showSettingsDialog(context),
                    isSmallScreen,
                  ),
                  _buildMenuItem(
                    context,
                    Icons.lock_outline,
                    '修改密码',
                    '修改登录密码',
                    () => _showChangePasswordDialog(context),
                    isSmallScreen,
                  ),
                  _buildMenuItem(
                    context,
                    Icons.notifications,
                    '消息通知',
                    '整改提醒、审核通知',
                    () => _showNotificationSettings(context),
                    isSmallScreen,
                  ),
                  _buildMenuItem(
                    context,
                    Icons.language,
                    '语言与地区',
                    '简体中文',
                    () => _showLanguageDialog(context),
                    isSmallScreen,
                  ),
                  _buildMenuItem(
                    context,
                    Icons.help_outline,
                    '帮助与反馈',
                    '使用教程、问题反馈',
                    () => _showHelpDialog(context),
                    isSmallScreen,
                  ),
                  _buildMenuItem(
                    context,
                    Icons.info_outline,
                    '关于系统',
                    '版本信息、许可证',
                    () => _showAboutDialog(context),
                    isSmallScreen,
                  ),

                  SizedBox(height: isSmallScreen ? 16 : 24),

                  // 账号信息
                  _buildSectionTitle('账号信息', isSmallScreen),
                  SizedBox(height: isSmallScreen ? 8 : 12),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow('用户名', user?.username ?? '-'),
                        const Divider(),
                        _buildInfoRow('手机号', user?.phone ?? '-'),
                        const Divider(),
                        _buildInfoRow('部门', user?.department ?? '-'),
                        const Divider(),
                        _buildInfoRow('角色', user?.roleName ?? '-'),
                        const Divider(),
                        _buildInfoRow('账号状态', user?.isActive == true ? '正常' : '停用'),
                      ],
                    ),
                  ),

                  SizedBox(height: isSmallScreen ? 16 : 24),

                  // 我的待整改问题入口
                  if (user?.role == UserRole.rectifier || user?.role == UserRole.supervisor) ...[
                    _buildSectionTitle('我的任务', isSmallScreen),
                    SizedBox(height: isSmallScreen ? 8 : 12),
                    _MyRectificationCard(userId: user?.id ?? ''),
                    SizedBox(height: isSmallScreen ? 16 : 24),
                  ],

                  // 退出登录
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('退出登录', style: TextStyle(color: Colors.red)),
                      onTap: () => _showLogoutDialog(context),
                    ),
                  ),
                  
                  SizedBox(height: 32),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isSmallScreen) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: isSmallScreen ? 14 : 16,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
    bool isSmallScreen,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF10B981)),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 12 : 16,
          vertical: 4,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // 系统设置
  void _showSettingsDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) {
          return Consumer<SettingsProvider>(
            builder: (context, settingsProv, _) => SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      const Text(
                        '系统设置',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 通知设置
                  _buildSettingsSection('通知设置', [
                    SwitchListTile(
                      title: const Text('推送通知'),
                      subtitle: const Text('接收问题提醒通知', style: TextStyle(fontSize: 12)),
                      value: settingsProv.pushEnabled,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) {
                        settingsProv.setPushEnabled(v);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('声音提醒'),
                      subtitle: const Text('收到通知时播放声音', style: TextStyle(fontSize: 12)),
                      value: settingsProv.soundEnabled,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) {
                        settingsProv.setSoundEnabled(v);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('震动提醒'),
                      subtitle: const Text('收到通知时震动', style: TextStyle(fontSize: 12)),
                      value: settingsProv.vibrateEnabled,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) {
                        settingsProv.setVibrateEnabled(v);
                      },
                    ),
                  ]),

                  // 界面设置
                  _buildSettingsSection('界面设置', [
                    SwitchListTile(
                      title: const Text('深色模式'),
                      subtitle: const Text('开启深色主题', style: TextStyle(fontSize: 12)),
                      value: settingsProv.darkMode,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) {
                        settingsProv.setDarkMode(v);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('大字体'),
                      subtitle: const Text('使用更大的字体显示', style: TextStyle(fontSize: 12)),
                      value: settingsProv.largeFont,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) {
                        settingsProv.setLargeFont(v);
                      },
                    ),
                  ]),

                  // 数据设置
                  _buildSettingsSection('数据设置', [
                    SwitchListTile(
                      title: const Text('自动同步'),
                      subtitle: const Text('自动同步数据到云端', style: TextStyle(fontSize: 12)),
                      value: settingsProv.autoSync,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) {
                        settingsProv.setAutoSync(v);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('WiFi下同步'),
                      subtitle: const Text('仅在WiFi下同步图片', style: TextStyle(fontSize: 12)),
                      value: settingsProv.wifiSync,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (v) {
                        settingsProv.setWifiSync(v);
                      },
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // 关闭按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 修改密码
  void _showChangePasswordDialog(BuildContext context) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('修改密码'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '原密码',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码',
                  prefixIcon: Icon(Icons.lock_open),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认新密码',
                  prefixIcon: Icon(Icons.lock_open),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              // 验证密码
              if (oldPasswordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入原密码'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              if (newPasswordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('新密码至少6位'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              if (newPasswordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('两次密码不一致'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }

              // 调用修改密码
              final auth = context.read<AuthProvider>();
              final success = auth.changePassword(
                oldPasswordController.text,
                newPasswordController.text,
              );

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? '密码修改成功' : '原密码错误'),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF10B981),
            ),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // 消息通知设置
  void _showNotificationSettings(BuildContext context) {
    // 从 Provider 读取最新值，初始化本地临时状态
    final settings = context.read<SettingsProvider>();
    setState(() {
      _newIssueNotify = settings.newIssueNotify;
      _overdueNotify = settings.overdueNotify;
      _auditNotify = settings.auditNotify;
      _dailyReport = settings.dailyReport;
    });

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final settingsProv = context.read<SettingsProvider>();
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    const Text(
                      '消息通知设置',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('新问题提醒'),
                  subtitle: const Text('有新问题上报时通知', style: TextStyle(fontSize: 12)),
                  value: _newIssueNotify,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (v) {
                    setModalState(() => _newIssueNotify = v);
                    setState(() => _newIssueNotify = v);
                    settingsProv.setNewIssueNotify(v);
                  },
                ),
                SwitchListTile(
                  title: const Text('整改超时提醒'),
                  subtitle: const Text('整改即将超时时提醒', style: TextStyle(fontSize: 12)),
                  value: _overdueNotify,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (v) {
                    setModalState(() => _overdueNotify = v);
                    setState(() => _overdueNotify = v);
                    settingsProv.setOverdueNotify(v);
                  },
                ),
                SwitchListTile(
                  title: const Text('审核结果通知'),
                  subtitle: const Text('问题审核完成时通知', style: TextStyle(fontSize: 12)),
                  value: _auditNotify,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (v) {
                    setModalState(() => _auditNotify = v);
                    setState(() => _auditNotify = v);
                    settingsProv.setAuditNotify(v);
                  },
                ),
                SwitchListTile(
                  title: const Text('日报推送'),
                  subtitle: const Text('每日巡检报告推送', style: TextStyle(fontSize: 12)),
                  value: _dailyReport,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (v) {
                    setModalState(() => _dailyReport = v);
                    setState(() => _dailyReport = v);
                    settingsProv.setDailyReport(v);
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('通知设置已保存'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 语言设置
  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择语言'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(
              title: const Text('简体中文'),
              value: 'zh',
              groupValue: 'zh',
              activeColor: const Color(0xFF10B981),
              onChanged: (v) => Navigator.pop(context),
            ),
            RadioListTile(
              title: const Text('English'),
              value: 'en',
              groupValue: 'zh',
              activeColor: const Color(0xFF10B981),
              onChanged: (v) => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // 帮助与反馈
  void _showHelpDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '帮助与反馈',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            
            // 使用教程
            ExpansionTile(
              leading: const Icon(Icons.school, color: Color(0xFF10B981)),
              title: const Text('使用教程'),
              children: [
                _buildHelpItem('如何上报问题？', '点击底部"上报"按钮，填写问题信息并拍照上传。'),
                _buildHelpItem('如何查看整改进度？', '在"问题"页面点击具体问题，可查看整改进度。'),
                _buildHelpItem('如何导出报表？', '在"统计"页面点击"导出统计报表"按钮。'),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // 常见问题
            ExpansionTile(
              leading: const Icon(Icons.help_outline, color: Color(0xFF10B981)),
              title: const Text('常见问题'),
              children: [
                _buildHelpItem('照片上传失败？', '请检查网络连接，或切换至WiFi网络后重试。'),
                _buildHelpItem('无法登录？', '请联系管理员确认账号状态，或通过"注册"功能重新注册。'),
                _buildHelpItem('数据不同步？', '请检查网络连接，或手动下拉刷新页面。'),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // 反馈按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('反馈功能开发中'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.feedback),
                label: const Text('提交问题反馈'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(String q, String a) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(a, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ],
      ),
    );
  }


  // 关于系统
  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.eco, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('GZ巡查系统'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本: v3.2'),
            SizedBox(height: 8),
            Text('构建: 2026-04-20'),
            SizedBox(height: 8),
            Text('© 2026 冠洲安环部'),
            SizedBox(height: 16),
            Text(
              '本系统用于企业环保问题巡检管理，'
              '支持问题上报、整改跟踪、数据统计等功能。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // 编辑个人信息 - 修复版
  void _showEditProfileDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    
    final nameController = TextEditingController(text: user?.name ?? '');
    final phoneController = TextEditingController(text: user?.phone ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('编辑个人信息'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '姓名',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '手机号',
                prefixIcon: Icon(Icons.phone),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              // 调用更新个人信息（异步）
              final success = await auth.updateProfile(
                name: nameController.text.trim(),
                phone: phoneController.text.trim(),
              );
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? '个人信息已更新' : '更新失败'),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF10B981),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 用户管理 - 管理员功能
  Future<void> _showUserManagement(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    
    // 异步获取初始数据
    final initialUsers = await auth.getPendingUsers();

    if (!context.mounted) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _UserManagementSheet(
        auth: auth,
        initialPendingUsers: initialUsers,
        onAddUser: () {
          Navigator.pop(context);
          _showAddUserDialog(context);
        },
      ),
    );
  }

  // 管理员添加用户
  void _showAddUserDialog(BuildContext context) {
    final usernameController = TextEditingController();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedDept = '安全保卫部';
    String selectedRole = 'inspector';

    final departments = ['安全保卫部', '生产车间', '仓储物流部', '环保部门', '技术部', '设备部'];
    final roles = [
      {'value': 'inspector', 'label': '巡检员'},
      {'value': 'leader', 'label': '部门领导'},
      {'value': 'rectifier', 'label': '整改负责人'},
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_add, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('添加用户'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 姓名（与用户名保持一致，自动同步）
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '姓名 *（用户名将自动与姓名相同）',
                    prefixIcon: Icon(Icons.person),
                    helperText: '用户名和姓名均使用真实姓名',
                  ),
                  onChanged: (val) {
                    // 姓名改变时自动同步到用户名
                    usernameController.text = val.trim();
                  },
                ),
                const SizedBox(height: 12),
                // 手机号单独填写
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '手机号 *',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '初始密码 *',
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedDept,
                  decoration: const InputDecoration(
                    labelText: '部门 *',
                    prefixIcon: Icon(Icons.business),
                  ),
                  items: departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setDialogState(() => selectedDept = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: '角色 *',
                    prefixIcon: Icon(Icons.badge),
                  ),
                  items: roles.map((r) => DropdownMenuItem(value: r['value'], child: Text(r['label']!))).toList(),
                  onChanged: (v) => setDialogState(() => selectedRole = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
                onPressed: () async {
                  if (usernameController.text.isEmpty || nameController.text.isEmpty ||
                      phoneController.text.isEmpty || passwordController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('请填写所有必填项'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  final auth = context.read<AuthProvider>();
                  final success = await auth.addUser(
                    username: usernameController.text.trim(),
                    password: passwordController.text,
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    department: selectedDept,
                    role: selectedRole,
                  );

                  if (success) {
                    // 添加成功：关闭对话框后重新打开用户管理（自动刷新列表）
                    Navigator.pop(context); // 关闭添加对话框
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (context.mounted) {
                        _showUserManagement(context);
                      }
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('用户添加失败: ${auth.error ?? "未知错误"}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF10B981),
              ),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  // 退出登录
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red,
            ),
            child: const Text('确定退出'),
          ),
        ],
      ),
    );
  }
}

// 用户管理底部弹窗组件
class _UserManagementSheet extends StatefulWidget {
  final AuthProvider auth;
  final List<User> initialPendingUsers;
  final VoidCallback onAddUser;

  const _UserManagementSheet({
    required this.auth,
    required this.initialPendingUsers,
    required this.onAddUser,
  });

  @override
  State<_UserManagementSheet> createState() => _UserManagementSheetState();
}

class _UserManagementSheetState extends State<_UserManagementSheet> {
  List<User> _pendingUsers = [];
  List<User> _allUsers = [];
  bool _isLoading = true;
  bool _showAllUsers = true; // 默认显示所有用户（而非待审核）
  String _searchQuery = ''; // 搜索关键词
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pendingUsers = widget.initialPendingUsers;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      print('🔄 开始加载用户列表...');

      // 先获取待审核用户
      final pending = await widget.auth.getPendingUsers();
      print('📋 getPendingUsers 返回: ${pending.length} 个');

      // 获取所有用户
      final all = await widget.auth.fetchAllUsersFromCloud();
      print('📋 fetchAllUsersFromCloud 返回: ${all.length} 个');

      // 详细日志：显示所有用户状态
      for (var u in all) {
        print('   用户: ${u.name} (${u.username}), role=${u.roleName}, status=${u.status}, isActive=${u.isActive}');
      }

      if (mounted) {
        setState(() {
          _pendingUsers = pending;
          // 过滤掉pending状态的用户，但保留其他所有用户（包括admin以外的所有人）
          _allUsers = all.where((u) => u.status != 'pending').toList();
          _isLoading = false;
        });
        print('✅ 用户列表刷新完成: pending=${_pendingUsers.length}, all=${_allUsers.length}');
        for (var u in _allUsers) {
          print('   [显示] ${u.name} (${u.username}), role=${u.roleName}');
        }

        // 显示加载结果提示
        if (_allUsers.isEmpty && all.isNotEmpty) {
          print('⚠️ 警告: all 不为空但 _allUsers 为空！检查过滤条件');
          _showFloatingSnackBar(
            context,
            '⚠️ 数据异常: _allUsers 为空，请检查 status 字段',
            Colors.orange,
            null,
          );
        }
      }
    } catch (e, stack) {
      print('❌ 加载用户失败: $e');
      print('Stack: $stack');
      if (mounted) {
        setState(() => _isLoading = false);
        _showFloatingSnackBar(
          context,
          '❌ 加载失败: $e',
          Colors.red,
          null,
        );
      }
    }
  }

      // 批准用户
  Future<void> _handleApprove(User user, int index) async {
    // 显示加载状态
    setState(() => _isLoading = true);
    
    try {
      print('🔄 开始批准用户: ${user.username}');
      final success = await widget.auth.approveUser(user.username);
      print('📋 approveUser 返回: $success');
      
      // 重新加载列表
      await _loadUsers();
      
      if (mounted) {
        if (success) {
          _showFloatingSnackBar(
            context,
            '✅ 用户 "${user.name}" 已批准！请刷新查看',
            Colors.green,
            null,
          );
        } else {
          _showFloatingSnackBar(
            context,
            '❌ 批准失败: ${widget.auth.error ?? "请检查网络"}',
            Colors.red,
            null,
          );
        }
      }
    } catch (e) {
      print('❌ 批准异常: $e');
      await _loadUsers();
      if (mounted) {
        _showFloatingSnackBar(
          context,
          '❌ 操作异常: $e',
          Colors.red,
          null,
        );
      }
    }
  }

  // 拒绝用户
  Future<void> _handleReject(User user, int index) async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认拒绝'),
        content: Text('确定要拒绝用户 "${user.name}" 的注册申请吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认拒绝'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isLoading = true);
    
    try {
      final success = await widget.auth.rejectUser(user.username);
      
      // 无论成功失败，都重新加载列表
      await _loadUsers();
      
      if (mounted) {
        if (success) {
          _showFloatingSnackBar(
            context,
            '⚠️ 用户 "${user.name}" 已拒绝',
            Colors.orange,
            null,
          );
        } else {
          _showFloatingSnackBar(
            context,
            '❌ 拒绝失败: ${widget.auth.error ?? "请检查网络"}',
            Colors.red,
            null,
          );
        }
      }
    } catch (e) {
      print('❌ 拒绝异常: $e');
      await _loadUsers();
      if (mounted) {
        _showFloatingSnackBar(
          context,
          '❌ 操作异常: $e',
          Colors.red,
          null,
        );
      }
    }
  }

  // 删除用户
  Future<void> _handleDelete(User user, int index) async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要彻底删除用户 "${user.name}" 吗？此操作不可恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isLoading = true);
    
    try {
      final success = await widget.auth.deleteUser(user.username);
      
      // 重新加载列表
      await _loadUsers();
      
      if (mounted) {
        if (success) {
          _showFloatingSnackBar(
            context,
            '🗑️ 用户 "${user.name}" 已删除',
            Colors.red,
            null,
          );
        } else {
          _showFloatingSnackBar(
            context,
            '❌ 删除失败: ${widget.auth.error ?? "请检查网络"}',
            Colors.red,
            null,
          );
        }
      }
    } catch (e) {
      print('❌ 删除异常: $e');
      await _loadUsers();
      if (mounted) {
        _showFloatingSnackBar(
          context,
          '❌ 操作异常: $e',
          Colors.red,
          null,
        );
      }
    }
  }


  // Qi Yong Yong Hu
  Future<void> _handleEnable(User user) async {
    setState(() => _isLoading = true);
    try {
      final success = await widget.auth.enableUser(user.username);
      await _loadUsers();
      if (mounted) {
        if (success) {
          _showFloatingSnackBar(context, '用户 ' + user.name + ' 已启用', Colors.green, null);
        } else {
          _showFloatingSnackBar(context, '启用失败: ' + (widget.auth.error ?? '请检查网络'), Colors.red, null);
        }
      }
    } catch (e) {
      print('启用异常: ' + e.toString());
      await _loadUsers();
      if (mounted) {
        _showFloatingSnackBar(context, '操作异常: ' + e.toString(), Colors.red, null);
      }
    }
  }

  /// 显示浮动 SnackBar（2秒自动消失，点击可跳转）
  void _showFloatingSnackBar(BuildContext context, String message, Color bgColor, VoidCallback? onTap) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: bgColor,
            duration: const Duration(seconds: 2), // 2秒自动消失，方便看清
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            action: onTap != null
                ? SnackBarAction(
                    label: '查看',
                    textColor: Colors.white,
                    onPressed: onTap,
                  )
                : null,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.manage_accounts, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Text(
                  '用户管理',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // 切换按钮
                TextButton.icon(
                  icon: Icon(_showAllUsers ? Icons.pending_actions : Icons.people),
                  label: Text(_showAllUsers ? '待审核' : '所有用户'),
                  onPressed: () {
                    setState(() {
                      _showAllUsers = !_showAllUsers;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.person_add),
                  onPressed: widget.onAddUser,
                  tooltip: '添加用户',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadUsers,
                  tooltip: '刷新',
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索用户姓名/用户名/部门...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
          ),

          // 内容区域
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_showAllUsers)
            _buildAllUsersList(scrollController)
          else
            _buildPendingUsersList(scrollController),
        ],
      ),
    );
  }

  // 待审核用户列表
  Widget _buildPendingUsersList(ScrollController scrollController) {
    if (_pendingUsers.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text('暂无待审核用户'),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
                onPressed: _loadUsers,
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.orange[50],
            child: Row(
              children: [
                Icon(Icons.pending, color: Colors.orange[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  '待审核 (${_pendingUsers.length})',
                  style: TextStyle(color: Colors.orange[700], fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: _pendingUsers.length,
              itemBuilder: (context, index) {
                final user = _pendingUsers[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange[100],
                    child: Text(user.name.isNotEmpty ? user.name.substring(0, 1) : '?'),
                  ),
                  title: Text(user.name),
                  subtitle: Text('${user.department} - ${user.roleName}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => _handleApprove(user, index),
                        tooltip: '批准',
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showEditUserDialog(user),
                        tooltip: '编辑',
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => _handleReject(user, index),
                        tooltip: '拒绝',
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_forever, color: Colors.red[700]),
                        onPressed: () => _handleDelete(user, index),
                        tooltip: '删除',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 所有用户列表
  Widget _buildAllUsersList(ScrollController scrollController) {
    // 应用搜索过滤
    final filteredUsers = _searchQuery.isEmpty
        ? _allUsers
        : _allUsers.where((u) =>
            u.name.toLowerCase().contains(_searchQuery) ||
            u.username.toLowerCase().contains(_searchQuery) ||
            u.department.toLowerCase().contains(_searchQuery) ||
            u.roleName.contains(_searchQuery)
          ).toList();
    
    if (filteredUsers.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty ? '暂无其他用户' : '未找到匹配的用户',
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: const Text('清除搜索'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.people, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  _searchQuery.isEmpty 
                      ? '所有用户 (${_allUsers.length})'
                      : '搜索结果 (${filteredUsers.length}/${_allUsers.length})',
                  style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: filteredUsers.length,
              itemBuilder: (context, index) {
                final user = filteredUsers[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getRoleColor(user.roleName),
                    child: Text(user.name.isNotEmpty ? user.name.substring(0, 1) : '?'),
                  ),
                  title: Row(
                    children: [
                      Text(user.name),
                      const SizedBox(width: 8),
                      _buildStatusBadge(user.status),
                    ],
                  ),
                  subtitle: Text('${user.department} - ${user.roleName}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showEditUserDialog(user),
                        tooltip: '编辑',
                      ),
                      if (user.status == 'disabled') ...[
                        // 已禁用的用户显示启用按钮
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () => _handleEnable(user),
                          tooltip: '启用',
                        ),
                      ] else ...[
                        // 正常用户显示删除按钮
                        IconButton(
                          icon: Icon(Icons.delete_forever, color: Colors.red[700]),
                          onPressed: () => _handleDelete(user, index),
                          tooltip: '删除',
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String roleName) {
    switch (roleName) {
      case '管理员':
        return Colors.red[100]!;
      case '巡检员':
        return Colors.blue[100]!;
      case '整改负责人':
        return Colors.orange[100]!;
      case '督查员':
        return Colors.purple[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String text;
    switch (status) {
      case 'active':
        color = Colors.green;
        text = '已激活';
        break;
      case 'pending':
        color = Colors.orange;
        text = '待审核';
        break;
      case 'disabled':
        color = Colors.red;
        text = '已禁用';
        break;
      default:
        color = Colors.grey;
        text = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  // 编辑用户对话框
  void _showEditUserDialog(User user) {
    final nameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phone);
    final deptController = TextEditingController(text: user.department);
    // user.role 返回 UserRole enum，需要转换为字符串
    String selectedRole = user.role.name;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text('编辑用户 - ${user.username}'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '姓名',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: '电话',
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deptController,
                  decoration: const InputDecoration(
                    labelText: '部门',
                    prefixIcon: Icon(Icons.business),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: '角色',
                    prefixIcon: Icon(Icons.badge),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('管理员')),
                    DropdownMenuItem(value: 'inspector', child: Text('巡检员')),
                    DropdownMenuItem(value: 'rectifier', child: Text('整改负责人')),
                    DropdownMenuItem(value: 'supervisor', child: Text('督查员')),
                    DropdownMenuItem(value: 'viewer', child: Text('只读查看员')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedRole = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _handleEditUser(
                  user,
                  nameController.text,
                  phoneController.text,
                  deptController.text,
                  selectedRole,
                );
              },
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF10B981),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleEditUser(
    User user,
    String name,
    String phone,
    String department,
    String role,
  ) async {
    setState(() => _isLoading = true);

    try {
      final success = await widget.auth.adminUpdateUser(
        username: user.username,
        name: name,
        phone: phone,
        department: department,
        role: role,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ 用户信息已修改并同步到云端'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ 修改失败: ${widget.auth.error ?? "请重试"}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        await _loadUsers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 修改异常: $e'),
            backgroundColor: Colors.red,
          ),
        );
        await _loadUsers();
      }
    }
  }
}

// 我的待整改问题卡片组件
class _MyRectificationCard extends StatefulWidget {
  final String userId;

  const _MyRectificationCard({required this.userId});

  @override
  State<_MyRectificationCard> createState() => _MyRectificationCardState();
}

class _MyRectificationCardState extends State<_MyRectificationCard> {
  List<Issue> _myIssues = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyIssues();
  }

  Future<void> _loadMyIssues() async {
    setState(() => _isLoading = true);

    try {
      final issueProvider = context.read<IssueProvider>();
      await issueProvider.loadIssues();

      // 筛选当前用户负责的问题
      final allIssues = issueProvider.allIssues;
      final myIssues = allIssues.where((issue) {
        return issue.assigneeId == widget.userId &&
               (issue.status == IssueStatus.pending || issue.status == IssueStatus.processing);
      }).toList();

      setState(() {
        _myIssues = myIssues;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 待反馈 = pending 且未超期
    final pendingCount = _myIssues.where((i) => i.status == IssueStatus.pending && !i.isOverdue).length;
    // 待催办 = pending 且已超期
    final overdueCount = _myIssues.where((i) => i.status == IssueStatus.pending && i.isOverdue).length;
    // 待验收 = processing + reviewing
    final processingCount = _myIssues.where((i) => i.status == IssueStatus.processing || i.status == IssueStatus.reviewing).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 统计栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('待反馈', pendingCount, Colors.orange),
                _buildStatItem('待验收', processingCount, Colors.blue),
                _buildStatItem('待催办', overdueCount, Colors.red),
              ],
            ),
          ),

          // 问题列表
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_myIssues.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text('暂无待整改问题', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _myIssues.length > 3 ? 3 : _myIssues.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final issue = _myIssues[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(issue.status).withOpacity(0.2),
                    child: Icon(
                      _getStatusIcon(issue.status),
                      color: _getStatusColor(issue.status),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    issue.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '${issue.categoryName} · ${issue.daysRemaining >= 0 ? '剩余${issue.daysRemaining}天' : '已超时${-issue.daysRemaining}天'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: issue.isOverdue ? Colors.red : Colors.grey[600],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => IssueDetailScreen(issue: issue),
                      ),
                    );
                  },
                );
              },
            ),

          // 查看更多按钮
          if (_myIssues.length > 3)
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请在"问题"页面查看全部'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Text('查看全部 ${_myIssues.length} 项 →'),
            ),
        ],
      ),
    );
  }

  // 辅助方法
  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(IssueStatus status) {
    switch (status) {
      case IssueStatus.pending:
        return Colors.orange;
      case IssueStatus.processing:
        return Colors.blue;
      case IssueStatus.reviewing:
        return Colors.purple;
      case IssueStatus.closed:
        return Colors.green;
    }
  }

  IconData _getStatusIcon(IssueStatus status) {
    switch (status) {
      case IssueStatus.pending:
        return Icons.schedule;
      case IssueStatus.processing:
        return Icons.build;
      case IssueStatus.reviewing:
        return Icons.rate_review;
      case IssueStatus.closed:
        return Icons.check_circle;
    }
  }

  String _getStatusText(IssueStatus status) {
    switch (status) {
      case IssueStatus.pending:
        return '待反馈';
      case IssueStatus.processing:
        return '整改中';
      case IssueStatus.reviewing:
        return '待验收';
      case IssueStatus.closed:
        return '已完成';
    }
  }
}

