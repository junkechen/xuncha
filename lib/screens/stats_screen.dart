// lib/screens/stats_screen.dart
// 统计页面 - 增强版

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:archive/archive_io.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../providers/issue_provider.dart';
import '../providers/auth_provider.dart';
import '../models/issue.dart';
import '../services/cloudbase_service.dart';
import 'issue_detail_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String _selectedPeriod = '本月';
  bool _isExporting = false;

  // 模拟历史数据（实际项目中应从API获取）
  final Map<String, Map<String, int>> _historicalData = {
    '上月': {'total': 45, 'closed': 38, 'pending': 3, 'processing': 4},
    '本月': {'total': 38, 'closed': 28, 'pending': 5, 'processing': 5},
    '本季度': {'total': 120, 'closed': 98, 'pending': 10, 'processing': 12},
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据统计'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('数据已刷新'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<IssueProvider>(
        builder: (context, issueProvider, _) {
          final issues = issueProvider.allIssues;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 时间筛选
                _buildPeriodSelector(),
                const SizedBox(height: 20),

                // 总览卡片
                _buildOverviewCards(issues),
                const SizedBox(height: 24),

                // 同比分析
                _buildComparisonAnalysis(),
                const SizedBox(height: 24),

                // 问题类型分布
                _buildCategoryStats(issues),
                const SizedBox(height: 24),

                // 重复问题分析
                _buildRepeatIssueAnalysis(issues),
                const SizedBox(height: 24),

                // 部门问题统计
                _buildDepartmentStats(issues),
                const SizedBox(height: 24),

                // 整改进度
                _buildProgressAnalysis(issues),
                const SizedBox(height: 24),

                // 导出按钮
                _buildExportSection(issues),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  // 时间段选择器
  Widget _buildPeriodSelector() {
    final periods = ['本周', '本月', '本季度', '本年'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: periods.map((period) {
          final isSelected = _selectedPeriod == period;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriod = period),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  period,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[700],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 总览卡片
  Widget _buildOverviewCards(List<Issue> issues) {
    final total = issues.length;
    final closed = issues.where((i) => i.status == IssueStatus.closed).length;
    // 待验收 = processing + reviewing
    final processing = issues.where((i) => i.status == IssueStatus.processing || i.status == IssueStatus.reviewing).length;
    // 待反馈 = pending 且未超期
    final pending = issues.where((i) => i.status == IssueStatus.pending && !i.isOverdue).length;
    // 待催办 = pending 且已超期
    final overdue = issues.where((i) => i.status == IssueStatus.pending && i.isOverdue).length;
    final closedRate = total > 0 ? (closed / total * 100) : 0.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                '问题总数',
                '$total',
                Icons.assignment,
                const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                '关闭率',
                '${closedRate.toStringAsFixed(1)}%',
                Icons.check_circle,
                Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                '待反馈',
                '$pending',
                Icons.pending_actions,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                '待验收',
                '$processing',
                Icons.engineering,
                Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                '待催办',
                '$overdue',
                Icons.warning_amber,
                Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                '已完成',
                '$closed',
                Icons.check_circle,
                Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 同比分析
  Widget _buildComparisonAnalysis() {
    final currentData = _historicalData[_selectedPeriod] ?? {'total': 0, 'closed': 0, 'pending': 0, 'processing': 0};
    final previousPeriod = _selectedPeriod == '本月' ? '上月' : (_selectedPeriod == '本季度' ? '上季度' : '上期');
    final previousData = _historicalData[previousPeriod] ?? {'total': 0, 'closed': 0, 'pending': 0, 'processing': 0};

    final currentTotal = currentData['total'] ?? 0;
    final previousTotal = previousData['total'] ?? 0;
    final change = previousTotal > 0 ? ((currentTotal - previousTotal) / previousTotal * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Row(
            children: [
              Icon(Icons.trending_up, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text(
                '同比分析',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedPeriod,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      '$currentTotal',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '问题数',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: change < 0 ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      change < 0 ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 16,
                      color: change < 0 ? Colors.green : Colors.red,
                    ),
                    Text(
                      '${change.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: change < 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      previousPeriod,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      '$previousTotal',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '问题数',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: change < 0 ? Colors.green[50] : Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  change < 0 ? Icons.thumb_up : Icons.warning,
                  color: change < 0 ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    change < 0 
                        ? '问题数量同比下降${change.abs().toStringAsFixed(1)}%，整改效果良好！'
                        : '问题数量同比上升${change.abs().toStringAsFixed(1)}%，需加强巡检力度。',
                    style: TextStyle(
                      color: change < 0 ? Colors.green[700] : Colors.orange[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 问题类型统计
  Widget _buildCategoryStats(List<Issue> issues) {
    final categoryCount = <IssueCategory, int>{};
    for (var issue in issues) {
      categoryCount[issue.category] = (categoryCount[issue.category] ?? 0) + 1;
    }
    
    final sortedCategories = categoryCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Row(
            children: [
              Icon(Icons.pie_chart, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text(
                '问题类型分布',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...sortedCategories.map((entry) {
            final percentage = issues.isNotEmpty ? (entry.value / issues.length * 100) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getCategoryColor(entry.key),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_getCategoryName(entry.key)),
                        ],
                      ),
                      Text(
                        '${entry.value} (${percentage.toStringAsFixed(1)}%)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getCategoryColor(entry.key),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // 重复问题分析
  Widget _buildRepeatIssueAnalysis(List<Issue> issues) {
    // 统计相同位置的问题
    final locationCount = <String, List<Issue>>{};
    for (var issue in issues) {
      locationCount[issue.location] = (locationCount[issue.location] ?? [])..add(issue);
    }
    
    final repeatIssues = locationCount.entries
        .where((e) => e.value.length > 1)
        .toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
              const Icon(Icons.warning_amber, color: Colors.orange),
              const SizedBox(width: 8),
              const Text(
                '重复问题分析',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (repeatIssues.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${repeatIssues.length}处',
                    style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (repeatIssues.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '暂无重复问题，各区域检查效果良好！',
                      style: TextStyle(color: Colors.green),
                    ),
                  ),
                ],
              ),
            )
          else
            ...repeatIssues.take(3).map((entry) {
              return InkWell(
                onTap: () => _showRepeatIssueDetail(context, entry.key, entry.value),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.orange),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${entry.value.length}次',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right, color: Colors.white, size: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '最近问题：${entry.value.last.title}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      Text(
                        '首次发现：${DateFormat('yyyy-MM-dd').format(entry.value.first.createdAt)}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // 部门（车间）问题统计 - 改为可点击查看详情
  Widget _buildDepartmentStats(List<Issue> issues) {
    final deptCount = <String, List<Issue>>{};
    for (var issue in issues) {
      // 如果 department 为空，尝试从标题提取车间名称（新增问题时标题=部门名）
      String dept = issue.department;
      if (dept.isEmpty) {
        // 常见车间列表，用于匹配
        final knownDepts = ['安全保卫部', '环保部门', '仓储物流部', '质量管理部门', '设备管理部门',
          '酸轧车间', '连轧一车间', '连退车间', '剪配车间', '锌锭车间', '镀锌一车间', '镀锌二车间',
          '彩涂一车间', '彩涂二车间', '公辅车间', '热电车间', '稀土车间', '东舜', '未分配部门'];
        for (var d in knownDepts) {
          if (issue.title.contains(d)) {
            dept = d;
            break;
          }
        }
      }
      deptCount[dept] = (deptCount[dept] ?? [])..add(issue);
    }
    
    final sortedDepts = deptCount.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
              const Icon(Icons.business, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              const Text(
                '车间问题数量排名',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.touch_app, size: 16, color: Colors.grey),
              const Spacer(),
              if (sortedDepts.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '共${sortedDepts.length}个车间',
                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '点击可查看该车间所有问题详情',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (sortedDepts.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '暂无问题数据',
                      style: TextStyle(color: Colors.green),
                    ),
                  ),
                ],
              ),
            )
          else
            ...sortedDepts.take(5).toList().asMap().entries.map((mapEntry) {
              final index = mapEntry.key;
              final entry = mapEntry.value;
              final percentage = issues.isNotEmpty ? (entry.value.length / issues.length * 100) : 0.0;
              final isUnassigned = entry.key == '未分配部门';
              return InkWell(
                onTap: () => _showDepartmentIssueDetail(context, entry.key, entry.value),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isUnassigned ? Colors.grey : const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: isUnassigned ? Colors.grey : Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isUnassigned 
                                  ? Colors.grey.withOpacity(0.1)
                                  : const Color(0xFF10B981).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${entry.value.length}个问题',
                              style: TextStyle(
                                color: isUnassigned ? Colors.grey : const Color(0xFF10B981),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${percentage.toStringAsFixed(1)}%)',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: isUnassigned ? Colors.grey[300] : Colors.grey, size: 20),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isUnassigned ? Colors.grey : const Color(0xFF10B981),
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
  
  // 显示车间问题详情弹窗
  void _showDepartmentIssueDetail(BuildContext context, String department, List<Issue> issues) {
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
        builder: (_, controller) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.business, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '车间: $department',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${issues.length}个问题',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.all(16),
                itemCount: issues.length,
                itemBuilder: (_, index) {
                  final issue = issues[index];
                  return _buildIssueCard(context, issue);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 显示重复问题详情弹窗
  void _showRepeatIssueDetail(BuildContext context, String location, List<Issue> issues) {
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
        builder: (_, controller) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '位置: $location',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '重复${issues.length}次',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.all(16),
                itemCount: issues.length,
                itemBuilder: (_, index) {
                  final issue = issues[index];
                  return _buildIssueCard(context, issue);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 构建问题卡片
  Widget _buildIssueCard(BuildContext parentContext, Issue issue) {
    Color statusColor;
    String statusText;

    // 根据新的业务逻辑显示状态
    if (issue.status == IssueStatus.closed) {
      statusColor = Colors.green;
      statusText = '已完成';
    } else if (issue.isOverdue && issue.status == IssueStatus.pending) {
      statusColor = Colors.red;
      statusText = '待催办';
    } else if (issue.status == IssueStatus.reviewing) {
      statusColor = Colors.purple;
      statusText = '待验收';
    } else if (issue.status == IssueStatus.processing) {
      statusColor = Colors.blue;
      statusText = '待验收'; // processing 也在"待验收"统计中
    } else {
      // pending 状态
      statusColor = Colors.orange;
      statusText = '待反馈';
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.pop(parentContext);
          Navigator.push(
            parentContext,
            MaterialPageRoute(
              builder: (ctx) => IssueDetailScreen(issue: issue),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      issue.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.category, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    issue.categoryName,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.person, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    issue.assigneeName.isNotEmpty ? issue.assigneeName : '未分配',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('yyyy-MM-dd HH:mm').format(issue.createdAt),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 整改进度分析
  Widget _buildProgressAnalysis(List<Issue> issues) {
    // 待反馈 = pending 且未超期
    final pending = issues.where((i) => i.status == IssueStatus.pending && !i.isOverdue).length;
    // 待催办 = pending 且已超期
    final overdue = issues.where((i) => i.status == IssueStatus.pending && i.isOverdue).length;
    // 待验收 = processing + reviewing
    final processing = issues.where((i) => i.status == IssueStatus.processing || i.status == IssueStatus.reviewing).length;
    // 已完成 = closed
    final closed = issues.where((i) => i.status == IssueStatus.closed).length;
    final total = issues.isNotEmpty ? issues.length : 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Row(
            children: [
              Icon(Icons.linear_scale, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text(
                '整改进度分析',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 24,
              child: Row(
                children: [
                  Expanded(
                    flex: pending > 0 ? pending : 0,
                    child: Container(color: Colors.orange),
                  ),
                  Expanded(
                    flex: overdue > 0 ? overdue : 0,
                    child: Container(color: Colors.red),
                  ),
                  Expanded(
                    flex: processing > 0 ? processing : 0,
                    child: Container(color: Colors.blue),
                  ),
                  Expanded(
                    flex: closed > 0 ? closed : 0,
                    child: Container(color: Colors.green),
                  ),
                  if (issues.isEmpty)
                    Expanded(child: Container(color: Colors.grey[300])),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 图例
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem('待反馈', Colors.orange, pending),
              _buildLegendItem('待催办', Colors.red, overdue),
              _buildLegendItem('待验收', Colors.blue, processing),
              _buildLegendItem('已完成', Colors.green, closed),
            ],
          ),
        ],
      ),
    );
  }

  // 导出功能
  Widget _buildExportSection(List<Issue> issues) {
    return Column(
      children: [
        // Excel导出按钮
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isExporting ? null : () => _exportReport(issues),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isExporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.table_chart),
                      SizedBox(width: 8),
                      Text('导出Excel台账', style: TextStyle(fontSize: 16)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        // PDF导出按钮
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isExporting ? null : () => _exportPdfReports(issues),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isExporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf),
                      SizedBox(width: 8),
                      Text('导出PDF报告（ZIP打包）', style: TextStyle(fontSize: 16)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Excel：含问题详情、整改反馈、驳回记录、验收意见\nZIP图文：每个问题一份HTML报告，浏览器打开可查看照片\nPDF：每个问题一份PDF，按车间+问题名命名，字母排序',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  // 执行导出 - 生成Excel文件（工作留痕版，含完整闭环管理内容）
  Future<void> _exportReport(List<Issue> issues) async {
    setState(() => _isExporting = true);

    // 进度提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏳ 正在刷新照片链接，请稍候...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 60),
        ),
      );
    }

    try {
      final cloudService = CloudBaseService.instance;
      final excelWorkbook = excel_pkg.Excel.createExcel();
      final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
      final dateOnly = DateFormat('yyyy-MM-dd');
      final now = DateTime.now();

      // ============================================================
      // 辅助函数：刷新照片URL（cloud:// → HTTP，普通HTTP保留）
      // 返回已刷新的 URL 列表；失败的条目保留原值
      // ============================================================
      Future<List<String>> refreshPhotoUrls(List<String> urls) async {
        final result = <String>[];
        for (final url in urls) {
          if (url.isEmpty) continue;
          if (url.startsWith('cloud://')) {
            final fresh = await cloudService.getFreshPhotoUrl(url);
            result.add(fresh ?? url);
          } else {
            result.add(url);
          }
        }
        return result;
      }

      // 辅助函数：将 URL 列表写为 HYPERLINK 公式单元格
      // 每张照片写到独立列（最多支持 maxPhotos 张）
      void writePhotoHyperlinks(
        excel_pkg.Sheet sheet,
        int rowIdx,
        int startCol,
        List<String> photoUrls,
        int maxPhotos,
      ) {
        for (var i = 0; i < maxPhotos; i++) {
          final cell = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(
            columnIndex: startCol + i,
            rowIndex: rowIdx,
          ));
          if (i < photoUrls.length && photoUrls[i].isNotEmpty) {
            final url = photoUrls[i];
            // 只写入有效的 HTTP/HTTPS URL；过滤掉 cloud:// 等无效格式
            if (url.startsWith('http://') || url.startsWith('https://')) {
              // 转义URL中的双引号，避免破坏 HYPERLINK 公式
              final safeUrl = url.replaceAll('"', '""');
              // 用 HYPERLINK 公式使单元格可点击
              cell.value = excel_pkg.FormulaCellValue('HYPERLINK("$safeUrl","照片${i + 1}")');
              // 设置超链接样式：蓝色+下划线
              cell.cellStyle = excel_pkg.CellStyle(
                fontColorHex: excel_pkg.ExcelColor.fromHexString('#0563C1'),
                underline: excel_pkg.Underline.Single,
              );
            } else {
              // URL无效（如 cloud:// 刷新失败），显示提示
              cell.value = excel_pkg.TextCellValue('(链接失效)');
              cell.cellStyle = excel_pkg.CellStyle(fontColorHex: excel_pkg.ExcelColor.fromHexString('#999999'));
            }
          } else {
            cell.value = excel_pkg.TextCellValue('');
          }
        }
      }

      // ============================================================
      // 预刷新所有照片 URL（统一处理，避免重复调用云端）
      // ============================================================
      // key: issueId, value: {问题照片列表, 每次整改照片列表}
      final Map<String, List<String>> refreshedIssuePhotos = {};
      // key: issueId_rectIdx, value: 照片列表
      final Map<String, List<String>> refreshedRectPhotos = {};

      for (final issue in issues) {
        // 刷新问题现场照片
        if (issue.photos.isNotEmpty) {
          refreshedIssuePhotos[issue.id] = await refreshPhotoUrls(issue.photos);
        }
        // 刷新每次整改照片
        if (issue.rectificationHistory.isNotEmpty) {
          for (var i = 0; i < issue.rectificationHistory.length; i++) {
            final record = issue.rectificationHistory[i];
            if (record.photos.isNotEmpty) {
              refreshedRectPhotos['${issue.id}_$i'] = await refreshPhotoUrls(record.photos);
            }
          }
        } else if (issue.rectificationPhotos.isNotEmpty) {
          // 旧版单条整改照片
          refreshedRectPhotos['${issue.id}_0'] = await refreshPhotoUrls(issue.rectificationPhotos);
        }
      }

      // 统计最大照片数（用于动态列头）
      final maxIssuePics = issues.fold<int>(0,
          (m, i) => (refreshedIssuePhotos[i.id]?.length ?? 0) > m ? (refreshedIssuePhotos[i.id]?.length ?? 0) : m).clamp(1, 6);
      final maxRectPics = (() {
        int m = 0;
        for (final v in refreshedRectPhotos.values) {
          if (v.length > m) m = v.length;
        }
        return m.clamp(1, 6);
      })();

      // ============================================================
      // 工作表1: 问题闭环台账（工作留痕核心表）
      // ============================================================
      final sheet1 = excelWorkbook['问题闭环台账'];
      final headers1Base = [
        '序号', '问题编号', '问题标题', '问题详情描述',
        '问题位置', '问题类型', '严重程度', '所属部门',
        '上报人', '整改责任人', '整改截止日期',
        '当前状态', '最新整改反馈', '整改反馈时间',
        '验收意见', '完成时间',
        '整改照片数量',
        '驳回次数', '创建时间', '最后更新时间',
      ];
      // 动态添加照片列头（问题照片放在末尾固定列）
      final picHeaders1 = List.generate(maxIssuePics, (i) => '问题照片${i + 1}');
      final headers1 = [...headers1Base, ...picHeaders1];

      for (var i = 0; i < headers1.length; i++) {
        final cell = sheet1.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel_pkg.TextCellValue(headers1[i]);
        cell.cellStyle = excel_pkg.CellStyle(bold: true, backgroundColorHex: excel_pkg.ExcelColor.fromHexString('#D9EAD3'));
      }

      for (var rowIdx = 0; rowIdx < issues.length; rowIdx++) {
        final issue = issues[rowIdx];

        // 取最新整改反馈（rectificationHistory 最后一条，fallback rectificationNote）
        String latestRectNote = '';
        String latestRectTime = '';
        if (issue.rectificationHistory.isNotEmpty) {
          final latest = issue.rectificationHistory.last;
          latestRectNote = latest.description;
          latestRectTime = dateFormat.format(latest.timestamp);
        } else if (issue.rectificationNote != null && issue.rectificationNote!.isNotEmpty) {
          latestRectNote = issue.rectificationNote!;
        }

        // 验收意见（acceptanceNote）
        final acceptNote = issue.acceptanceNote ?? '';

        // 完成时间
        final closedTime = issue.closedAt != null ? dateFormat.format(issue.closedAt!) : '';

        // 驳回次数（rejectionHistory 优先，fallback rejectionNote 是否有值）
        final rejectionCount = issue.rejectionHistory.isNotEmpty
            ? issue.rejectionHistory.length
            : (issue.rejectionNote != null && issue.rejectionNote!.isNotEmpty ? 1 : 0);

        // 整改照片数量
        final rectPicCount = issue.rectificationHistory.isNotEmpty
            ? issue.rectificationHistory.fold<int>(0, (sum, r) => sum + r.photos.length)
            : issue.rectificationPhotos.length;

        final row1Data = [
          (rowIdx + 1).toString(),
          issue.id,
          issue.title,
          issue.description,
          issue.location,
          _getCategoryName(issue.category),
          _getSeverityName(issue.severity),
          issue.department,
          issue.reporterName,
          issue.assigneeName,
          dateOnly.format(issue.deadline),
          _getStatusName(issue.status),
          latestRectNote,
          latestRectTime,
          acceptNote,
          closedTime,
          rectPicCount.toString(),
          rejectionCount.toString(),
          dateFormat.format(issue.createdAt),
          dateFormat.format(issue.updatedAt),
        ];

        for (var colIdx = 0; colIdx < row1Data.length; colIdx++) {
          final cell = sheet1.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIdx + 1));
          cell.value = excel_pkg.TextCellValue(row1Data[colIdx]);
        }

        // 写入问题照片超链接（动态列）
        final picUrls = refreshedIssuePhotos[issue.id] ?? [];
        writePhotoHyperlinks(sheet1, rowIdx + 1, row1Data.length, picUrls, maxIssuePics);
      }

      // ============================================================
      // 工作表2: 整改过程记录（每次整改单独一行，支持多次整改追溯）
      //          照片列改为可点击超链接
      // ============================================================
      final sheet2 = excelWorkbook['整改过程记录'];
      final headers2Base = [
        '序号', '问题编号', '问题标题', '所属部门',
        '整改责任人', '整改次数', '整改时间',
        '整改反馈内容', '整改照片数量',
      ];
      final picHeaders2 = List.generate(maxRectPics, (i) => '整改照片${i + 1}');
      final headers2 = [...headers2Base, ...picHeaders2];

      for (var i = 0; i < headers2.length; i++) {
        final cell = sheet2.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel_pkg.TextCellValue(headers2[i]);
        cell.cellStyle = excel_pkg.CellStyle(bold: true, backgroundColorHex: excel_pkg.ExcelColor.fromHexString('#CFE2F3'));
      }

      var rectRowIdx = 1;
      var rectSeq = 0;
      for (final issue in issues) {
        if (issue.rectificationHistory.isNotEmpty) {
          // 多次整改历史（新版数据）
          for (var i = 0; i < issue.rectificationHistory.length; i++) {
            rectSeq++;
            final record = issue.rectificationHistory[i];
            final picUrls = refreshedRectPhotos['${issue.id}_$i'] ?? [];
            final row2Data = [
              rectSeq.toString(),
              issue.id,
              issue.title,
              issue.department,
              record.submitterName.isNotEmpty ? record.submitterName : issue.assigneeName,
              (i + 1).toString(),
              dateFormat.format(record.timestamp),
              record.description,
              picUrls.length.toString(),
            ];
            for (var colIdx = 0; colIdx < row2Data.length; colIdx++) {
              sheet2.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rectRowIdx)).value =
                  excel_pkg.TextCellValue(row2Data[colIdx]);
            }
            // 写入整改照片超链接（动态列）
            writePhotoHyperlinks(sheet2, rectRowIdx, row2Data.length, picUrls, maxRectPics);
            rectRowIdx++;
          }
        } else if (issue.rectificationNote != null && issue.rectificationNote!.isNotEmpty) {
          // 兼容旧版单条整改记录
          rectSeq++;
          final picUrls = refreshedRectPhotos['${issue.id}_0'] ?? [];
          final row2Data = [
            rectSeq.toString(),
            issue.id,
            issue.title,
            issue.department,
            issue.assigneeName,
            '1',
            dateFormat.format(issue.updatedAt),
            issue.rectificationNote!,
            picUrls.length.toString(),
          ];
          for (var colIdx = 0; colIdx < row2Data.length; colIdx++) {
            sheet2.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rectRowIdx)).value =
                excel_pkg.TextCellValue(row2Data[colIdx]);
          }
          // 写入整改照片超链接
          writePhotoHyperlinks(sheet2, rectRowIdx, row2Data.length, picUrls, maxRectPics);
          rectRowIdx++;
        }
      }

      // ============================================================
      // 工作表3: 驳回记录（每次驳回单独成行，完整保留追溯链）
      // ============================================================
      final sheet3 = excelWorkbook['驳回记录'];
      final headers3 = [
        '序号', '问题编号', '问题标题', '所属部门',
        '整改责任人', '驳回次数', '驳回时间',
        '驳回人', '驳回意见',
      ];
      for (var i = 0; i < headers3.length; i++) {
        final cell = sheet3.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel_pkg.TextCellValue(headers3[i]);
        cell.cellStyle = excel_pkg.CellStyle(bold: true, backgroundColorHex: excel_pkg.ExcelColor.fromHexString('#FCE5CD'));
      }

      var rejRowIdx = 1;
      var rejSeq = 0;
      for (final issue in issues) {
        if (issue.rejectionHistory.isNotEmpty) {
          // 多次驳回历史（新版数据）
          for (var i = 0; i < issue.rejectionHistory.length; i++) {
            rejSeq++;
            final record = issue.rejectionHistory[i];
            final row3Data = [
              rejSeq.toString(),
              issue.id,
              issue.title,
              issue.department,
              issue.assigneeName,
              (i + 1).toString(),
              dateFormat.format(record.timestamp),
              record.reviewerName,
              record.note,
            ];
            for (var colIdx = 0; colIdx < row3Data.length; colIdx++) {
              sheet3.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rejRowIdx)).value =
                  excel_pkg.TextCellValue(row3Data[colIdx]);
            }
            rejRowIdx++;
          }
        } else if (issue.rejectionNote != null && issue.rejectionNote!.isNotEmpty) {
          // 兼容旧版单条驳回记录
          rejSeq++;
          final row3Data = [
            rejSeq.toString(),
            issue.id,
            issue.title,
            issue.department,
            issue.assigneeName,
            '1',
            dateFormat.format(issue.updatedAt),
            issue.reporterName,
            issue.rejectionNote!,
          ];
          for (var colIdx = 0; colIdx < row3Data.length; colIdx++) {
            sheet3.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rejRowIdx)).value =
                excel_pkg.TextCellValue(row3Data[colIdx]);
          }
          rejRowIdx++;
        }
      }

      // ============================================================
      // 工作表4: 统计汇总
      // ============================================================
      final sheet4 = excelWorkbook['统计汇总'];

      void _setCell(int col, int row, String text, {bool bold = false}) {
        final cell = sheet4.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        cell.value = excel_pkg.TextCellValue(text);
        if (bold) cell.cellStyle = excel_pkg.CellStyle(bold: true);
      }

      _setCell(0, 0, 'GZ 环保巡查整改管理统计报表', bold: true);
      _setCell(0, 1, '统计周期:');
      _setCell(1, 1, _selectedPeriod);
      _setCell(0, 2, '生成时间:');
      _setCell(1, 2, dateFormat.format(now));
      _setCell(0, 3, '导出人:');
      _setCell(1, 3, '统计');

      _setCell(0, 5, '【总体统计】', bold: true);
      final closedCount = issues.where((i) => i.status == IssueStatus.closed).length;
      final processingCount = issues.where((i) => i.status == IssueStatus.processing).length;
      final pendingCount = issues.where((i) => i.status == IssueStatus.pending).length;
      final reviewingCount = issues.where((i) => i.status == IssueStatus.reviewing).length;
      final overdueCount = issues.where((i) => i.status == IssueStatus.pending && i.isOverdue).length;
      final closedRate = issues.isNotEmpty ? (closedCount / issues.length * 100) : 0.0;

      final summaryRows = [
        ['问题总数', issues.length.toString()],
        ['已完成', closedCount.toString()],
        ['完成率', '${closedRate.toStringAsFixed(1)}%'],
        ['待反馈', pendingCount.toString()],
        ['整改中/待验收', (processingCount + reviewingCount).toString()],
        ['已超期未整改', overdueCount.toString()],
        ['累计整改记录数', rectSeq.toString()],
        ['累计驳回记录数', rejSeq.toString()],
      ];
      for (var i = 0; i < summaryRows.length; i++) {
        _setCell(0, 6 + i, summaryRows[i][0]);
        _setCell(1, 6 + i, summaryRows[i][1]);
      }

      _setCell(0, 6 + summaryRows.length + 1, '【问题类型分布】', bold: true);
      final categoryCount = <IssueCategory, int>{};
      for (var issue in issues) {
        categoryCount[issue.category] = (categoryCount[issue.category] ?? 0) + 1;
      }
      var catRowBase = 6 + summaryRows.length + 2;
      for (var entry in categoryCount.entries) {
        _setCell(0, catRowBase, _getCategoryName(entry.key));
        _setCell(1, catRowBase, entry.value.toString());
        catRowBase++;
      }

      _setCell(0, catRowBase + 1, '【部门问题统计】', bold: true);
      final deptCount = <String, int>{};
      for (var issue in issues) {
        final dept = issue.department.isNotEmpty ? issue.department : '未分配';
        deptCount[dept] = (deptCount[dept] ?? 0) + 1;
      }
      var deptRowBase = catRowBase + 2;
      for (var entry in deptCount.entries) {
        _setCell(0, deptRowBase, entry.key);
        _setCell(1, deptRowBase, entry.value.toString());
        deptRowBase++;
      }

      // 删除默认空白 Sheet（避免生成多余工作表）
      try { excelWorkbook.delete('Sheet1'); } catch (_) {}

      // 保存并分享
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'GZ巡查整改台账_${DateFormat('yyyyMMdd_HHmmss').format(now)}.xlsx';
      final filePath = '${directory.path}/$fileName';

      final fileBytes = excelWorkbook.encode();
      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);

        // 关闭"正在刷新"提示
        if (mounted) ScaffoldMessenger.of(context).clearSnackBars();

        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'GZ环保巡查整改台账（工作留痕版）\n'
              '共 ${issues.length} 条问题，'
              '完成率 ${closedRate.toStringAsFixed(1)}%\n'
              '生成时间：${dateFormat.format(now)}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 台账已导出（${issues.length}条问题 | $rectSeq条整改 | $rejSeq条驳回）'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  // ============================================================
  // ZIP打包导出：每个问题生成一份HTML图文报告，打包成ZIP
  // ============================================================
  Future<void> _exportZipReport(List<Issue> issues) async {
    if (issues.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可导出的问题'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() => _isExporting = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏳ 正在生成图文报告，请稍候...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 60),
        ),
      );
    }

    try {
      final cloudService = CloudBaseService.instance;
      final tempDir = await getTemporaryDirectory();
      final exportDir = Directory('${tempDir.path}/env_export_${DateTime.now().millisecondsSinceEpoch}');
      await exportDir.create(recursive: true);

      final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
      final dateOnly = DateFormat('yyyy-MM-dd');

      // 刷新所有照片URL
      Future<List<String>> refreshPhotoUrls(List<String> urls) async {
        final result = <String>[];
        for (final url in urls) {
          if (url.isEmpty) continue;
          if (url.startsWith('cloud://')) {
            final fresh = await cloudService.getFreshPhotoUrl(url);
            if (fresh != null && fresh.startsWith('http')) result.add(fresh);
          } else if (url.startsWith('http')) {
            result.add(url);
          }
        }
        return result;
      }

      // 为每个问题生成HTML报告
      var processedCount = 0;
      for (final issue in issues) {
        final issueDir = Directory('${exportDir.path}/${issue.id}');
        await issueDir.create();

        // 刷新问题照片URL
        final issuePhotoUrls = await refreshPhotoUrls(issue.photos);

        // 刷新整改照片URL
        List<Map<String, dynamic>> rectificationData = [];
        if (issue.rectificationHistory.isNotEmpty) {
          for (var i = 0; i < issue.rectificationHistory.length; i++) {
            final record = issue.rectificationHistory[i];
            final photos = await refreshPhotoUrls(record.photos);
            rectificationData.add({
              'round': i + 1,
              'time': dateFormat.format(record.timestamp),
              'submitter': record.submitterName,
              'description': record.description,
              'photos': photos,
            });
          }
        } else if (issue.rectificationNote != null && issue.rectificationNote!.isNotEmpty) {
          final photos = await refreshPhotoUrls(issue.rectificationPhotos);
          rectificationData.add({
            'round': 1,
            'time': dateFormat.format(issue.updatedAt),
            'submitter': issue.assigneeName,
            'description': issue.rectificationNote!,
            'photos': photos,
          });
        }

        // 刷新驳回记录
        List<Map<String, dynamic>> rejectionData = [];
        if (issue.rejectionHistory.isNotEmpty) {
          for (var i = 0; i < issue.rejectionHistory.length; i++) {
            final record = issue.rejectionHistory[i];
            rejectionData.add({
              'round': i + 1,
              'time': dateFormat.format(record.timestamp),
              'reviewer': record.reviewerName,
              'reason': record.note,
            });
          }
        } else if (issue.rejectionNote != null && issue.rejectionNote!.isNotEmpty) {
          rejectionData.add({
            'round': 1,
            'time': dateFormat.format(issue.updatedAt),
            'reviewer': issue.reporterName,
            'reason': issue.rejectionNote!,
          });
        }

        // 生成HTML
        final html = _buildIssueHtml(
          issue: issue,
          issuePhotoUrls: issuePhotoUrls,
          rectificationData: rectificationData,
          rejectionData: rejectionData,
          dateFormat: dateFormat,
          dateOnly: dateOnly,
        );

        final htmlFile = File('${issueDir.path}/report.html');
        await htmlFile.writeAsString(html, encoding: utf8);
        processedCount++;
      }

      // 打包成ZIP
      final zipPath = '${tempDir.path}/env_reports_${DateTime.now().millisecondsSinceEpoch}.zip';
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      await encoder.addDirectory(exportDir);
      encoder.close();

      // 清理临时目录
      try { await exportDir.delete(recursive: true); } catch (_) {}

      // 分享ZIP
      await Share.shareXFiles(
        [XFile(zipPath)],
        text: 'GZ环保巡查图文报告\n共 $processedCount 条问题，每份报告可浏览器打开查看照片',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已导出 $processedCount 条问题的图文报告'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 生成单个问题的HTML报告
  String _buildIssueHtml({
    required Issue issue,
    required List<String> issuePhotoUrls,
    required List<Map<String, dynamic>> rectificationData,
    required List<Map<String, dynamic>> rejectionData,
    required DateFormat dateFormat,
    required DateFormat dateOnly,
  }) {
    String statusColor;
    switch (issue.status.toString()) {
      case 'IssueStatus.closed':
      case 'closed':
        statusColor = '#22C55E';
        break;
      case 'IssueStatus.reviewing':
      case 'reviewing':
        statusColor = '#3B82F6';
        break;
      case 'IssueStatus.pending':
      case 'pending':
        statusColor = '#F97316';
        break;
      default:
        statusColor = '#6B7280';
    }

    String statusText;
    switch (issue.status.toString()) {
      case 'IssueStatus.closed': case 'closed': statusText = '已完成'; break;
      case 'IssueStatus.reviewing': case 'reviewing': statusText = '待验收'; break;
      case 'IssueStatus.pending': case 'pending': statusText = '待整改'; break;
      default: statusText = issue.status.toString();
    }

    String categoryName;
    switch (issue.category.toString()) {
      case 'IssueCategory.safety': case 'safety': categoryName = '安全隐患'; break;
      case 'IssueCategory.environment': case 'environment': categoryName = '环保问题'; break;
      case 'IssueCategory.quality': case 'quality': categoryName = '质量问题'; break;
      case 'IssueCategory.other': case 'other': categoryName = '其他'; break;
      default: categoryName = issue.category.toString();
    }

    String severityName;
    switch (issue.severity.toString()) {
      case 'IssueSeverity.critical': case 'critical': severityName = '严重'; break;
      case 'IssueSeverity.high': case 'high': severityName = '高'; break;
      case 'IssueSeverity.medium': case 'medium': severityName = '中'; break;
      case 'IssueSeverity.low': case 'low': severityName = '低'; break;
      default: severityName = issue.severity.toString();
    }

    // 问题照片HTML
    final issuePhotosHtml = issuePhotoUrls.isEmpty
        ? '<p style="color:#999">无照片</p>'
        : issuePhotoUrls.map((url) => '<img src="$url" style="max-width:100%;margin:8px 0;border-radius:4px;border:1px solid #ddd;" />').join('\n');

    // 整改记录HTML
    final rectHtml = rectificationData.isEmpty
        ? '<p style="color:#999">暂无整改反馈</p>'
        : rectificationData.map((r) {
            final photos = (r['photos'] as List<String>).map((url) =>
              '<img src="$url" style="max-width:100%;margin:6px 0;border-radius:4px;border:1px solid #ddd;" />'
            ).join('\n');
            return '''
              <div style="margin:10px 0;padding:10px;background:#f0fdf4;border-radius:6px;border-left:4px solid #22C55E;">
                <p><strong>第${r['round']}次整改</strong> · ${r['time']} · 整改人：${r['submitter']}</p>
                <p style="margin:6px 0;">${r['description']}</p>
                ${(r['photos'] as List<String>).isNotEmpty ? '<div>$photos</div>' : '<p style="color:#999;font-size:12px;">无整改照片</p>'}
              </div>
            ''';
          }).join('\n');

    // 驳回记录HTML
    final rejectHtml = rejectionData.isEmpty
        ? '<p style="color:#999">无驳回记录</p>'
        : rejectionData.map((r) => '''
            <div style="margin:10px 0;padding:10px;background:#fef2f2;border-radius:6px;border-left:4px solid #EF4444;">
              <p><strong>第${r['round']}次驳回</strong> · ${r['time']} · 验收人：${r['reviewer']}</p>
              <p style="margin:6px 0;">${r['reason']}</p>
            </div>
          ''').join('\n');

    final acceptanceNote = issue.acceptanceNote ?? '';
    final closedTime = issue.closedAt != null ? dateFormat.format(issue.closedAt!) : '';

    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>问题报告 - ${issue.title}</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; margin: 0; padding: 16px; background: #f5f5f5; color: #333; line-height: 1.6; }
  .container { max-width: 800px; margin: 0 auto; background: #fff; border-radius: 12px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }
  .header { background: $statusColor; color: white; padding: 20px; border-radius: 10px; margin-bottom: 20px; }
  .header h1 { margin: 0 0 8px 0; font-size: 22px; }
  .header .meta { opacity: 0.9; font-size: 14px; }
  .section { margin: 16px 0; }
  .section-title { font-size: 16px; font-weight: bold; color: #111; margin-bottom: 10px; padding-bottom: 6px; border-bottom: 2px solid #e5e7eb; }
  .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .info-item { padding: 8px 0; }
  .info-label { color: #6b7280; font-size: 13px; }
  .info-value { font-weight: 500; color: #111; }
  .photo-grid { display: grid; grid-template-columns: 1fr; gap: 8px; }
  .photo-grid img { width: 100%; border-radius: 6px; border: 1px solid #e5e7eb; }
  .status-badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 12px; font-weight: bold; background: rgba(255,255,255,0.25); }
  .footer { margin-top: 24px; padding-top: 16px; border-top: 1px solid #e5e7eb; text-align: center; color: #9ca3af; font-size: 12px; }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <h1>${issue.title}</h1>
    <div class="meta">
      <span class="status-badge">$statusText</span> &nbsp;
      编号：${issue.id} &nbsp;|&nbsp; 部门：${issue.department}
    </div>
  </div>

  <div class="section">
    <div class="section-title">📋 问题详情</div>
    <div class="info-grid">
      <div class="info-item"><div class="info-label">问题位置</div><div class="info-value">${issue.location}</div></div>
      <div class="info-item"><div class="info-label">问题类型</div><div class="info-value">$categoryName</div></div>
      <div class="info-item"><div class="info-label">严重程度</div><div class="info-value">$severityName</div></div>
      <div class="info-item"><div class="info-label">整改截止</div><div class="info-value">${dateOnly.format(issue.deadline)}</div></div>
    </div>
    <div class="info-item" style="margin-top:10px;">
      <div class="info-label">问题描述</div>
      <div class="info-value">${issue.description}</div>
    </div>
  </div>

  <div class="section">
    <div class="section-title">👥 责任信息</div>
    <div class="info-grid">
      <div class="info-item"><div class="info-label">上报人</div><div class="info-value">${issue.reporterName}</div></div>
      <div class="info-item"><div class="info-label">整改责任人</div><div class="info-value">${issue.assigneeName}</div></div>
      <div class="info-item"><div class="info-label">创建时间</div><div class="info-value">${dateFormat.format(issue.createdAt)}</div></div>
      <div class="info-item"><div class="info-label">最后更新</div><div class="info-value">${dateFormat.format(issue.updatedAt)}</div></div>
    </div>
  </div>

  <div class="section">
    <div class="section-title">📷 现场照片（${issuePhotoUrls.length}张）</div>
    <div class="photo-grid">$issuePhotosHtml</div>
  </div>

  <div class="section">
    <div class="section-title">🔧 整改反馈（${rectificationData.length}次）</div>
    $rectHtml
  </div>

  <div class="section">
    <div class="section-title">📝 验收信息</div>
    <div class="info-grid">
      <div class="info-item"><div class="info-label">验收意见</div><div class="info-value">${acceptanceNote.isNotEmpty ? acceptanceNote : '暂无'}</div></div>
      <div class="info-item"><div class="info-label">完成时间</div><div class="info-value">${closedTime.isNotEmpty ? closedTime : '未完成'}</div></div>
    </div>
  </div>

  <div class="section">
    <div class="section-title">❌ 驳回记录（${rejectionData.length}次）</div>
    $rejectHtml
  </div>

  <div class="footer">
    GZ环保巡查管理系统 · 生成时间：${dateFormat.format(DateTime.now())}
  </div>
</div>
</body>
</html>''';
  }

  // 辅助方法
  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text('$label ($count)'),
      ],
    );
  }

  Color _getCategoryColor(IssueCategory cat) {
    switch (cat) {
      case IssueCategory.wastewater: return Colors.blue;
      case IssueCategory.wastegas: return Colors.purple;
      case IssueCategory.solidWaste: return Colors.green;
      case IssueCategory.noise: return Colors.orange;
      case IssueCategory.other: return Colors.grey;
    }
  }

  String _getCategoryName(IssueCategory cat) {
    switch (cat) {
      case IssueCategory.wastewater: return '废水';
      case IssueCategory.wastegas: return '废气';
      case IssueCategory.solidWaste: return '固废';
      case IssueCategory.noise: return '噪音';
      case IssueCategory.other: return '其他';
    }
  }

  String _getCategoryNameEn(IssueCategory cat) {
    switch (cat) {
      case IssueCategory.wastewater: return 'Wastewater';
      case IssueCategory.wastegas: return 'Waste Gas';
      case IssueCategory.solidWaste: return 'Solid Waste';
      case IssueCategory.noise: return 'Noise';
      case IssueCategory.other: return 'Other';
    }
  }

  String _getSeverityName(SeverityLevel sev) {
    switch (sev) {
      case SeverityLevel.general: return '一般';
      case SeverityLevel.serious: return '较重';
      case SeverityLevel.critical: return '严重';
    }
  }

  String _getSeverityNameEn(SeverityLevel sev) {
    switch (sev) {
      case SeverityLevel.general: return 'General';
      case SeverityLevel.serious: return 'Serious';
      case SeverityLevel.critical: return 'Critical';
    }
  }

  String _getStatusName(IssueStatus status) {
    switch (status) {
      case IssueStatus.pending: return '待反馈';
      case IssueStatus.processing: return '待验收';
      case IssueStatus.reviewing: return '待验收';
      case IssueStatus.closed: return '已完成';
    }
  }

  // ============================================================
  // PDF图片辅助方法
  // ============================================================

  /// 下载单张图片字节，支持 cloud:// 和 http(s):// 格式
  Future<Uint8List?> _downloadImageBytes(String url, CloudBaseService cloudService) async {
    if (url.isEmpty) return null;

    String downloadUrl = url;

    // cloud:// 格式需要刷新为临时HTTP URL
    if (url.startsWith('cloud://')) {
      final freshUrl = await cloudService.getFreshPhotoUrl(url);
      if (freshUrl == null) return null;
      downloadUrl = freshUrl;
    }

    if (!downloadUrl.startsWith('http')) return null;

    try {
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (e) {
      print('❌ 下载图片失败: $url, 错误: $e');
    }
    return null;
  }

  /// 构建PDF中的照片网格（每行最多3张，每张限制最大高度）
  List<pw.Widget> _buildPdfPhotoWidgets(
    List<String> photoUrls,
    Map<String, Uint8List?> imageCache, {
    double maxImageHeight = 140,
  }) {
    final result = <pw.Widget>[];
    final validImages = <pw.Widget>[];

    for (final url in photoUrls) {
      final bytes = imageCache[url];
      if (bytes != null) {
        validImages.add(
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.all(4),
              child: pw.Image(
                pw.MemoryImage(bytes),
                fit: pw.BoxFit.cover,
                height: maxImageHeight,
              ),
            ),
          ),
        );
      }
    }

    if (validImages.isEmpty) return result;

    // 每3个一行
    for (var i = 0; i < validImages.length; i += 3) {
      final end = (i + 3).clamp(0, validImages.length);
      final rowChildren = validImages.sublist(i, end);
      // 如果一行不足3个，用Spacer填充
      while (rowChildren.length < 3) {
        rowChildren.add(pw.Expanded(child: pw.SizedBox()));
      }
      result.add(pw.Row(children: rowChildren));
    }

    return result;
  }

  // ============================================================
  // PDF导出：每个问题单独生成PDF，按车间+问题名命名，字母排序打包ZIP
  // ============================================================
  Future<void> _exportPdfReports(List<Issue> issues) async {
    if (issues.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可导出的问题'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() => _isExporting = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏳ 正在生成PDF报告，请稍候...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 60),
        ),
      );
    }

    try {
      final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
      final dateOnly = DateFormat('yyyy-MM-dd');

      // 按车间+问题名称字母排序
      final sortedIssues = List<Issue>.from(issues);
      sortedIssues.sort((a, b) {
        final aKey = '${a.department}${a.title}';
        final bKey = '${b.department}${b.title}';
        return aKey.compareTo(bKey);
      });

      final tempDir = await getTemporaryDirectory();
      final pdfDir = Directory('${tempDir.path}/pdf_export_${DateTime.now().millisecondsSinceEpoch}');
      await pdfDir.create(recursive: true);

      // 加载中文字体（黑体），确保PDF中文正常显示
      final fontData = await rootBundle.load('assets/fonts/simhei.ttf');
      final chineseFont = pw.Font.ttf(fontData);
      final theme = pw.ThemeData.withFont(
        base: chineseFont,
        bold: chineseFont,
      );

      // 获取CloudBaseService单例用于刷新图片URL
      final cloudService = CloudBaseService.instance;

      // 收集所有需要下载的图片URL（去重）
      final allPhotoUrls = <String>{};
      for (final issue in sortedIssues) {
        allPhotoUrls.addAll(issue.photos);
        allPhotoUrls.addAll(issue.rectificationPhotos);
        for (final record in issue.rectificationHistory) {
          allPhotoUrls.addAll(record.photos);
        }
      }

      // 预下载所有图片（带进度提示）
      final imageCache = <String, Uint8List?>{};
      if (allPhotoUrls.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⏳ 正在下载照片（${allPhotoUrls.length}张），请稍候...'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 60),
            ),
          );
        }
        var downloaded = 0;
        for (final url in allPhotoUrls) {
          if (url.isNotEmpty) {
            imageCache[url] = await _downloadImageBytes(url, cloudService);
            downloaded++;
          }
        }
        print('✅ 照片下载完成: $downloaded/${allPhotoUrls.length} 张');
      }

      // 为每个问题生成PDF
      var processedCount = 0;
      for (final issue in sortedIssues) {
        final pdf = pw.Document(theme: theme);

        // 状态颜色
        PdfColor statusColor;
        switch (issue.status) {
          case IssueStatus.closed:
            statusColor = PdfColors.green;
            break;
          case IssueStatus.reviewing:
            statusColor = PdfColors.blue;
            break;
          case IssueStatus.pending:
            statusColor = PdfColors.orange;
            break;
          default:
            statusColor = PdfColors.grey;
        }

        // 构建问题详情页的widgets列表（支持自动分页）
        final pageWidgets = <pw.Widget>[];

        // 标题栏
        pageWidgets.add(
          pw.Container(
            padding: const pw.EdgeInsets.all(15),
            decoration: pw.BoxDecoration(
              color: statusColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  issue.title,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  '编号：${issue.id} | 车间：${issue.department}',
                  style: pw.TextStyle(fontSize: 12, color: PdfColors.white),
                ),
              ],
            ),
          ),
        );
        pageWidgets.add(pw.SizedBox(height: 20));

        // 问题详情
        pageWidgets.add(pw.Text('问题详情', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)));
        pageWidgets.add(pw.Divider());
        pageWidgets.add(
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('位置：${issue.location}', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text('类别：${_getCategoryName(issue.category)}', style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('严重程度：${_getSeverityName(issue.severity)}', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text('截止日期：${dateOnly.format(issue.deadline)}', style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
        pageWidgets.add(pw.SizedBox(height: 10));
        pageWidgets.add(pw.Text('问题描述：${issue.description}', style: const pw.TextStyle(fontSize: 12)));

        // 问题现场照片
        if (issue.photos.isNotEmpty) {
          pageWidgets.add(pw.SizedBox(height: 10));
          pageWidgets.add(pw.Text('现场照片（${issue.photos.length}张）：', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey)));
          pageWidgets.addAll(_buildPdfPhotoWidgets(issue.photos, imageCache));
        }
        pageWidgets.add(pw.SizedBox(height: 20));

        // 责任信息
        pageWidgets.add(pw.Text('责任信息', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)));
        pageWidgets.add(pw.Divider());
        pageWidgets.add(
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text('发起人：${issue.reporterName}', style: const pw.TextStyle(fontSize: 12))),
              pw.Expanded(child: pw.Text('整改人：${issue.assigneeName}', style: const pw.TextStyle(fontSize: 12))),
            ],
          ),
        );
        pageWidgets.add(pw.SizedBox(height: 10));
        pageWidgets.add(
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text('创建时间：${dateFormat.format(issue.createdAt)}', style: const pw.TextStyle(fontSize: 12))),
              pw.Expanded(child: pw.Text('更新时间：${dateFormat.format(issue.updatedAt)}', style: const pw.TextStyle(fontSize: 12))),
            ],
          ),
        );
        pageWidgets.add(pw.SizedBox(height: 20));

        // 整改记录
        pageWidgets.add(pw.Text('整改记录（${issue.rectificationHistory.length}条）', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)));
        pageWidgets.add(pw.Divider());
        if (issue.rectificationHistory.isEmpty) {
          pageWidgets.add(pw.Text('暂无整改记录。', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey)));
        } else {
          for (final entry in issue.rectificationHistory.asMap().entries) {
            final i = entry.key;
            final record = entry.value;
            pageWidgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('#${i + 1} | ${dateFormat.format(record.timestamp)} | 提交人：${record.submitterName}',
                      style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text(record.description, style: const pw.TextStyle(fontSize: 12)),
                    if (record.photos.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      pw.Text('整改照片：', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                      ..._buildPdfPhotoWidgets(record.photos, imageCache, maxImageHeight: 100),
                    ],
                  ],
                ),
              ),
            );
          }
        }
        pageWidgets.add(pw.SizedBox(height: 20));

        // 验收信息
        pageWidgets.add(pw.Text('验收信息', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)));
        pageWidgets.add(pw.Divider());
        pageWidgets.add(pw.Text('验收备注：${issue.acceptanceNote ?? "无"}', style: const pw.TextStyle(fontSize: 12)));
        if (issue.closedAt != null) {
          pageWidgets.add(pw.Text('关闭时间：${dateFormat.format(issue.closedAt!)}', style: const pw.TextStyle(fontSize: 12)));
        }
        // 整改后照片
        if (issue.rectificationPhotos.isNotEmpty) {
          pageWidgets.add(pw.SizedBox(height: 10));
          pageWidgets.add(pw.Text('整改后照片（${issue.rectificationPhotos.length}张）：', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey)));
          pageWidgets.addAll(_buildPdfPhotoWidgets(issue.rectificationPhotos, imageCache));
        }
        pageWidgets.add(pw.SizedBox(height: 20));

        // 驳回记录
        pageWidgets.add(pw.Text('驳回记录（${issue.rejectionHistory.length}条）', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)));
        pageWidgets.add(pw.Divider());
        if (issue.rejectionHistory.isEmpty) {
          pageWidgets.add(pw.Text('暂无驳回记录。', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey)));
        } else {
          for (final entry in issue.rejectionHistory.asMap().entries) {
            final i = entry.key;
            final record = entry.value;
            pageWidgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('#${i + 1} | ${dateFormat.format(record.timestamp)} | 验收人：${record.reviewerName}',
                      style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text(record.note, style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            );
          }
        }

        // 页脚
        pageWidgets.add(pw.Divider());
        pageWidgets.add(
          pw.Center(
            child: pw.Text(
              'GZ环保巡查系统 | 生成时间：${dateFormat.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          ),
        );

        // 使用MultiPage自动分页（内容多时自动拆分到多页）
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            build: (pw.Context context) => pageWidgets,
          ),
        );

        // 保存PDF文件
        final safeTitle = issue.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final fileName = '${issue.department}-$safeTitle.pdf';
        final pdfFile = File('${pdfDir.path}/$fileName');
        await pdfFile.writeAsBytes(await pdf.save());

        processedCount++;
      }

      // 打包成ZIP
      final zipPath = '${tempDir.path}/pdf_reports_${DateTime.now().millisecondsSinceEpoch}.zip';
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      await encoder.addDirectory(pdfDir);
      encoder.close();

      // 清理临时目录
      try { await pdfDir.delete(recursive: true); } catch (_) {}

      // 分享ZIP
      await Share.shareXFiles(
        [XFile(zipPath)],
        text: 'GZ环保巡查PDF报告\n共 $processedCount 条问题，每个问题单独一份PDF',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已导出 $processedCount 份PDF报告'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e, stack) {
      print('❌ PDF导出失败: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}
