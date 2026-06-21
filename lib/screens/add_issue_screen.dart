// lib/screens/add_issue_screen.dart
// 新增问题页面 - 支持真实拍照和云端上传

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/issue_provider.dart';
import '../providers/chat_provider.dart';
import '../models/issue.dart' as models;
import '../services/cloudbase_service.dart';

class AddIssueScreen extends StatefulWidget {
  const AddIssueScreen({super.key});

  @override
  State<AddIssueScreen> createState() => _AddIssueScreenState();
}

class _AddIssueScreenState extends State<AddIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  final _deptController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  models.IssueCategory _selectedCategory = models.IssueCategory.wastewater;
  models.SeverityLevel _selectedSeverity = models.SeverityLevel.general;
  DateTime _deadline = DateTime.now().add(const Duration(days: 3));
  
  // 部门列表（基础+云端动态）
  List<String> _departments = [
    // 管理部门
    '安全保卫部',
    '环保部门',
    '仓储物流部',
    '质量管理部门',
    '设备管理部门',
    // 生产车间
    '酸轧车间',
    '连轧一车间',
    '连退车间',
    '剪配车间',
    '锌锭车间',
    '镀锌一车间',
    '镀锌二车间',
    '彩涂一车间',
    '彩涂二车间',
    '包装车间',
    '公辅车间',
    '热电车间',
    '稀土车间',
    '东舜',
  ];
  String? _selectedDepartment;
  bool _departmentsLoaded = false;
  
  // 整改责任人列表（从云端获取）
  List<Map<String, String>> _rectifiers = [];
  List<Map<String, String>> _filteredRectifiers = [];
  Map<String, List<Map<String, String>>> _rectifiersByDept = {};
  bool _loadingRectifiers = false;
  
  String? _selectedRectifierId;
  String? _selectedRectifierName;
  // 整改人搜索
  final TextEditingController _rectifierSearchController = TextEditingController();
  String _rectifierSearchQuery = '';
  
  // 真实图片列表（本地文件路径）
  List<File> _photoFiles = [];
  // 上传后的云端URL列表
  List<String> _uploadedUrls = [];
  bool _isUploading = false;
  
  // 预设问题描述列表
  List<String> _presetDescriptions = [
    '设备漏油严重，需要及时处理',
    '危险化学品存放不规范',
    '废气排放超标',
    '消防通道被堵塞',
    '电气线路老化',
    '安全防护设施缺失',
    '地面油污湿滑',
    '噪音超标',
    '固废堆放混乱',
    '应急预案不完善',
    '个人防护用品佩戴不规范',
    '动火作业未审批',
    '有限空间作业无标识',
    '高处作业无防护',
    '叉车作业无证驾驶',
  ];
  
  // 常用描述（从本地存储加载）
  List<String> _frequentDescriptions = [];

  @override
  void initState() {
    super.initState();
    // 初始化云端服务并加载数据
    _initializeAndLoad();
    _loadFrequentDescriptions();
  }

  // 初始化云端服务并加载数据
  Future<void> _initializeAndLoad() async {
    // 确保CloudBase服务已初始化
    await CloudBaseService.instance.init();
    // 加载用户和部门列表
    await _loadUsersFromCloud();
  }
  
  // 从本地存储加载常用描述
  Future<void> _loadFrequentDescriptions() async {
    // 从已提交的隐患中学习常用描述
    try {
      final cloudService = CloudBaseService.instance;
      final issues = await cloudService.getCloudIssues();
      
      if (issues.isNotEmpty) {
        // 统计描述出现频率
        Map<String, int> descCount = {};
        for (var issue in issues) {
          if (issue.description.isNotEmpty) {
            descCount[issue.description] = (descCount[issue.description] ?? 0) + 1;
          }
        }
        
        // 按频率排序，取前5个
        var sorted = descCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        
        _frequentDescriptions = sorted.take(5).map((e) => e.key).toList();
        
        print('📋 从历史隐患中学习到常用描述: $_frequentDescriptions');
      }
    } catch (e) {
      print('加载常用描述失败: $e');
    }
  }
  
  // 保存常用描述到本地
  void _saveDescription(String desc) {
    if (desc.isEmpty) return;
    if (!_frequentDescriptions.contains(desc)) {
      _frequentDescriptions.insert(0, desc);
      if (_frequentDescriptions.length > 10) {
        _frequentDescriptions = _frequentDescriptions.take(10).toList();
      }
      print('💾 已保存常用描述: $desc');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    _deptController.dispose();
    _rectifierSearchController.dispose();
    super.dispose();
  }

  // 从云端加载用户列表（使用AuthProvider确保数据一致）
  Future<void> _loadUsersFromCloud() async {
    setState(() {
      _loadingRectifiers = true;
    });
    
    try {
      // 使用 AuthProvider 获取用户列表（与用户管理页面保持一致）
      final authProvider = context.read<AuthProvider>();
      final users = await authProvider.fetchAllUsersFromCloud();
      
      print('🔍 _loadUsersFromCloud: 从AuthProvider获取到 ${users.length} 个用户');
      
      if (users.isNotEmpty) {
        final List<Map<String, String>> loadedRectifiers = [];
        for (var user in users) {
          // 过滤掉admin用户，但保留所有其他用户（不限制角色）
          final username = user.username;
          if (username.isNotEmpty && username != 'admin') {
            final name = user.name.isNotEmpty ? user.name : username;
            final dept = user.department.isNotEmpty ? user.department : '未分配部门';
            final role = user.role.toString();
            
            loadedRectifiers.add({
              'id': username,
              'name': name,
              'dept': dept,
              'role': role,
            });
            
            print('   [整改人选项] $name ($username), 部门: $dept, 角色: $role');
          }
        }
        _rectifiers = loadedRectifiers;
        
        // 整体按姓名排序
        _rectifiers.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        
        // 按部门分组
        _rectifiersByDept = {};
        for (var r in _rectifiers) {
          final dept = r['dept'] ?? '未分配部门';
          _rectifiersByDept.putIfAbsent(dept, () => []);
          _rectifiersByDept[dept]!.add(r);
          
          // 添加新部门到列表
          if (!_departments.contains(dept)) {
            _departments.add(dept);
          }
        }
        
        // 部门内也按姓名排序
        for (var key in _rectifiersByDept.keys) {
          _rectifiersByDept[key]!.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        }
        
        // 标记部门已从云端加载
        _departmentsLoaded = true;
        
        print('✅ 从AuthProvider加载了 ${_rectifiers.length} 个用户（整改负责人选项）');
        print('   部门数量: ${_rectifiersByDept.length}');
        print('   部门列表: $_departments');
      } else {
        print('⚠️ AuthProvider用户列表为空，尝试CloudBaseService');
        // 备用：使用CloudBaseService
        await _loadUsersFromCloudBase();
      }
      
      // 如果部门为空，也尝试加载部门列表
      if (!_departmentsLoaded) {
        await _loadDepartmentsFromCloud();
      }
    } catch (e) {
      print('❌ 加载用户失败: $e');
      // 尝试使用CloudBaseService备用
      await _loadUsersFromCloudBase();
    }
    
    setState(() {
      _loadingRectifiers = false;
    });
  }
  
  // 备用：从CloudBaseService加载用户
  Future<void> _loadUsersFromCloudBase() async {
    try {
      final cloudService = CloudBaseService.instance;
      final result = await cloudService.queryUsers();
      
      print('🔍 _loadUsersFromCloudBase: 从CloudBaseService获取到 ${result.length} 个用户');
      
      if (result.isNotEmpty) {
        final List<Map<String, String>> loadedRectifiers = [];
        for (var user in result) {
          final username = user['username']?.toString() ?? '';
          if (username.isNotEmpty && username != 'admin') {
            final name = user['name']?.toString() ?? username;
            final dept = user['department']?.toString() ?? '未分配部门';
            final role = user['role']?.toString() ?? 'inspector';
            
            loadedRectifiers.add({
              'id': username,
              'name': name,
              'dept': dept,
              'role': role,
            });
          }
        }
        _rectifiers = loadedRectifiers;
        
        // 整体按姓名排序
        _rectifiers.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        
        // 按部门分组
        _rectifiersByDept = {};
        for (var r in _rectifiers) {
          final dept = r['dept'] ?? '未分配部门';
          _rectifiersByDept.putIfAbsent(dept, () => []);
          _rectifiersByDept[dept]!.add(r);
          if (!_departments.contains(dept)) {
            _departments.add(dept);
          }
        }
        // 部门内按姓名排序
        for (var key in _rectifiersByDept.keys) {
          _rectifiersByDept[key]!.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        }
        _departmentsLoaded = true;
      }
    } catch (e) {
      print('❌ CloudBaseService加载用户失败: $e');
    }
  }
  
  // 从云端专门加载部门列表
  Future<void> _loadDepartmentsFromCloud() async {
    try {
      final cloudService = CloudBaseService.instance;
      final depts = await cloudService.queryDepartments();
      
      if (depts.isNotEmpty) {
        for (var dept in depts) {
          final deptName = dept['name']?.toString() ?? dept['department']?.toString() ?? '';
          if (deptName.isNotEmpty && !_departments.contains(deptName)) {
            _departments.add(deptName);
          }
        }
        _departmentsLoaded = true;
        print('✅ 从云端加载了 ${depts.length} 个部门');
      }
    } catch (e) {
      print('❌ 加载部门列表失败: $e');
    }
  }

  // 压缩图片 - 目标50KB以下（云函数超时限制）
  Future<File?> _compressImage(File file) async {
    try {
      final fileSize = await file.length();
      print('📷 原始图片大小: ${(fileSize / 1024).toStringAsFixed(1)} KB');
      
      // 目标大小：50KB以下
      const targetSize = 50 * 1024;
      
      // 如果已经小于50KB，直接返回
      if (fileSize <= targetSize) {
        print('📷 图片已符合要求，无需压缩');
        return file;
      }
      
      // 分辨率等级：逐步降低
      const resolutions = [
        [1920, 1080],  // 保持1080p
        [1280, 720],   // 720p
        [1024, 576],   // 480p
        [800, 450],    // 低分辨率
        [640, 360],    // 极低分辨率
      ];
      
      // 使用应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final compressDir = Directory('${appDir.path}/compressed_photos');
      if (!await compressDir.exists()) {
        await compressDir.create(recursive: true);
      }
      
      // 返回压缩结果文件
      File? lastResult;
      
      for (var resolution in resolutions) {
        int quality = 80;  // 初始质量
        
        for (int q = quality; q >= 20; q -= 10) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final uniqueId = '${timestamp}_${resolution[0]}x${resolution[1]}_q$q';
          final targetPath = '${compressDir.path}/compressed_$uniqueId.jpg';
          
          print('📷 尝试压缩: ${resolution[0]}x${resolution[1]}, 质量$q%');
          
          final result = await FlutterImageCompress.compressAndGetFile(
            file.absolute.path,
            targetPath,
            quality: q,
            minWidth: resolution[0],
            minHeight: resolution[1],
          );
          
          if (result != null) {
            // XFile 转换为 File
            final compressedFile = File(result.path);
            final compressedSize = await compressedFile.length();
            print('📷 分辨率${resolution[0]}x${resolution[1]}，质量$q%，大小: ${(compressedSize / 1024).toStringAsFixed(1)} KB');
            
            // 如果压缩后大小满足要求，返回
            if (compressedSize <= targetSize) {
              print('📷 压缩成功，满足50KB以下要求');
              return compressedFile;
            }
            
            // 保存当前最接近的结果
            if (lastResult == null || compressedSize < (lastResult.lengthSync())) {
              lastResult = compressedFile;
            }
          }
        }
      }
      
      // 返回最佳结果
      if (lastResult != null) {
        print('📷 返回压缩结果: ${(lastResult.lengthSync() / 1024).toStringAsFixed(1)} KB');
        return lastResult;
      }
      
      return file;
    } catch (e) {
      print('❌ 图片压缩失败: $e');
      return file; // 压缩失败返回原图
    }
  }

  // 拍照（拍照后立即压缩）
  Future<void> _takePhoto() async {
    if (_photoFiles.length >= 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('最多上传9张照片'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80, // 适当提高初始质量，压缩会处理
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (photo != null) {
        // 拍照后立即压缩
        final originalFile = File(photo.path);
        final fileSize = await originalFile.length();
        print('📷 拍照完成，原始大小: ${(fileSize / 1024).toStringAsFixed(1)} KB');

        // 先添加原图（让用户看到预览）
        setState(() {
          _photoFiles.add(originalFile);
        });

        // 后台压缩（替换列表中的文件）
        final compressedFile = await _compressImage(originalFile);
        if (compressedFile != null && compressedFile.path != originalFile.path) {
          final compressedSize = await compressedFile.length();
          print('📷 拍照压缩完成: ${(compressedSize / 1024).toStringAsFixed(1)} KB');

          // 替换为压缩后的文件
          setState(() {
            final idx = _photoFiles.indexOf(originalFile);
            if (idx >= 0) {
              _photoFiles[idx] = compressedFile;
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('照片已添加并压缩至${(compressedSize / 1024).toStringAsFixed(1)}KB'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              margin: const EdgeInsets.all(16),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('照片已添加 (${(fileSize / 1024).toStringAsFixed(1)}KB)'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('拍照失败: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  // 从相册选择
  Future<void> _pickFromGallery() async {
    if (_photoFiles.length >= 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('最多上传9张照片'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
          margin: EdgeInsets.all(16),
        ),
      );
      return;
    }
    
    try {
      final List<XFile> photos = await _picker.pickMultiImage(
        imageQuality: 70, // 使用中等质量
        maxWidth: 1920,  // 限制最大分辨率
        maxHeight: 1080,
      );
      
      if (photos.isNotEmpty) {
        int added = 0;
        for (var photo in photos) {
          if (_photoFiles.length < 9) {
            // 压缩每张图片
            final originalFile = File(photo.path);
            final compressedFile = await _compressImage(originalFile);
            
            setState(() {
              if (compressedFile != null) {
                _photoFiles.add(compressedFile);
              } else {
                _photoFiles.add(originalFile);
              }
            });
            added++;
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已选择${added}张照片并压缩'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('选择失败: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  // 移除图片
  void _removePhoto(int index) {
    setState(() {
      _photoFiles.removeAt(index);
    });
  }

  // 上传所有照片到云端
  Future<bool> _uploadPhotos() async {
    if (_photoFiles.isEmpty) return true;
    
    // 显示上传中提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在上传照片，请稍候...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    }
    
    setState(() {
      _isUploading = true;
    });
    
    try {
      final cloudService = CloudBaseService.instance;
      _uploadedUrls = [];
      
      for (int i = 0; i < _photoFiles.length; i++) {
        final file = _photoFiles[i];
        final fileName = 'hazard_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        
        print('📤 开始上传第 ${i + 1}/${_photoFiles.length} 张照片...');
        
        // 传入文件路径，cloudService.uploadImage 会自动读取并转为Base64
        final url = await cloudService.uploadImage(file.path, fileName);
        
        if (url != null) {
          _uploadedUrls.add(url);
          print('✅ 照片 $i 上传成功: $url');
          
          // 显示单张照片上传成功提示
          if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 第 ${i + 1} 张照片上传成功'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
          }
        } else {
          print('❌ 照片 $i 上传失败');
          
          // 显示单张照片上传失败提示
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ 第 ${i + 1} 张照片上传失败，请检查网络'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
              ),
            );
          }
        }
      }
      
      setState(() {
        _isUploading = false;
      });
      
      // 照片上传是可选的，只要有一张成功就继续，都没有照片也可以提交
      final hasPhotos = _photoFiles.isNotEmpty;
      final hasUploaded = _uploadedUrls.isNotEmpty;
      final allFailed = hasPhotos && !hasUploaded;
      final successCount = _uploadedUrls.length;
      final totalCount = _photoFiles.length;
      
      if (allFailed) {
        // 全部上传失败，给用户提示但允许继续提交（照片为空）
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('照片上传失败（$successCount/$totalCount），将以无照片方式提交'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } else if (successCount < totalCount) {
        // 部分成功
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('部分照片上传成功（$successCount/$totalCount）'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
      
      // 没有照片 或者 至少有一张照片上传成功
      return _photoFiles.isEmpty || _uploadedUrls.isNotEmpty;
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      print('❌ 上传失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('照片上传失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return false;
    }
  }

  // 选择整改责任人（搜索+按部门分组+姓名排序）
  void _showRectifierSelector() {
    if (_loadingRectifiers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在加载用户列表...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
      _loadUsersFromCloud();
      return;
    }
    
    // 重置搜索状态
    _rectifierSearchController.clear();
    _rectifierSearchQuery = '';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // 根据搜索词过滤用户
          List<Map<String, String>> filteredAll = _rectifiers.where((r) {
            if (_rectifierSearchQuery.isEmpty) return true;
            final q = _rectifierSearchQuery.toLowerCase();
            return (r['name'] ?? '').toLowerCase().contains(q) ||
                   (r['dept'] ?? '').toLowerCase().contains(q);
          }).toList();

          // 构建过滤后的按部门分组
          Map<String, List<Map<String, String>>> filteredByDept = {};
          if (_rectifierSearchQuery.isEmpty) {
            filteredByDept = _rectifiersByDept;
          } else {
            for (var r in filteredAll) {
              final dept = r['dept'] ?? '未分配部门';
              filteredByDept.putIfAbsent(dept, () => []);
              filteredByDept[dept]!.add(r);
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      const Text(
                        '选择整改责任人',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (_loadingRectifiers)
                        const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                // 搜索框
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _rectifierSearchController,
                    decoration: InputDecoration(
                      hintText: '搜索姓名或部门...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _rectifierSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _rectifierSearchController.clear();
                                setModalState(() {
                                  _rectifierSearchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF10B981)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        _rectifierSearchQuery = val;
                      });
                    },
                  ),
                ),
                const Divider(height: 1),
                // 用户列表
                Expanded(
                  child: _loadingRectifiers
                      ? const Center(child: CircularProgressIndicator())
                      : filteredAll.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  Text(
                                    _rectifierSearchQuery.isEmpty ? '暂无用户，请先注册用户' : '未找到匹配的用户',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  if (_rectifierSearchQuery.isEmpty) ...[
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _loadUsersFromCloud();
                                      },
                                      child: const Text('刷新'),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: filteredByDept.keys.length,
                              itemBuilder: (context, index) {
                                final dept = filteredByDept.keys.elementAt(index);
                                final users = filteredByDept[dept] ?? [];
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 部门标题
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      color: Colors.grey[200],
                                      width: double.infinity,
                                      child: Text(
                                        dept,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    ...users.map((rectifier) {
                                      final isSelected = _selectedRectifierId == rectifier['id'];
                                      final name = rectifier['name'] ?? '';
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: isSelected
                                              ? const Color(0xFF10B981)
                                              : Colors.grey[300],
                                          child: Text(
                                            name.isNotEmpty ? name[0] : '?',
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : Colors.black,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        title: Text(name),
                                        subtitle: Text(
                                          _getRoleDisplayName(rectifier['role'] ?? ''),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        trailing: isSelected
                                            ? const Icon(Icons.check_circle, color: Color(0xFF10B981))
                                            : null,
                                        onTap: () {
                                          setState(() {
                                            _selectedRectifierId = rectifier['id'];
                                            _selectedRectifierName = name;
                                          });
                                          Navigator.pop(context);
                                        },
                                      );
                                    }),
                                  ],
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 角色名称显示转换
  String _getRoleDisplayName(String role) {
    switch (role.toLowerCase()) {
      case 'userrole.admin':
      case 'admin': return '管理员';
      case 'userrole.inspector':
      case 'inspector': return '检查员';
      case 'userrole.supervisor':
      case 'supervisor': return '监督员';
      case 'userrole.rectifier':
      case 'rectifier': return '整改人';
      default: return '普通用户';
    }
  }

  // 显示新增部门对话框
  void _showAddDepartmentDialog() {
    _deptController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增部门'),
        content: TextField(
          controller: _deptController,
          decoration: const InputDecoration(
            labelText: '部门名称',
            hintText: '例如：热轧车间',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newDept = _deptController.text.trim();
              if (newDept.isNotEmpty && !_departments.contains(newDept)) {
                // 同步到云端
                try {
                  final cloudService = CloudBaseService.instance;
                  await cloudService.addDepartment(newDept);
                  print('✅ 部门已同步到云端: $newDept');
                } catch (e) {
                  print('⚠️ 部门同步到云端失败: $e');
                }
                
                setState(() {
                  _departments.add(newDept);
                  _selectedDepartment = newDept;
                  _titleController.text = newDept;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已添加部门并同步到云端: $newDept'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              } else if (_departments.contains(newDept)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('该部门已存在'),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  // 提交问题
  Future<void> _submitIssue() async {
    if (!_formKey.currentState!.validate()) return;

    // 检查部门
    if (_selectedDepartment == null || _selectedDepartment!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请选择部门车间'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // 检查是否至少有一张照片
    if (_photoFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请至少拍摄一张现场照片'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // 检查整改责任人
    if (_selectedRectifierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请选择整改责任人'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // 显示上传中提示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF10B981)),
                SizedBox(height: 16),
                Text('正在上传照片...'),
              ],
            ),
          ),
        ),
      ),
    );

    // 上传照片到云端
    final uploadSuccess = await _uploadPhotos();
    
    if (!uploadSuccess && _photoFiles.isNotEmpty) {
      Navigator.pop(context); // 关闭加载框
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('照片上传失败，请重试'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
      return;
    }

    // 关闭上传提示
    Navigator.pop(context);

    final auth = context.read<AuthProvider>();
    final issueProvider = context.read<IssueProvider>();

    final issue = models.Issue(
      id: '',
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      category: _selectedCategory,
      severity: _selectedSeverity,
      photos: _uploadedUrls, // 使用云端URL
      location: _locationController.text.trim(),
      department: _selectedDepartment ?? '',  // 使用用户选择的部门，而不是整改人的部门
      reporterId: auth.currentUser?.id ?? '',
      reporterName: auth.currentUser?.name ?? '',
      assigneeId: _selectedRectifierId ?? '',
      assigneeName: _selectedRectifierName ?? '',
      deadline: _deadline,
      status: models.IssueStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final success = await issueProvider.createIssue(issue);
    if (success && mounted) {
      // 保存常用描述（自动学习）
      _saveDescription(_descController.text.trim());
      
      // 通知整改责任人
      if (_selectedRectifierId != null && _selectedRectifierName != null) {
        final chatProvider = context.read<ChatProvider>();
        await chatProvider.sendIssueNotification(
          assigneeId: _selectedRectifierId!,
          assigneeName: _selectedRectifierName!,
          issueId: issue.id.isNotEmpty ? issue.id : 'new_issue',
          issueTitle: _titleController.text.trim(),
          action: 'create',
        );
        print('✅ 已通知整改责任人: ${_selectedRectifierName}');
      }
      
      // 根据实际上传结果显示提示
      final photoCount = _photoFiles.length;
      final uploadedCount = _uploadedUrls.length;
      String message;
      if (photoCount == 0) {
        message = '问题提交成功';
      } else if (uploadedCount == photoCount) {
        message = '✅ 问题提交成功，$uploadedCount张照片已上传云端';
      } else if (uploadedCount > 0) {
        message = '⚠️ 问题已提交，但仅$uploadedCount/$photoCount张照片上传成功';
      } else {
        message = '⚠️ 问题已提交本地，云端同步可能有延迟';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: uploadedCount == photoCount ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
      
      // 清空表单
      _titleController.clear();
      _descController.clear();
      _locationController.clear();
      setState(() {
        _photoFiles.clear();
        _uploadedUrls.clear();
        _selectedRectifierId = null;
        _selectedRectifierName = null;
      });
    }
  }

  // 选择截止日期
  Future<void> _selectDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() {
        _deadline = date;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上报问题'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 问题类型
              const Text(
                '问题类型 *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: models.IssueCategory.values.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(_getCategoryName(cat)),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = cat;
                      });
                    },
                    selectedColor: const Color(0xFF10B981),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // 严重程度
              const Text(
                '严重程度 *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: models.SeverityLevel.values.map((sev) {
                  final isSelected = _selectedSeverity == sev;
                  return ChoiceChip(
                    label: Text(_getSeverityName(sev)),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedSeverity = sev;
                      });
                    },
                    selectedColor: _getSeverityColor(sev),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // 部门车间选择/输入
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedDepartment,
                      decoration: InputDecoration(
                        labelText: '部门车间 *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                      items: _departments.map((dept) {
                        return DropdownMenuItem(value: dept, child: Text(dept));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedDepartment = value;
                          _titleController.text = value ?? '';
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请选择部门';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              await _loadDepartmentsFromCloud();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('部门列表已刷新'),
                                    backgroundColor: Color(0xFF10B981),
                                    duration: Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.all(16),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.blue[700],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.refresh, color: Colors.white, size: 20),
                                  SizedBox(width: 4),
                                  Text('刷新', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => _showAddDepartmentDialog(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add, color: Colors.white, size: 20),
                                  SizedBox(width: 4),
                                  Text('新增', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 问题标题（显示选中的部门）
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: '问题标题 *',
                  hintText: '简明扼要描述问题',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入问题标题';
                  }
                  return null;
                },
                onChanged: (value) {
                  // 如果值和部门不一样，可能是用户输入了自定义内容
                },
              ),
              const SizedBox(height: 16),

              // 常用描述快捷选择
              if (_frequentDescriptions.isNotEmpty || _presetDescriptions.isNotEmpty) ...[
                Text(
                  '💡 快捷描述',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                // 常用描述（从历史学习）
                if (_frequentDescriptions.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _frequentDescriptions.map((desc) {
                      return ActionChip(
                        label: Text(desc.length > 12 ? '${desc.substring(0, 12)}...' : desc),
                        backgroundColor: Colors.green[50],
                        labelStyle: TextStyle(fontSize: 12, color: Colors.green[800]),
                        onPressed: () {
                          setState(() {
                            _descController.text = desc;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
                // 预设描述
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _presetDescriptions.map((desc) {
                    return ActionChip(
                      label: Text(desc.length > 15 ? '${desc.substring(0, 15)}...' : desc),
                      backgroundColor: Colors.blue[50],
                      labelStyle: TextStyle(fontSize: 12, color: Colors.blue[800]),
                      onPressed: () {
                        setState(() {
                          _descController.text = desc;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // 问题描述
              TextFormField(
                controller: _descController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: '问题描述 *',
                  hintText: '详细描述发现的问题',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入问题描述';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 问题位置
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: '问题位置 *',
                  hintText: '如：冷轧车间东侧排水口',
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入问题位置';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 整改责任人
              InkWell(
                onTap: _showRectifierSelector,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: '整改责任人 *',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(
                    _selectedRectifierName ?? '请选择整改责任人',
                    style: TextStyle(
                      color: _selectedRectifierName != null 
                          ? Colors.black 
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 整改期限
              InkWell(
                onTap: _selectDeadline,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: '整改期限 *',
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  child: Text(
                    '${_deadline.year}-${_deadline.month.toString().padLeft(2, '0')}-${_deadline.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 快捷选择整改天数
              Wrap(
                spacing: 8,
                children: [1, 3, 7, 15, 30].map((days) {
                  final isSelected = _deadline.year == DateTime.now().add(Duration(days: days)).year &&
                      _deadline.month == DateTime.now().add(Duration(days: days)).month &&
                      _deadline.day == DateTime.now().add(Duration(days: days)).day;
                  return ChoiceChip(
                    label: Text('${days}日'),
                    selected: isSelected,
                    selectedColor: const Color(0xFF10B981),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontSize: 13,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _deadline = DateTime.now().add(Duration(days: days));
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // 拍照上传 - 真实版
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '现场照片 *',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '必填 (${_photoFiles.length}/9)',
                            style: TextStyle(fontSize: 12, color: Colors.red[700]),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // 已选图片预览
                    if (_photoFiles.isNotEmpty) ...[
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _photoFiles.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  // 真实图片预览
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      _photoFiles[index],
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => _removePhoto(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    
                    // 添加图片按钮
                    Row(
                      children: [
                        // 拍照按钮
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isUploading ? null : _takePhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('拍照'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF10B981),
                              side: const BorderSide(color: Color(0xFF10B981)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 相册按钮
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isUploading ? null : _pickFromGallery,
                            icon: const Icon(Icons.photo_library),
                            label: const Text('相册'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF10B981),
                              side: const BorderSide(color: Color(0xFF10B981)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_upload, color: Colors.green[700], size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '照片将自动上传到腾讯云存储',
                              style: TextStyle(fontSize: 12, color: Colors.green[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 提交按钮
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitIssue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '提交问题',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _getCategoryName(models.IssueCategory cat) {
    switch (cat) {
      case models.IssueCategory.wastewater: return '废水';
      case models.IssueCategory.wastegas: return '废气';
      case models.IssueCategory.solidWaste: return '固废';
      case models.IssueCategory.noise: return '噪音';
      case models.IssueCategory.other: return '其他';
    }
  }

  String _getSeverityName(models.SeverityLevel sev) {
    switch (sev) {
      case models.SeverityLevel.general: return '一般';
      case models.SeverityLevel.serious: return '较重';
      case models.SeverityLevel.critical: return '严重';
    }
  }

  Color _getSeverityColor(models.SeverityLevel sev) {
    switch (sev) {
      case models.SeverityLevel.general: return Colors.green;
      case models.SeverityLevel.serious: return Colors.orange;
      case models.SeverityLevel.critical: return Colors.red;
    }
  }
}
