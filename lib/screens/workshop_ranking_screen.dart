// lib/screens/workshop_ranking_screen.dart
// 车间问题数量全部排名

import 'package:flutter/material.dart';
import '../models/issue.dart';
import 'issue_detail_screen.dart';

class WorkshopRankingScreen extends StatelessWidget {
  final List<Issue> issues;

  const WorkshopRankingScreen({super.key, required this.issues});

  @override
  Widget build(BuildContext context) {
    final deptMap = <String, List<Issue>>{};
    for (final issue in issues) {
      final dept = issue.department.isNotEmpty ? issue.department : '未分配部门';
      deptMap.putIfAbsent(dept, () => []).add(issue);
    }

    final sortedDepts = deptMap.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    final total = issues.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('车间问题数量排名'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedDepts.length,
        itemBuilder: (context, index) {
          final entry = sortedDepts[index];
          final percentage = total > 0 ? (entry.value.length / total * 100) : 0.0;
          final isUnassigned = entry.key == '未分配部门';
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[200]!),
            ),
            child: InkWell(
              onTap: () => _showDepartmentIssues(context, entry.key, entry.value),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isUnassigned ? Colors.grey : const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isUnassigned ? Colors.grey : Colors.black87,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: total > 0 ? entry.value.length / total : 0,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isUnassigned ? Colors.grey : const Color(0xFF10B981),
                            ),
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDepartmentIssues(BuildContext context, String department, List<Issue> issues) {
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
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      title: Text(
                        issue.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${issue.categoryName} · ${issue.severityName} · ${issue.statusName}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () {
                        Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IssueDetailScreen(issue: issue),
                            ),
                          );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
