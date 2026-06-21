// lib/services/cloudbase_service.dart
// 腾讯云开发 CloudBase 服务 - 云函数HTTP API调用方式
// API地址: https://anuanbu1-1-6gjqaydwd067dbb1-1421679372.ap-shanghai.app.tcloudbase.com/api

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as images;
import '../models/issue.dart' as models;
import '../models/user.dart' as models;

class CloudBaseService {
  static CloudBaseService? _instance;
  static bool _isInitialized = false;
  
  // 云函数API地址 - 直接硬编码确保正确
  static const String _apiUrl = 'https://anuanbu1-1-6gjqaydwd067dbb1-1421679372.ap-shanghai.app.tcloudbase.com/api';
  
  // 认证令牌（登录后获取）
  String? _accessToken;
  String? _refreshToken;
  models.User? _currentUser;
  bool _useCloudBase = true; // 始终使用云端

  CloudBaseService._();

  static CloudBaseService get instance {
    _instance ??= CloudBaseService._();
    return _instance!;
  }

  /// 初始化服务
  Future<bool> init() async {
    if (_isInitialized) return true;
    
    // 确保云端模式开启
    _useCloudBase = true;
    _isInitialized = true;
    print('✅ CloudBase Service 初始化成功');
    print('   云函数API: $_apiUrl');
    print('   云端模式: 开启');
    return true;
  }

  /// 调用云函数API（公开方法，供其他 Provider 使用）
  Future<Map<String, dynamic>> callApi(
    String action, {
    Map<String, dynamic>? query,
    String? collection,
    Map<String, dynamic>? data,
    Map<String, dynamic>? fields,
  }) async {
    try {
      // 构建请求体
      final Map<String, dynamic> requestBody = {
        'action': action,
        if (query != null) 'query': query,
        if (collection != null) 'collection': collection,
      };

      // 如果有 fields，合并到 data 中
      if (fields != null) {
        requestBody['data'] = {
          if (query != null) ...query, // query 中的条件也会作为 data 传递
          ...fields, // 更新的字段
        };
      } else if (data != null) {
        requestBody['data'] = data;
      }

      final body = jsonEncode(requestBody);

      print('📤 API调用: $action, URL: $_apiUrl');
      print('📤 请求体大小: ${body.length} bytes');

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 60));

      print('📥 HTTP状态: ${response.statusCode}');
      print('📥 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        print('📥 API响应: code=${result['code']}');
        return result;
      } else {
        print('❌ 请求失败: ${response.statusCode}');
        return {'code': -1, 'message': '请求失败: ${response.statusCode}'};
      }
    } catch (e) {
      print('❌ 网络错误: $e');
      return {'code': -1, 'message': '网络错误: $e'};
    }
  }

  /// 登录
  Future<LoginResult> login(String username, String password) async {
    // 使用云端登录
    try {
      final result = await callApi('login', query: {'name': username, 'password': password});
      
      if (result['code'] == 0 && result['user'] != null) {
        final userData = result['user'] as Map<String, dynamic>;
        _currentUser = models.User.fromJson(userData);
        _accessToken = 'cloudbase_token_${DateTime.now().millisecondsSinceEpoch}';
        return LoginResult(success: true, user: _currentUser);
      } else {
        return LoginResult(success: false, error: result['message'] ?? '登录失败');
      }
    } catch (e) {
      print('⚠️ 云端登录失败: $e');
      return LoginResult(success: false, error: '网络错误: $e');
    }
  }

  /// 登出
  void logout() {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
  }

  /// 获取当前用户
  models.User? get currentUser => _currentUser;

  /// 是否已登录
  bool get isLoggedIn => _accessToken != null;

  /// 压缩图片文件到目标大小（150KB以下）
  /// 返回压缩后的文件路径，如果失败返回原路径
  Future<String?> compressImageForUpload(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return filePath;

      final fileSize = await file.length();
      final fileSizeKB = fileSize / 1024;
      
      // 如果文件已经小于150KB，不需要压缩
      if (fileSizeKB <= 150) {
        print('📷 图片大小 ${fileSizeKB.toStringAsFixed(1)}KB，无需压缩');
        return filePath;
      }

      // 使用 image 包进行压缩
      final bytes = await file.readAsBytes();
      final image = images.decodeImage(bytes);
      
      if (image == null) {
        print('❌ 无法解码图片: $filePath');
        return filePath;
      }

      // 计算压缩比例，目标150KB
      // JPEG 编码质量从 95 开始尝试，逐步降低
      int quality = 90;
      List<int>? compressed;
      
      while (quality >= 30) {
        compressed = images.encodeJpg(image, quality: quality);
        final compressedKB = compressed.length / 1024;
        
        if (compressedKB <= 150) {
          print('📷 压缩成功: ${fileSizeKB.toStringAsFixed(1)}KB -> ${compressedKB.toStringAsFixed(1)}KB (quality=$quality)');
          break;
        }
        quality -= 10;
      }

      if (compressed != null && compressed.length < bytes.length) {
        // 保存压缩后的文件
        final compressedFile = File(filePath);
        await compressedFile.writeAsBytes(compressed);
        print('📷 压缩后大小: ${(compressed.length / 1024).toStringAsFixed(1)}KB');
        return filePath;
      }
      
      // 如果压缩后仍然太大，使用更激进的压缩
      if (compressed != null) {
        final compressedKB = compressed.length / 1024;
        print('📷 最小压缩后仍 ${compressedKB.toStringAsFixed(1)}KB，继续压缩...');
        
        // 缩放图片尺寸
        final scale = 150 / compressedKB;
        final newWidth = (image.width * scale * 0.8).toInt().clamp(320, 1920);
        final resized = images.copyResize(image, width: newWidth);
        
        // 再次尝试低质量编码
        for (int q = 50; q >= 20; q -= 10) {
          final smallCom = images.encodeJpg(resized, quality: q);
          if (smallCom.length / 1024 <= 150) {
            await File(filePath).writeAsBytes(smallCom);
            print('📷 最终压缩: ${(smallCom.length / 1024).toStringAsFixed(1)}KB (缩放+quality=$q)');
            return filePath;
          }
        }
        
        // 最后手段：使用极低质量
        final lastCom = images.encodeJpg(resized, quality: 20);
        await File(filePath).writeAsBytes(lastCom);
        print('📷 强制压缩: ${(lastCom.length / 1024).toStringAsFixed(1)}KB');
        return filePath;
      }
      
      return filePath;
    } catch (e) {
      print('⚠️ 图片压缩异常: $e');
      return filePath; // 失败时返回原路径
    }
  }

  /// 上传图片到云存储（带重试和自动压缩）
  Future<String?> uploadImage(String filePath, String fileName, {int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('📷 开始上传图片: $fileName (第$attempt/$maxRetries次尝试)');
        print('📷 文件路径: $filePath');
        
        // 检查文件是否存在
        final file = File(filePath);
        if (!await file.exists()) {
          print('❌ 文件不存在: $filePath');
          // 尝试检查父目录是否存在
          final dir = file.parent;
          print('📷 检查目录: ${dir.path}, exists=${await dir.exists()}');
          return null;
        }
        
        // 获取文件大小
        final fileSize = await file.length();
        print('📷 原始文件大小: ${(fileSize / 1024).toStringAsFixed(1)} KB');
        
        if (fileSize == 0) {
          print('❌ 文件大小为0: $filePath');
          return null;
        }
        
        // ===== 自动压缩：图片大于150KB时自动压缩 =====
        String pathToUpload = filePath;
        if (fileSize > 150 * 1024) { // 超过150KB
          print('📷 图片 ${(fileSize / 1024).toStringAsFixed(1)}KB > 150KB，开始自动压缩...');
          final compressed = await compressImageForUpload(filePath);
          if (compressed != null && compressed != filePath) {
            pathToUpload = compressed;
            final newFile = File(pathToUpload);
            final newSize = await newFile.length();
            print('📷 压缩后: ${(newSize / 1024).toStringAsFixed(1)} KB');
          }
        }
        
        // 读取文件并转为Base64
        final bytes = await File(pathToUpload).readAsBytes();
        final base64Data = base64Encode(bytes);
        
        print('📷 Base64编码后: ${base64Data.length} chars (${(base64Data.length / 1024).toStringAsFixed(1)} KB)');
        
        // 检查Base64数据是否有效
        if (base64Data.isEmpty) {
          print('❌ Base64编码失败，数据为空');
          return null;
        }
        
        // 检查Base64数据大小（云函数3秒超时限制）
        // 150KB图片Base64约200KB，是安全上限
        if (base64Data.length > 250 * 1024) { // 超过250KB可能超时
          print('⚠️ Base64数据过大(${base64Data.length} chars)，进行二次压缩...');
          await compressImageForUpload(pathToUpload);
          final reBytes = await File(pathToUpload).readAsBytes();
          final reBase64 = base64Encode(reBytes);
          print('📷 二次压缩后: ${reBase64.length} chars (${(reBase64.length / 1024).toStringAsFixed(1)} KB)');
        }
        
        // 通过云函数上传图片
        print('📤 调用云函数uploadImage...');
        final result = await callApi('uploadImage', data: {
          'fileName': fileName,
          'fileData': base64Data,
        });
        
        print('📥 云函数返回: code=${result['code']}, message=${result['message'] ?? '无消息'}');
        
        if (result['code'] == 0) {
          // 优先返回 fileId（永久引用），无 fileId 时回退到 url（临时URL）
          // fileId 格式: cloud://环境ID.应用ID/路径（永久有效）
          final fileId = result['fileId'];
          if (fileId != null && fileId.toString().isNotEmpty) {
            print('✅ 上传成功，使用fileID: $fileId');
            return fileId.toString();
          }
          if (result['url'] != null) {
            print('✅ 上传成功，使用URL（临时）：${result['url']}');
            return result['url'];
          }
          print('⚠️ 上传成功但无返回URL');
          return null;
        } else {
          print('❌ 上传失败: code=${result['code']}, message=${result['message']}');
          if (attempt < maxRetries) {
            print('等待2秒后重试...');
            await Future.delayed(Duration(seconds: 2));
            continue;
          }
          return null;
        }
      } catch (e, stackTrace) {
        print('❌ 上传异常 (第$attempt次): $e');
        print('❌ 堆栈: $stackTrace');
        if (attempt < maxRetries) {
          print('等待2秒后重试...');
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
        return null;
      }
    }
    return null;
  }
  
  /// 添加隐患到云端（支持多种action格式）
  /// 返回云端 _id（用于后续更新操作），失败时返回 null
  Future<String?> addIssue(Map<String, dynamic> issueData) async {
    if (!_useCloudBase) return null;
    
    try {
      print('📤 正在上传隐患到云端: ${issueData['title']}');
      print('📤 上传数据: $issueData');
      
      // 确保必填字段存在
      final dataToUpload = Map<String, dynamic>.from(issueData);
      if (!dataToUpload.containsKey('createdAt')) {
        dataToUpload['createdAt'] = DateTime.now().toIso8601String();
      }
      if (!dataToUpload.containsKey('updatedAt')) {
        dataToUpload['updatedAt'] = DateTime.now().toIso8601String();
      }
      if (!dataToUpload.containsKey('status')) {
        dataToUpload['status'] = 'pending';
      }
      
      // 尝试多种可能的 action 名称
      final actions = ['addIssue', 'add', 'createIssue', 'insert'];
      Map<String, dynamic>? lastResult;
      
      for (final action in actions) {
        print('📤 尝试 action: $action');
        final result = await callApi(action, collection: 'hazards', data: dataToUpload);
        lastResult = result;
        
        if (result['code'] == 0) {
          final cloudId = result['id'] ?? result['_id'] ?? dataToUpload['id'];
          print('✅ 隐患已上传到云端 (action=$action): $cloudId');
          return cloudId?.toString();
        } else {
          print('⚠️ action=$action 失败: code=${result['code']}, message=${result['message']}');
        }
      }
      
      // 所有 action 都失败
      print('❌ 所有 action 都失败，最后结果: $lastResult');
      return null;
    } catch (e) {
      print('❌ 上传异常: $e');
      return null;
    }
  }
  
  /// 添加部门到云端
  Future<bool> addDepartment(String departmentName) async {
    if (!_useCloudBase) return false;
    
    try {
      final result = await callApi('add', collection: 'departments', data: {
        'name': departmentName,
        'department': departmentName,
        'createdAt': DateTime.now().toIso8601String(),
      });
      
      if (result['code'] == 0) {
        print('✅ 部门已添加到云端: $departmentName');
        return true;
      } else {
        print('❌ 添加部门失败: ${result['message']}');
        return false;
      }
    } catch (e) {
      print('❌ 添加部门异常: $e');
      return false;
    }
  }
  
  /// 从云端获取隐患列表
  Future<List<models.Issue>> getCloudIssues() async {
    if (!_useCloudBase) return [];
    
    try {
      print('🔍 正在从云端获取隐患列表...');
      // 关键：排除已撤回的记录（isDeleted=true 或 status=deleted）
      final result = await callApi(
        'query',
        collection: 'hazards',
        query: {
          'isDeleted': {'\$ne': true},
        },
      );
      
      if (result['code'] == 0 && result['data'] != null) {
        final List<dynamic> dataList = result['data'];
        print('📥 从云端获取了 ${dataList.length} 条隐患数据（已排除撤回记录）');
        
        // 调试：打印第一条数据看看结构
        if (dataList.isNotEmpty) {
          print('📋 示例数据字段: ${(dataList.first as Map).keys.join(", ")}');
        }
        
        return dataList.map((json) => models.Issue.fromJson(json as Map<String, dynamic>)).toList();
      }
      
      print('⚠️ 云端无隐患数据');
      return [];
    } catch (e) {
      print('❌ 获取云端隐患失败: $e');
      return [];
    }
  }

  /// 根据整改责任人ID获取隐患列表
  Future<List<models.Issue>> getCloudIssuesByAssignee(String assigneeId) async {
    if (!_useCloudBase) return [];
    
    try {
      print('🔍 正在从云端获取整改责任人 [$assigneeId] 的隐患列表...');
      // 排除已撤回记录
      final result = await callApi('query', collection: 'hazards', query: {
        'assigneeId': assigneeId,
        'isDeleted': {'\$ne': true},
      });
      
      if (result['code'] == 0 && result['data'] != null) {
        final List<dynamic> dataList = result['data'];
        print('📥 从云端获取了 ${dataList.length} 条属于该责任人的隐患');
        return dataList.map((json) => models.Issue.fromJson(json as Map<String, dynamic>)).toList();
      }
      
      return [];
    } catch (e) {
      print('❌ 获取责任人隐患失败: $e');
      return [];
    }
  }

  /// 查询用户列表
  Future<List<Map<String, dynamic>>> queryUsers() async {
    if (!_useCloudBase) return [];
    
    try {
      // 排除已禁用的用户（status: 'disabled'）
      final result = await callApi('query', collection: 'users', query: {'status': {'\$ne': 'disabled'}});
      
      if (result['code'] == 0 && result['data'] != null) {
        final List<dynamic> dataList = result['data'];
        return dataList.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('查询用户失败: $e');
      return [];
    }
}

  /// 更新云端隐患状态
  Future<bool> updateIssueStatus(String issueId, String newStatus) async {
    if (!_useCloudBase) return false;
    
    try {
      final result = await callApi('updateIssueStatus', collection: 'hazards', data: {
        'issueId': issueId,
        'status': newStatus,
      });
      
      if (result['code'] == 0) {
        print('✅ 隐患状态已更新到云端');
        return true;
      } else {
        print('❌ 更新隐患状态失败: ${result['message']}');
        return false;
      }
    } catch (e) {
      print('❌ 更新隐患状态异常: $e');
      return false;
    }
  }
  
  /// 更新云端隐患状态和验收意见
  Future<bool> updateIssueWithReview(
    String issueId,
    String newStatus,
    String? acceptanceNote, {
    List<Map<String, dynamic>>? rejectionHistory,
  }) async {
    if (!_useCloudBase) return false;
    
    try {
      print('📤 正在同步隐患验收结果到云端: $issueId');
      print('📤 新状态: $newStatus, 验收意见: $acceptanceNote');
      
      // 构建上传数据，包含所有相关字段
      final data = <String, dynamic>{
        'status': newStatus,
        'acceptanceNote': acceptanceNote,  // 验收意见
        'updatedAt': DateTime.now().toIso8601String(),
      };
      
      // 关键：同步驳回历史（防止刷新后丢失）
      if (rejectionHistory != null && rejectionHistory.isNotEmpty) {
        data['rejectionHistory'] = rejectionHistory;
      }
      
      // 使用 _id 字段查询（云端主键）
      final result = await callApi(
        'update',
        collection: 'hazards',
        query: {'_id': issueId},
        data: data,
      );
      
      if (result['code'] == 0) {
        print('✅ 隐患验收结果已同步到云端: $issueId');
        return true;
      } else {
        print('❌ 同步验收结果失败: ${result['message']}');
        // 即使云端失败也返回 true，让本地数据可用
        return true;
      }
    } catch (e) {
      print('❌ 同步验收结果异常: $e');
      return true; // 异常时也返回 true，本地已更新
    }
  }

  /// 更新云端隐患的驳回意见
  Future<bool> updateRejectionNote(String issueId, String? rejectionNote) async {
    if (!_useCloudBase) return false;
    
    try {
      print('📤 正在同步驳回意见到云端: $issueId');
      
      final result = await callApi(
        'update',
        collection: 'hazards',
        query: {'_id': issueId},
        data: {
          'rejectionNote': rejectionNote,  // 驳回意见
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
      
      if (result['code'] == 0) {
        print('✅ 驳回意见已同步到云端: $issueId');
        return true;
      } else {
        print('❌ 同步驳回意见失败: ${result['message']}');
        return true; // 本地已更新
      }
    } catch (e) {
      print('❌ 同步驳回意见异常: $e');
      return true;
    }
  }
  
  /// 驳回问题（一次性同步状态和驳回意见，支持多次驳回历史）
  Future<bool> rejectIssue(String issueId, {required String rejectionNote, List<Map<String, dynamic>>? rejectionHistory}) async {
    if (!_useCloudBase) return false;
    
    try {
      print('📤 正在同步驳回结果到云端: $issueId');
      print('📤 驳回意见: $rejectionNote');
      print('📤 驳回历史: ${rejectionHistory?.length ?? 0} 条');
      
      // 构建更新数据
      final updateData = {
        'status': 'processing',      // 驳回后状态变为整改中
        'statusIndex': 1,            // pending=0, processing=1, reviewing=2, closed=3
        'rejectionNote': rejectionNote, // 最新驳回意见（兼容旧数据）
        'updatedAt': DateTime.now().toIso8601String(),
      };
      
      // 如果有驳回历史，一并同步
      if (rejectionHistory != null) {
        updateData['rejectionHistory'] = rejectionHistory;
      }
      
      // 一次性同步状态和驳回意见
      final result = await callApi(
        'update',
        collection: 'hazards',
        query: {'_id': issueId},
        data: updateData,
      );
      
      if (result['code'] == 0) {
        print('✅ 驳回结果已同步到云端: $issueId');
        return true;
      } else {
        print('❌ 同步驳回结果失败: ${result['message']}');
        return true; // 本地已更新
      }
    } catch (e) {
      print('❌ 同步驳回结果异常: $e');
      return true;
    }
  }
  
  /// 更新云端隐患的整改责任人
  Future<bool> updateIssueAssignee(String issueId, String assigneeId, String assigneeName) async {
    if (!_useCloudBase) return false;
    
    try {
      print('📤 正在同步整改责任人到云端: $issueId -> $assigneeName');
      
      // 使用 _id 字段查询（云端主键）
      final result = await callApi(
        'update',
        collection: 'hazards',
        query: {'_id': issueId},
        data: {
          'assigneeId': assigneeId,
          'assigneeName': assigneeName,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
      
      if (result['code'] == 0) {
        print('✅ 整改责任人已同步到云端: $assigneeName');
        return true;
      } else {
        print('❌ 同步整改责任人失败: ${result['message']}');
        return true; // 本地已更新，即使云端失败也返回成功
      }
    } catch (e) {
      print('❌ 同步整改责任人异常: $e');
      return true; // 异常时也返回 true，本地已更新
    }
  }
  
  /// 同步整改反馈到云端
  Future<bool> updateRectification(
    String issueId,
    List<Map<String, dynamic>> rectificationHistory,
    int status,
    List<String> rectificationPhotos,
    String? rectificationNote,
  ) async {
    if (!_useCloudBase) return false;

    try {
      print('📤 正在同步整改反馈到云端: $issueId');
      print('📤 整改记录数: ${rectificationHistory.length}');
      print('📤 整改照片数: ${rectificationPhotos.length}');
      print('📤 整改说明: $rectificationNote');

      // 准备要更新的字段
      final updateData = {
        'status': 'reviewing',
        'statusIndex': status,
        'rectificationHistory': rectificationHistory,
        'rectificationPhotos': rectificationPhotos,
        'rectificationNote': rectificationNote, // 关键：同步整改说明，便于检查人查看
        'updatedAt': DateTime.now().toIso8601String(),
      };

      // 使用 _id 字段查询（云端主键）
      final result = await callApi(
        'update',
        collection: 'hazards',
        query: {'_id': issueId},
        data: updateData,
      );
      print('   结果: code=${result['code']}, msg=${result['message']}');

      if (result['code'] == 0) {
        print('✅ 整改反馈已同步到云端: $issueId');
        return true;
      } else {
        print('❌ 同步整改反馈失败: ${result['message']}');
        // 即使云端失败也返回 true，让本地数据可用
        return true;
      }
    } catch (e) {
      print('❌ 同步整改反馈异常: $e');
      return true; // 异常时也返回 true，本地已更新
    }
  }

  /// 获取部门列表 - 从云端departments集合获取
  Future<List<Map<String, dynamic>>> queryDepartments() async {
    if (!_useCloudBase) return [];
    
    try {
      // 尝试从departments集合获取
      final result = await callApi('query', collection: 'departments', query: {});
      
      if (result['code'] == 0 && result['data'] != null) {
        final List<dynamic> dataList = result['data'];
        print('✅ 从云端获取了 ${dataList.length} 个部门');
        return dataList.cast<Map<String, dynamic>>();
      }
      
      // 如果departments集合为空，从users集合中提取不重复的部门
      // 排除已禁用的用户
      final usersResult = await callApi('query', collection: 'users', query: {'status': {'\$ne': 'disabled'}});
      if (usersResult['code'] == 0 && usersResult['data'] != null) {
        final List<dynamic> dataList = usersResult['data'];
        Set<String> deptSet = {};
        for (var user in dataList) {
          final dept = user['department']?.toString();
          if (dept != null && dept.isNotEmpty) {
            deptSet.add(dept);
          }
        }
        final depts = deptSet.map((d) => {'name': d, 'department': d}).toList();
        print('✅ 从用户列表提取了 ${depts.length} 个部门');
        return depts;
      }
      
      return [];
    } catch (e) {
      print('获取部门列表失败: $e');
      return [];
    }
  }

  Map<String, int> getDemoStats() {
    return {
      'total': 156,
      'pending': 23,
      'processing': 45,
      'reviewing': 12,
      'closed': 76,
      'overdue': 8,
    };
  }

  /// 撤回/删除隐患（通过update将status改为deleted）
  Future<bool> deleteIssue(String cloudId) async {
    if (!_useCloudBase) return false;

    try {
      // 关键：使用 _id 字段（云端主键 UUID）查询
      // 旧数据没有 cloudId，cloudId 即为 issue.id（业务ID），CloudBase 的 query 也支持业务字段查询
      final result = await callApi(
        'update',
        collection: 'hazards',
        query: {'_id': cloudId},
        data: {
          'status': 'deleted',
          'deletedAt': DateTime.now().toIso8601String(),
          'isDeleted': true,
        },
      );
      
      if (result['code'] == 0) {
        print('✅ 隐患已撤回: $cloudId');
        return true;
      } else {
        print('❌ 撤回隐患失败: ${result['message']}');
        return false;
      }
    } catch (e) {
      print('❌ 撤回隐患异常: $e');
      return false;
    }
  }

  /// 从过期URL中提取云存储文件路径
  /// 例如: https://xxx.tcb.qcloud.la/hazards/filename.jpg?sign=xxx&t=xxx
  /// 提取出: hazards/filename.jpg
  String? extractFilePathFromUrl(String url) {
    try {
      // 去掉查询参数
      final baseUrl = url.split('?')[0];
      // 找到路径部分：在域名之后，可能是 /hazards/xxx 或 /xxx
      final uri = Uri.parse(baseUrl);
      String path = uri.path;
      // 去掉开头的 /
      if (path.startsWith('/')) path = path.substring(1);
      return path.isNotEmpty ? path : null;
    } catch (e) {
      print('⚠️ 提取文件路径失败: $e');
      return null;
    }
  }

  /// 识别照片URL是否为本地文件路径（Android缓存路径等）
  bool isLocalFilePath(String url) {
    if (url.isEmpty) return true;
    // 本地路径特征：以 / 开头但非 http
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('//') || url.startsWith('cloud://')) {
      return false;
    }
    // 以 / 开头的是本地路径（如 /data/user/0/...）
    // 以 C:\ 开头的是本地路径
    // 以 storage/ 开头的是本地路径
    if (url.startsWith('/') || url.startsWith('C:') || url.startsWith('storage')) {
      return true;
    }
    return false;
  }

  /// 获取/刷新云存储文件的临时访问URL
  /// [filePath] 可以是完整路径（如 "hazards/filename.jpg"）或 fileID
  /// 返回新的临时URL，失败返回null
  Future<String?> getFreshPhotoUrl(String filePath) async {
    if (!_useCloudBase) return null;
    
    try {
      print('🔄 正在刷新文件URL: $filePath');
      
      // 调用云函数 getFileUrl action
      final result = await callApi('getFileUrl', data: {
        'filePath': filePath,
        'maxAge': 60 * 60 * 24 * 30, // 30天
      });
      
      if (result['code'] == 0 && result['url'] != null) {
        print('✅ 文件URL刷新成功: ${result['url']}');
        return result['url'];
      } else {
        print('❌ 刷新文件URL失败: ${result['message']}');
        return null;
      }
    } catch (e) {
      print('❌ 刷新文件URL异常: $e');
      return null;
    }
  }

  /// 自动修复照片URL：如果是本地路径则尝试上传到云存储
  /// 如果是已过期的网络URL或cloud:// fileID则尝试刷新
  /// 返回修复后的URL，失败返回null
  Future<String?> repairPhotoUrl(String url, String issueId, int index) async {
    // 1. 空字符串
    if (url.isEmpty) return null;
    
    // 2. 云端 fileID（cloud:// 格式） - 永久引用，可以直接刷新
    if (url.startsWith('cloud://')) {
      final freshUrl = await getFreshPhotoUrl(url);
      if (freshUrl != null) return freshUrl;
      return url; // 刷新失败返回原值
    }
    
    // 3. 已经是有效网络URL - 尝试刷新（可能已过期）
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final filePath = extractFilePathFromUrl(url);
      if (filePath != null) {
        final freshUrl = await getFreshPhotoUrl(filePath);
        if (freshUrl != null) return freshUrl;
      }
      // 刷新失败，返回原URL（给UI层显示原有错误）
      return url;
    }
    
    // 4. 本地文件路径 - 尝试检查文件是否存在
    if (url.startsWith('/') || url.startsWith('C:') || !url.contains('://')) {
      // 检查本地文件是否存在
      try {
        final file = File(url);
        if (await file.exists()) {
          // 本地文件还在，可以尝试上传到云端
          final fileName = 'migrated_${issueId}_${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
          final uploadedUrl = await uploadImage(url, fileName);
          if (uploadedUrl != null) return uploadedUrl;
        }
      } catch (e) {
        print('⚠️ 检查本地文件失败: $e');
      }
      return null; // 本地文件不存在或上传失败
    }
    
    return null;
  }

  /// 更新隐患详情（标题、描述、分类、严重程度等）
  Future<bool> updateIssueDetail(String issueId, Map<String, dynamic> fields) async {
    if (!_useCloudBase) return false;

    try {
      print('📤 正在同步隐患详情到云端: $issueId');

      // 使用 _id 字段查询（云端主键）
      final dataFields = Map<String, dynamic>.from(fields);
      dataFields['updatedAt'] = DateTime.now().toIso8601String();
      
      final result = await callApi(
        'update',
        collection: 'hazards',
        query: {'_id': issueId},
        data: dataFields,
      );

      if (result['code'] == 0) {
        print('✅ 隐患详情已更新: $issueId');
        return true;
      } else {
        print('❌ 更新隐患详情失败: ${result['message']}');
        return true; // 本地已更新，即使云端失败也返回成功
      }
    } catch (e) {
      print('❌ 更新隐患详情异常: $e');
      return false;
    }
  }
}

/// 登录结果
class LoginResult {
  final bool success;
  final models.User? user;
  final String? error;

  LoginResult({required this.success, this.user, this.error});
}


