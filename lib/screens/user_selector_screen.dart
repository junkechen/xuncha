// lib/screens/user_selector_screen.dart
// 用户选择器 - 用于发起新聊天

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';

class UserSelectorScreen extends StatefulWidget {
  const UserSelectorScreen({Key? key}) : super(key: key);

  @override
  State<UserSelectorScreen> createState() => _UserSelectorScreenState();
}

class _UserSelectorScreenState extends State<UserSelectorScreen> {
  static const String _apiUrl = 'https://anuanbu1-1-6gjqaydwd067dbb1-1421679372.ap-shanghai.app.tcloudbase.com/api';
  
  List<User> _users = [];
  List<User> _filteredUsers = [];
  bool _loading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'query',
          'collection': 'users',
          'query': {},
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null) {
          final List<dynamic> dataList = data['data'];
          print('📥 从云端获取到 ${dataList.length} 个用户');
          
          // 过滤掉admin用户，如果有status/isActive字段则检查
          final filteredList = dataList.where((u) {
            if (u['username'] == 'admin') return false;
            // 如果有status或isActive字段，只过滤明确标记为停用的用户
            if (u.containsKey('status') && u['status'] == 'inactive') return false;
            if (u.containsKey('isActive') && u['isActive'] == false) return false;
            return true;
          }).toList();
          
          print('🔍 过滤后有 ${filteredList.length} 个有效用户');
          
          setState(() {
            _users = filteredList
                .map((json) => User.fromJson(json as Map<String, dynamic>))
                .toList();
            _filteredUsers = List.from(_users);
          });
          
          if (_users.isEmpty) {
            print('⚠️ 云端没有有效用户数据（可能所有用户都未激活）');
          }
        } else {
          print('⚠️ 云端返回数据为空: ${data['message']}');
        }
      } else {
        print('⚠️ 请求失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 加载用户失败: $e');
    }
    
    setState(() => _loading = false);
  }

  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredUsers = List.from(_users);
      } else {
        _filteredUsers = _users.where((user) {
          return user.name.toLowerCase().contains(query.toLowerCase()) ||
              user.username.toLowerCase().contains(query.toLowerCase()) ||
              user.department.toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择联系人'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索姓名、部门...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterUsers('');
                        },
                      )
                    : null,
              ),
              onChanged: _filterUsers,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              '未找到用户',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          return _buildUserTile(user);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(User user) {
    final roleStr = user.role.name;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getRoleColor(roleStr),
        child: Text(
          user.name.isNotEmpty ? user.name[0] : '?',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(user.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.department),
          Text(
            _getRoleText(roleStr),
            style: TextStyle(
              fontSize: 12,
              color: _getRoleColor(roleStr),
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chat_bubble_outline, color: Colors.blue),
      onTap: () => _selectUser(user),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.red;
      case 'inspector':
        return Colors.blue;
      case 'supervisor':
        return Colors.orange;
      case 'rectifier':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getRoleText(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return '管理员';
      case 'inspector':
        return '检查员';
      case 'supervisor':
        return '监督员';
      case 'rectifier':
        return '整改人';
      default:
        return '普通用户';
    }
  }

  void _selectUser(User user) {
    Navigator.pop(context, {
      'id': user.id,
      'name': user.name,
    });
  }
}
