// lib/widgets/business_type_selector.dart
// 业务类型 UI 组件 —— 展示（彩色 chip）与多选器，个人中心 / 用户管理 / 注册共用。
// 取值与配色全部来自 models/business_type.dart（与桌面端 business.js 对齐）。

import 'package:flutter/material.dart';
import '../models/business_type.dart';

/// 业务类型展示：彩色 chip 横排。
/// 空数组按桌面端 business.js 口径显示灰色「全部业务」。
class BusinessTypeChips extends StatelessWidget {
  final List<String> codes;
  final bool dense;

  const BusinessTypeChips(this.codes, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    if (codes.isEmpty) {
      return _chip('全部业务', Colors.grey, dense);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: codes.map((c) {
        final b = businessTypeOf(c);
        return _chip(b?.shortName ?? c, Color(b?.colorValue ?? 0xFF9E9E9E), dense);
      }).toList(),
    );
  }

  static Widget _chip(String text, Color color, bool dense) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 业务类型多选器：可单选可多选，未选表示「全部业务」
class BusinessTypeSelector extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const BusinessTypeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '业务类型',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: kBusinessTypes.map((b) {
            final isSelected = selected.contains(b.code);
            final color = Color(b.colorValue);
            return FilterChip(
              label: Text(b.name),
              selected: isSelected,
              onSelected: (v) {
                final next = List<String>.from(selected);
                if (v) {
                  if (!next.contains(b.code)) next.add(b.code);
                } else {
                  next.remove(b.code);
                }
                onChanged(next);
              },
              selectedColor: color.withOpacity(0.18),
              checkmarkColor: color,
              side: BorderSide(
                color: isSelected ? color : Colors.grey.shade300,
              ),
              labelStyle: TextStyle(
                fontSize: 12,
                color: isSelected ? color : Colors.black87,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          selected.isEmpty ? '未选择 = 全部业务' : '已选 ${selected.length} 项 · 可多选',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
