// lib/screens/issue_list_screen.dart
// 问题列表页面 - 屏幕自适应版本

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/issue_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/issue.dart';
import '../models/user.dart';
import '../models/chat_message.dart';
import 'issue_detail_screen.dart';
import 'rectification_feedback_screen.dart';

class IssueListScreen extends StatefulWidget {
  const IssueListScreen({super.key});

  @override
  State<IssueListScreen> createState() => _IssueListScreenState();
}

class _IssueListScreenState extends State<IssueListScreen> {
  @override
  void initState() {
    super.initState();
    // 设置当前用户以便进行权限过滤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final issueProvider = context.read<IssueProvider>();
      issueProvider.setCurrentUser(auth.currentUser);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GZ巡查'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: Consumer<IssueProvider>(
        builder: (context, issueProvider, _) {
          return Column(
            children: [
              // 顶部欢迎和统计区域
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                              final user = auth.currentUser;
                      final canRectify = user?.role != UserRole.viewer;
                      
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '欢迎，${user?.name ?? ""}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (canRectify) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          '可整改',
                                          style: TextStyle(color: Colors.white, fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  auth.currentUser?.department ?? '',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                if (canRectify)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                      '显示分配给您的问题',
                                      style: TextStyle(color: Colors.white60, fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.white24,
                            child: Text(
                              auth.currentUser?.name.isNotEmpty == true
                                  ? auth.currentUser!.name.substring(0, 1)
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // 统计卡片 - 屏幕适配
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 360;
                    return Column(
                      children: [
                        // 第一行：整改人视角 + 已完成
                        Row(
                          children: [
                            _buildStatCard('待反馈', issueProvider.pendingCount, Colors.orange, isNarrow, IssueFilterType.pending),
                            SizedBox(width: isNarrow ? 6 : 8),
                            _buildStatCard('已反馈', issueProvider.rectsSubmittedCount, Colors.blue, isNarrow, IssueFilterType.rectsSubmitted),
                            SizedBox(width: isNarrow ? 6 : 8),
                            _buildStatCard('待验收', issueProvider.reviewingCount, Colors.purple, isNarrow, IssueFilterType.reviewing),
                            SizedBox(width: isNarrow ? 6 : 8),
                            _buildStatCard('已完成', issueProvider.closedCount, Colors.green, isNarrow, IssueFilterType.closed),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 第二行：发起人视角 - 待催办（宽卡片，突出显示）
                        _buildUrgeCard(issueProvider.overdueCount, isNarrow),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 筛选状态横幅（当前非"全部"时显示）
              if (issueProvider.filterType != IssueFilterType.all)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getFilterBannerColor(issueProvider.filterType).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _getFilterBannerColor(issueProvider.filterType).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getFilterBannerIcon(issueProvider.filterType),
                        size: 16,
                        color: _getFilterBannerColor(issueProvider.filterType),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getFilterBannerText(issueProvider),
                        style: TextStyle(
                          fontSize: 13,
                          color: _getFilterBannerColor(issueProvider.filterType),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => issueProvider.setFilterType(IssueFilterType.all),
                        child: Row(
                          children: [
                            Text(
                              '清除筛选',
                              style: TextStyle(
                                fontSize: 12,
                                color: _getFilterBannerColor(issueProvider.filterType).withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.close,
                              size: 14,
                              color: _getFilterBannerColor(issueProvider.filterType).withOpacity(0.7),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // 问题列表
              Expanded(
                child: issueProvider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : issueProvider.visibleIssues.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inbox,
                                  size: 64,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '暂无相关问题',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => issueProvider.loadIssues(),
                            child: _buildFilteredIssueList(
                              issueProvider,
                              context.read<AuthProvider>().currentUser,
                            ),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建过滤后的问题列表（权限控制）
  Widget _buildFilteredIssueList(IssueProvider issueProvider, User? user) {
    if (user == null) {
      return const Center(child: Text('请先登录'));
    }

    // 统一使用 Provider 的 visibleIssues 处理所有筛选逻辑
    // visibleIssues 内部已整合了用户角色和筛选类型两层过滤
    List<Issue> filteredIssues = issueProvider.visibleIssues;

    if (filteredIssues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '暂无相关问题',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: filteredIssues.length,
      itemBuilder: (context, index) {
        final issue = filteredIssues[index];
        return _buildIssueCard(context, issue, issueProvider.filterType);
      },
    );
  }

  Widget _buildStatCard(String label, int count, Color color, bool isNarrow, IssueFilterType filterType) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          // 点击后设置筛选并滚动到列表顶部
          context.read<IssueProvider>().setFilterType(filterType);
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isNarrow ? 8 : 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: isNarrow ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: isNarrow ? 10 : 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 待催办卡片（横跨全宽，发起人视角）
  Widget _buildUrgeCard(int count, bool isNarrow) {
    final hasUrge = count > 0;
    return GestureDetector(
      onTap: () {
        final issueProvider = context.read<IssueProvider>();
        final wasAlreadyFiltered = issueProvider.filterType == IssueFilterType.overdue;
        issueProvider.setFilterType(IssueFilterType.overdue);
        if (!wasAlreadyFiltered) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已筛选待催办问题 ($count 项)'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              action: SnackBarAction(
                label: '查看详情',
                textColor: Colors.white,
                onPressed: () {
                  // 滚动到列表顶部
                  // ignore: avoid_print
                },
              ),
            ),
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: isNarrow ? 10 : 12,
          horizontal: 16,
        ),
        decoration: BoxDecoration(
          color: hasUrge ? const Color(0xFFFFF3E0) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: hasUrge
              ? Border.all(color: Colors.orange.shade300, width: 1)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.alarm,
              size: isNarrow ? 16 : 18,
              color: hasUrge ? Colors.orange : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              '待催办',
              style: TextStyle(
                fontSize: isNarrow ? 12 : 13,
                color: hasUrge ? Colors.orange.shade800 : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                fontSize: isNarrow ? 20 : 24,
                fontWeight: FontWeight.bold,
                color: hasUrge ? Colors.deepOrange : Colors.grey,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '项',
              style: TextStyle(
                fontSize: isNarrow ? 12 : 13,
                color: hasUrge ? Colors.orange.shade700 : Colors.grey,
              ),
            ),
            if (hasUrge) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '点击催办',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }


  Widget _buildIssueCard(BuildContext context, Issue issue, [IssueFilterType currentFilter = IssueFilterType.all]) {
    Color statusColor;
    String statusText;

    // 根据筛选类型和业务状态显示标签
    // 关键：只有在"待催办"筛选中，超期的待处理问题才显示"待催办"
    // 在"待反馈"筛选中，即使超期也应显示"待反馈"
    if (issue.status == IssueStatus.closed) {
      statusColor = Colors.green;
      statusText = '已完成';
    } else if (currentFilter == IssueFilterType.overdue && issue.status == IssueStatus.pending) {
      statusColor = Colors.red;
      statusText = '待催办';
    } else if (issue.status == IssueStatus.reviewing) {
      statusColor = Colors.purple;
      statusText = '待验收';
    } else if (issue.status == IssueStatus.processing) {
      statusColor = Colors.orange;
      statusText = '待反馈';
    } else {
      // pending 状态
      statusColor = Colors.orange;
      statusText = '待反馈';
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => IssueDetailScreen(issue: issue),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    issue.categoryName,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              issue.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              issue.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    issue.location,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '责任人: ${issue.assigneeName}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  issue.isOverdue
                      ? '超期${-issue.daysRemaining}天'
                      : '剩余${issue.daysRemaining}天',
                  style: TextStyle(
                    color: issue.isOverdue ? Colors.red : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            
            // 整改人快捷操作按钮
            Consumer<AuthProvider>(
              builder: (context, auth, _) {
                final user = auth.currentUser;
                if (user == null) return const SizedBox.shrink();
                
                // 判断问题是否分配给当前用户（不区分角色，整改负责人、巡查人、督查人均可接受）
                final isMyIssue = issue.assigneeId == user.id ||
                    issue.assigneeId == user.username ||
                    issue.assigneeName == user.name;
                
                // 只要是分配给自己的问题，非viewer角色均可进行整改操作
                final canRectify = user.role != UserRole.viewer;
                
                if (canRectify && isMyIssue) {
                  // 待处理状态：显示"开始整改"按钮
                  if (issue.status == IssueStatus.pending) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _startRectification(context, issue),
                          icon: const Icon(Icons.build, size: 18),
                          label: const Text('开始整改'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    );
                  }
                  
                  // 整改中状态：显示"提交整改反馈"按钮
                  if (issue.status == IssueStatus.processing) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _submitRectificationFeedback(context, issue),
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('提交整改反馈'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    );
                  }
                }
                
                // 安环部/巡检人可以对未处理的问题催办
                final isSupervisor = user.role == UserRole.admin || 
                                    user.role == UserRole.supervisor ||
                                    user.role == UserRole.inspector;
                
                if (isSupervisor && issue.status == IssueStatus.pending && !isMyIssue) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _urgeIssue(context, issue),
                            icon: const Icon(Icons.notification_important, size: 18),
                            label: const Text('催办'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange,
                              side: const BorderSide(color: Colors.orange),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 整改人开始整改
  void _startRectification(BuildContext context, Issue issue) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.build, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('开始整改'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定开始整改 "${issue.title}" 吗？'),
            const SizedBox(height: 12),
            const Text(
              '开始后问题状态将变为"整改中"，请按时完成整工作。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              
              // 更新状态为整改中
              final issueProvider = context.read<IssueProvider>();
              await issueProvider.updateIssueStatus(issue.id, IssueStatus.processing);
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已开始整改，问题已标记为"整改中"'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF10B981),
            ),
            child: const Text('确认开始'),
          ),
        ],
      ),
    );
  }

  /// 催办问题
  void _urgeIssue(BuildContext context, Issue issue) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notification_important, color: Colors.orange),
            SizedBox(width: 8),
            Text('催办问题'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定催办 "${issue.assigneeName}" 尽快处理以下问题？'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issue.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '责任人: ${issue.assigneeName}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              
              // 实际发送催办通知
              final chatProvider = context.read<ChatProvider>();
              final authProvider = context.read<AuthProvider>();
              final currentUser = authProvider.currentUser;
              
              await chatProvider.sendMessage(
                toUserId: issue.assigneeId,
                toUserName: issue.assigneeName,
                content: '【催办提醒】您有一个隐患需要尽快处理：${issue.title}\n\n请及时进行整改！',
                type: MessageType.reminder,
                issueId: issue.id,
                issueTitle: issue.title,
              );
              
              // 发送成功后直接跳转到隐患详情页，不再依赖 SnackBar
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => IssueDetailScreen(issue: issue),
                ),
              ).then((_) {
                // 返回后刷新列表
                context.read<IssueProvider>().loadIssues();
              });
            },
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.orange,
            ),
            child: const Text('确认催办'),
          ),
        ],
      ),
    );
  }

  /// 跳转到提交整改反馈页面
  void _submitRectificationFeedback(BuildContext context, Issue issue) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RectificationFeedbackScreen(
          issueId: issue.id,
          issueTitle: issue.title,
        ),
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    final issueProvider = context.read<IssueProvider>();
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '筛选问题',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          issueProvider.setFilterType(IssueFilterType.all);
                          Navigator.pop(ctx);
                        },
                        child: const Text('清除筛选'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('问题状态'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('全部'),
                        selected: issueProvider.filterType == IssueFilterType.all,
                        onSelected: (selected) {
                          issueProvider.setFilterType(IssueFilterType.all);
                          Navigator.pop(ctx);
                        },
                      ),
                      FilterChip(
                        label: const Text('待反馈'),
                        selected: issueProvider.filterType == IssueFilterType.pending,
                        onSelected: (selected) {
                          issueProvider.setFilterType(IssueFilterType.pending);
                          Navigator.pop(ctx);
                        },
                      ),
                      FilterChip(
                        label: const Text('已反馈'),
                        selected: issueProvider.filterType == IssueFilterType.rectsSubmitted,
                        onSelected: (selected) {
                          issueProvider.setFilterType(IssueFilterType.rectsSubmitted);
                          Navigator.pop(ctx);
                        },
                      ),
                      FilterChip(
                        label: const Text('待验收'),
                        selected: issueProvider.filterType == IssueFilterType.reviewing,
                        onSelected: (selected) {
                          issueProvider.setFilterType(IssueFilterType.reviewing);
                          Navigator.pop(ctx);
                        },
                      ),
                      FilterChip(
                        label: const Text('待催办'),
                        selected: issueProvider.filterType == IssueFilterType.overdue,
                        onSelected: (selected) {
                          issueProvider.setFilterType(IssueFilterType.overdue);
                          Navigator.pop(ctx);
                        },
                      ),
                      FilterChip(
                        label: const Text('已完成'),
                        selected: issueProvider.filterType == IssueFilterType.closed,
                        onSelected: (selected) {
                          issueProvider.setFilterType(IssueFilterType.closed);
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ========== 筛选横幅辅助方法 ==========
  Color _getFilterBannerColor(IssueFilterType type) {
    switch (type) {
      case IssueFilterType.pending:
        return Colors.orange;
      case IssueFilterType.rectsSubmitted:
        return Colors.blue;
      case IssueFilterType.reviewing:
        return Colors.purple;
      case IssueFilterType.overdue:
        return Colors.red;
      case IssueFilterType.closed:
        return Colors.green;
      case IssueFilterType.reported:
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getFilterBannerIcon(IssueFilterType type) {
    switch (type) {
      case IssueFilterType.pending:
        return Icons.pending_actions;
      case IssueFilterType.rectsSubmitted:
        return Icons.check_circle_outline;
      case IssueFilterType.reviewing:
        return Icons.rate_review;
      case IssueFilterType.overdue:
        return Icons.notification_important;
      case IssueFilterType.closed:
        return Icons.check_circle;
      case IssueFilterType.reported:
        return Icons.send;
      default:
        return Icons.filter_list;
    }
  }

  String _getFilterBannerText(IssueProvider provider) {
    final count = provider.visibleIssues.length;
    switch (provider.filterType) {
      case IssueFilterType.pending:
        return '待反馈：查看您作为整改人待处理的问题（$count 项）';
      case IssueFilterType.rectsSubmitted:
        return '已反馈：您已提交整改，等待发起人验收（$count 项）';
      case IssueFilterType.reviewing:
        return '待验收：您发起的问题等待您审批验收（$count 项）';
      case IssueFilterType.overdue:
        return '待催办：您发起的问题，整改人尚未反馈（$count 项）';
      case IssueFilterType.closed:
        return '已完成：您已验收通过的问题（$count 项）';
      case IssueFilterType.reported:
        return '已发起：您发起的所有问题（$count 项）';
      default:
        return '全部问题（$count 项）';
    }
  }
}