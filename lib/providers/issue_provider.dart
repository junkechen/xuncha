// lib/providers/issue_provider.dart
// 问题状态管理

import 'dart:io';
import 'package:flutter/material.dart';
import '../models/issue.dart';
import '../models/user.dart';
import '../services/cloudbase_service.dart';
import '../services/audio_service.dart';

enum IssueFilterType {
  all,
  pending,      // 待反馈（合并：pending+processing，整改人视角）
  rectsSubmitted, // 已反馈（整改人提交了，等待验收）
  reviewing,    // 待验收（发起人视角，需要验收审批）
  overdue,      // 待催办（超期）
  closed,       // 已完成
  reported,     // 已发起（查看自己发起的所有问题）
}

class IssueProvider extends ChangeNotifier {
  List<Issue> _issues = [];
  bool _isLoading = false;
  String? _error;
  IssueFilterType _filterType = IssueFilterType.all;
  User? _currentUser;

  /// 设置当前用户（用于权限过滤）
  void setCurrentUser(User? user) {
    _currentUser = user;
    notifyListeners();
  }

  /// 根据用户角色过滤问题列表
  /// - 管理员(admin)：查看所有问题
  /// - 巡查人/督查员/整改人/巡检员：查看分配给自己的问题（均可作为整改负责人）
  /// - 查看员(viewer)：不显示任何问题
  List<Issue> get issues {
    List<Issue> filteredIssues;
    
    if (_currentUser == null) {
      // 未登录用户看不到任何问题
      filteredIssues = [];
    } else if (_currentUser!.role == UserRole.admin || 
               _currentUser!.username == 'admin' ||
               _currentUser!.username == 'Administrator') {
      // 管理员看所有问题
      filteredIssues = _issues;
    } else if (_currentUser!.role == UserRole.viewer) {
      // 查看员不显示任何问题
      filteredIssues = [];
    } else {
      // 巡查人/督查/整改人/巡检员：只看到自己发起或分配给自己的问题
      // 关键：云端数据中 reporterId 存的是 UUID（_id），reporterName 存的是 name
      //       assigneeId 存的是 username（可靠），assigneeName 可能与 assigneeId 不一致
      //       匹配原则：只用语义明确的字段，不用 assigneeName（会导致误匹配）
      final uid = _currentUser!.id;
      final uname = _currentUser!.username;
      final uname2 = _currentUser!.name;
      filteredIssues = _issues.where((i) => 
        // assigneeId 匹配（存的是 username，可靠）
        i.assigneeId == uid || i.assigneeId == uname || i.assigneeId == uname2 ||
        // reporterId 匹配（存的是 UUID _id，云端登录时 user.id 等于 UUID）
        i.reporterId == uid || i.reporterId == uname || i.reporterId == uname2 ||
        // reporterName 匹配（作为 reporterId 的后备，本地登录时 user.id 为空）
        i.reporterName == uid || i.reporterName == uname || i.reporterName == uname2
        // 注意：不匹配 assigneeName（可能和 assigneeId 不一致，导致误匹配）
      ).toList();
    }
    
    // 再根据筛选类型过滤（基于用户角色）
    switch (_filterType) {
      case IssueFilterType.all:
        return filteredIssues;
      case IssueFilterType.pending:
        // 待反馈：当前用户作为整改人，状态为pending或processing（首次待整改+整改中被驳回）
        return filteredIssues.where((i) => 
          _isCurrentUserAssignee(i) && 
          (i.status == IssueStatus.pending || i.status == IssueStatus.processing)
        ).toList();
      case IssueFilterType.rectsSubmitted:
        // 已反馈：当前用户作为整改人，已提交整改但状态为reviewing（等待验收）
        return filteredIssues.where((i) => 
          _isCurrentUserAssignee(i) && i.status == IssueStatus.reviewing
        ).toList();
      case IssueFilterType.reviewing:
        // 待验收：当前用户作为发起人，状态为reviewing（需要发起人验收）
        return filteredIssues.where((i) => 
          _isCurrentUserReporter(i) && i.status == IssueStatus.reviewing
        ).toList();
      case IssueFilterType.overdue:
        // 待催办：当前用户作为发起人，状态为pending或processing（整改人尚未反馈）
        // 与 overdueCount 逻辑保持一致，不额外检查 isOverdue
        return filteredIssues.where((i) => 
          _isCurrentUserReporter(i) && 
          (i.status == IssueStatus.pending || i.status == IssueStatus.processing)
        ).toList();
      case IssueFilterType.closed:
        // 已完成：发起人和整改人双方都能看到已完成的项目
        return filteredIssues.where((i) =>
          (_isCurrentUserReporter(i) || _isCurrentUserAssignee(i)) &&
          i.status == IssueStatus.closed
        ).toList();
      case IssueFilterType.reported:
        // 已发起：当前用户作为发起人的所有问题（不限状态）
        return filteredIssues.where((i) =>
          _isCurrentUserReporter(i)
        ).toList();
    }
  }
  
  List<Issue> get allIssues => _issues;
  bool get isLoading => _isLoading;
  String? get error => _error;
  IssueFilterType get filterType => _filterType;

  /// 设置问题筛选类型
  void setFilterType(IssueFilterType type) {
    _filterType = type;
    notifyListeners();
  }

  /// 兼容旧方法：根据 IssueStatus 筛选
  void setFilter(IssueStatus? status) {
    if (status == null) {
      _filterType = IssueFilterType.all;
    } else if (status == IssueStatus.pending || status == IssueStatus.processing) {
      // pending 和 processing 都归为"待反馈"
      _filterType = IssueFilterType.pending;
    } else if (status == IssueStatus.reviewing) {
      _filterType = IssueFilterType.reviewing;
    } else if (status == IssueStatus.closed) {
      _filterType = IssueFilterType.closed;
    }
    notifyListeners();
  }

  /// 判断当前用户是否是问题的相关方（发起人或接收人）
  /// 规则：问题只能被发起人和整改人互相可见；管理员可见所有
  bool _isRelatedUser(Issue issue) {
    if (_currentUser == null) return false;
    final uid = _currentUser!.id;
    final uname = _currentUser!.username;
    final uname2 = _currentUser!.name;

    // 检查是否是发起人或接收人
    // 注意：只匹配 assigneeId 和 reporterId/reporterName，不匹配 assigneeName
    //       assigneeName 可能和 assigneeId 不一致（云数据中 assigneeId=田建岗, assigneeName=吕广元）
    //       用 assigneeName 匹配会导致误匹配（非责任人看到问题）
    final isReporter = issue.reporterId == uid ||
                       issue.reporterId == uname ||
                       issue.reporterId == uname2 ||
                       issue.reporterName == uid ||
                       issue.reporterName == uname ||
                       issue.reporterName == uname2;

    final isAssignee = issue.assigneeId == uid ||
                       issue.assigneeId == uname ||
                       issue.assigneeId == uname2;

    return isReporter || isAssignee;
  }
  
  /// 获取当前用户可见的问题列表（用于统计计数）
  /// 规则：管理员看所有问题；非管理员看自己发起的 + 分配给自己的问题
  /// 获取经过角色+筛选类型两层过滤后的问题列表
  List<Issue> get visibleIssues {
    if (_currentUser == null) return [];
    
    // 管理员看所有问题
    if (_currentUser!.role == UserRole.admin || 
        _currentUser!.username == 'admin' ||
        _currentUser!.username == 'Administrator') {
      // 管理员也按筛选类型过滤
      switch (_filterType) {
        case IssueFilterType.all:
          return _issues;
        case IssueFilterType.pending:
          return _issues.where((i) => 
            i.status == IssueStatus.pending || i.status == IssueStatus.processing
          ).toList();
        case IssueFilterType.rectsSubmitted:
          return _issues.where((i) => i.status == IssueStatus.reviewing).toList();
        case IssueFilterType.reviewing:
          return _issues.where((i) => i.status == IssueStatus.reviewing).toList();
        case IssueFilterType.overdue:
          return _issues.where((i) => 
            i.status == IssueStatus.pending || i.status == IssueStatus.processing
          ).toList();
        case IssueFilterType.closed:
          return _issues.where((i) => i.status == IssueStatus.closed).toList();
        case IssueFilterType.reported:
          return _issues;
      }
    }
    
    // 非管理员：看自己发起的 + 分配给自己的问题（双方都能看到）
    var myIssues = _issues.where((i) => _isRelatedUser(i)).toList();
    
    // 再根据筛选类型过滤（基于用户角色）
    switch (_filterType) {
      case IssueFilterType.all:
        break;
      case IssueFilterType.pending:
        // 待反馈：当前用户作为整改人，状态为pending或processing
        myIssues = myIssues.where((i) => 
          _isCurrentUserAssignee(i) && 
          (i.status == IssueStatus.pending || i.status == IssueStatus.processing)
        ).toList();
      case IssueFilterType.rectsSubmitted:
        // 已反馈：当前用户作为整改人，已提交整改但状态为reviewing
        myIssues = myIssues.where((i) => 
          _isCurrentUserAssignee(i) && i.status == IssueStatus.reviewing
        ).toList();
      case IssueFilterType.reviewing:
        // 待验收：当前用户作为发起人，状态为reviewing
        myIssues = myIssues.where((i) => 
          _isCurrentUserReporter(i) && i.status == IssueStatus.reviewing
        ).toList();
      case IssueFilterType.overdue:
        // 待催办：当前用户作为发起人，状态为pending或processing
        myIssues = myIssues.where((i) => 
          _isCurrentUserReporter(i) && 
          (i.status == IssueStatus.pending || i.status == IssueStatus.processing)
        ).toList();
      case IssueFilterType.closed:
        // 已完成：发起人和整改人双方都能看到已完成的项目
        myIssues = myIssues.where((i) =>
          (_isCurrentUserReporter(i) || _isCurrentUserAssignee(i)) &&
          i.status == IssueStatus.closed
        ).toList();
      case IssueFilterType.reported:
        // 已发起：当前用户作为发起人的所有问题
        myIssues = myIssues.where((i) =>
          _isCurrentUserReporter(i)
        ).toList();
    }
    
    return myIssues;
  }

  /// 待反馈 = 当前用户作为整改人，状态为 pending 或 processing 的问题（需要整改，含首次和被驳回）
  int get pendingCount {
    if (_currentUser == null) return 0;
    return _issues.where((i) {
      final isAssignee = _isCurrentUserAssignee(i);
      return isAssignee && 
             (i.status == IssueStatus.pending || i.status == IssueStatus.processing);
    }).length;
  }
  
  /// 已反馈 = 当前用户作为整改人，已提交整改但状态为 reviewing 的问题（等待验收）
  int get rectsSubmittedCount {
    if (_currentUser == null) return 0;
    return _issues.where((i) {
      final isAssignee = _isCurrentUserAssignee(i);
      return isAssignee && i.status == IssueStatus.reviewing;
    }).length;
  }
  
  /// 被驳回 = 当前用户作为整改人，状态为 processing 的问题（保留旧方法兼容）
  @Deprecated('使用 pendingCount 代替，pending 包含 pending 和 processing 两个状态')
  int get rejectedCount {
    if (_currentUser == null) return 0;
    return _issues.where((i) {
      final isAssignee = _isCurrentUserAssignee(i);
      return isAssignee && i.status == IssueStatus.processing;
    }).length;
  }
  
  /// 待验收 = 当前用户作为发起人，状态为 reviewing 的问题（需要发起人验收）
  int get reviewingCount {
    if (_currentUser == null) return 0;
    return _issues.where((i) {
      final isReporter = _isCurrentUserReporter(i);
      return isReporter && i.status == IssueStatus.reviewing;
    }).length;
  }
  
  /// 待催办 = 当前用户作为发起人，整改人尚未反馈（status 为 pending 或 processing）的问题
  /// 即：我发起后对方还没有提交整改反馈，可以催促对方整改
  int get overdueCount {
    if (_currentUser == null) return 0;
    return _issues.where((i) {
      final isReporter = _isCurrentUserReporter(i);
      return isReporter &&
          (i.status == IssueStatus.pending || i.status == IssueStatus.processing);
    }).length;
  }
  
  /// 已完成 = 当前用户相关（发起的或整改的）且已关闭的问题
  /// 发起人和整改人双方都能看到已完成的项目
  int get closedCount {
    if (_currentUser == null) return 0;
    final uid = _currentUser!.id;
    final uname = _currentUser!.username;
    final uname2 = _currentUser!.name;
    return _issues.where((i) {
      final isRelated = i.assigneeId == uid || i.assigneeId == uname || i.assigneeId == uname2 ||
          i.reporterId == uid || i.reporterId == uname || i.reporterId == uname2 ||
          i.reporterName == uid || i.reporterName == uname || i.reporterName == uname2;
      return isRelated && i.status == IssueStatus.closed;
    }).length;
  }
  
  /// 判断当前用户是否是该问题的发起人
  bool _isCurrentUserReporter(Issue i) {
    if (_currentUser == null) return false;
    final u = _currentUser!;
    return i.reporterId == u.id ||
        i.reporterId == u.username ||
        i.reporterId == u.name ||
        i.reporterName == u.id ||
        i.reporterName == u.username ||
        i.reporterName == u.name;
  }
  
  /// 判断当前用户是否是该问题的整改人
  /// 注意：只匹配 assigneeId（不匹配 assigneeName，避免误匹配）
  bool _isCurrentUserAssignee(Issue i) {
    if (_currentUser == null) return false;
    final u = _currentUser!;
    return i.assigneeId == u.id ||
        i.assigneeId == u.username ||
        i.assigneeId == u.name;
  }

  /// 获取分配给当前用户的待处理问题（不区分角色）
  /// 规则：分配给自己的 + 自己发起的待处理问题
  List<Issue> get myPendingIssues {
    if (_currentUser == null) return [];
    final uid = _currentUser!.id;
    final uname = _currentUser!.username;
    final uname2 = _currentUser!.name;
    return _issues.where((i) {
      // 判断是否是分配给自己的（只匹配 assigneeId，不匹配 assigneeName）
      final isAssignee = i.assigneeId == uid || i.assigneeId == uname || i.assigneeId == uname2;
      // 判断是否是自己发起的
      final isReporter = i.reporterId == uid || i.reporterId == uname || i.reporterId == uname2 ||
          i.reporterName == uid || i.reporterName == uname || i.reporterName == uname2;
      return (isAssignee || isReporter) &&
             (i.status == IssueStatus.pending || i.status == IssueStatus.processing);
    }).toList();
  }
  
  /// 获取分配给当前整改人的问题（兼容旧代码）
  List<Issue> get myRectificationIssues {
    return myPendingIssues;
  }

  // 从云端加载数据
  Future<void> loadIssues({bool playSound = false}) async {
    final oldCount = _issues.length;
    final oldIds = _issues.map((i) => i.id).toSet();
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 优先从云端获取数据
      final cloudService = CloudBaseService.instance;
      final cloudIssues = await cloudService.getCloudIssues();

      if (cloudIssues.isNotEmpty) {
        // 合并云端数据与本地数据：
        // - 保留本地 Issue 对象的完整字段（包含 rejectionHistory 等云端可能缺失的字段）
        // - 用云端数据覆盖同 ID 记录的字段（保证云端最新）
        final localMap = {for (var i in _issues) i.id: i};
        final mergedIssues = <Issue>[];
        
        for (final cloudIssue in cloudIssues) {
          final localIssue = localMap[cloudIssue.id];
          if (localIssue != null) {
            // 合并：云端覆盖 + 保留本地独有字段
            // rejectionHistory 需要合并（云端和本地各可能有不同的驳回记录）
            final mergedRejectionHistory = <RejectionRecord>{
              ...localIssue.rejectionHistory,
              ...cloudIssue.rejectionHistory,
            }.toList()
              ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
            
            // rectificationHistory 也需要合并（防止离线提交的整改记录在云端同步时丢失）
            final mergedRectificationHistory = <RectificationRecord>{
              ...localIssue.rectificationHistory,
              ...cloudIssue.rectificationHistory,
            }.toList()
              ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
            
            mergedIssues.add(Issue(
              id: cloudIssue.id,
              cloudId: cloudIssue.cloudId.isNotEmpty ? cloudIssue.cloudId : localIssue.cloudId,
              title: cloudIssue.title,
              description: cloudIssue.description,
              category: cloudIssue.category,
              severity: cloudIssue.severity,
              photos: cloudIssue.photos,
              location: cloudIssue.location,
              department: cloudIssue.department,
              reporterId: cloudIssue.reporterId,
              reporterName: cloudIssue.reporterName,
              assigneeId: cloudIssue.assigneeId,
              assigneeName: cloudIssue.assigneeName,
              deadline: cloudIssue.deadline,
              status: cloudIssue.status,
              rectificationPhotos: cloudIssue.rectificationPhotos.isNotEmpty 
                  ? cloudIssue.rectificationPhotos : localIssue.rectificationPhotos,
              rectificationNote: cloudIssue.rectificationNote ?? localIssue.rectificationNote,
              rejectionNote: cloudIssue.rejectionNote ?? localIssue.rejectionNote,
              acceptanceNote: cloudIssue.acceptanceNote ?? localIssue.acceptanceNote,
              createdAt: cloudIssue.createdAt,
              updatedAt: cloudIssue.updatedAt,
              closedAt: cloudIssue.closedAt,
              // 合并云端和本地的整改记录（去重后按时间排序）
              rectificationHistory: mergedRectificationHistory,
              // 合并云端和本地的驳回历史（去重后按时间排序）
              rejectionHistory: mergedRejectionHistory,
            ));
          } else {
            // 云端新增的记录
            mergedIssues.add(cloudIssue);
          }
        }
        
        _issues = mergedIssues;
        // 按创建时间倒序排列（最新的在前面）
        _issues.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        print('✅ 从云端加载了 ${_issues.length} 条隐患数据（已合并本地数据，按时间倒序）');
        
        // 如果有新增问题且需要播放提示音
        if (playSound && _issues.length > oldCount) {
          final newIssues = _issues.where((i) => !oldIds.contains(i.id)).toList();
          if (newIssues.isNotEmpty) {
            print('🔔 发现 ${newIssues.length} 条新问题，播放警告音');
            AudioService.instance.playAlertSound();
          }
        }
      } else {
        // 云端为空时，加载本地演示数据作为备选
        print('⚠️ 云端暂无数据，加载本地演示数据');
        _issues = _getDemoIssues();
      }
    } catch (e) {
      print('❌ 加载云端数据失败: $e');
      _error = '加载数据失败: $e';
      // 失败时也加载本地演示数据
      _issues = _getDemoIssues();
    }

    _isLoading = false;
    notifyListeners();
  }

  // 本地演示数据（仅在云端无数据时使用）
  List<Issue> _getDemoIssues() {
    return [
      Issue(
        id: 'issue_001',
        title: '冷轧车间排水口COD超标',
        description: '冷轧车间排水口取样检测COD浓度为128mg/L，超出排放标准（100mg/L）28%',
        category: IssueCategory.wastewater,
        severity: SeverityLevel.critical,
        photos: [],
        location: '冷轧车间东侧排水口',
        reporterId: 'inspector_001',
        reporterName: '张检查',
        assigneeId: 'rectifier_001',
        assigneeName: '王整改',
        deadline: DateTime.now().subtract(const Duration(days: 2)),
        status: IssueStatus.processing,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Issue(
        id: 'issue_002',
        title: '镀锌线粉尘收集装置故障',
        description: '镀锌线运行时噪音超标，疑似风机故障',
        category: IssueCategory.wastegas,
        severity: SeverityLevel.serious,
        photos: [],
        location: '镀锌车间2号生产线',
        reporterId: 'inspector_001',
        reporterName: '张检查',
        assigneeId: 'rectifier_001',
        assigneeName: '王整改',
        deadline: DateTime.now().add(const Duration(days: 3)),
        status: IssueStatus.processing,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now(),
      ),
      Issue(
        id: 'issue_003',
        title: '危废仓库标识牌老化',
        description: '危废仓库门口标识牌老化脱落，需更换',
        category: IssueCategory.solidWaste,
        severity: SeverityLevel.general,
        photos: [],
        location: '危废仓库门口',
        reporterId: 'inspector_001',
        reporterName: '张检查',
        assigneeId: '',
        assigneeName: '待指派',
        deadline: DateTime.now().add(const Duration(days: 7)),
        status: IssueStatus.pending,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Issue(
        id: 'issue_004',
        title: '污水处理站污泥含水率高',
        description: '污泥含水率超标，需要调整脱水设备参数',
        category: IssueCategory.wastewater,
        severity: SeverityLevel.serious,
        photos: [],
        location: '污水处理站',
        reporterId: 'inspector_001',
        reporterName: '张检查',
        assigneeId: 'rectifier_001',
        assigneeName: '王整改',
        deadline: DateTime.now().add(const Duration(days: 5)),
        status: IssueStatus.reviewing,
        rectificationPhotos: [],
        rectificationNote: '已完成设备调试，污泥含水率已达标',
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        updatedAt: DateTime.now(),
      ),
    ];
  }

  Future<bool> createIssue(Issue issue) async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));

    // 同步新增到云端（先上传，获取云端返回的 _id）
    String? cloudId;
    try {
      final cloudService = CloudBaseService.instance;
      final cloudData = {
        'id': 'issue_${DateTime.now().millisecondsSinceEpoch}',
        'title': issue.title,
        'description': issue.description,
        'category': issue.categoryName,
        'severity': issue.severityName,
        'status': 'pending',
        'location': issue.location,
        'department': issue.department,
        'photos': issue.photos,
        'reporterId': issue.reporterId,
        'reporterName': issue.reporterName,
        'assigneeId': issue.assigneeId,
        'assigneeName': issue.assigneeName,
        'createdAt': DateTime.now().toIso8601String(),
        'dueDate': issue.deadline?.toIso8601String(),
      };
      cloudId = await cloudService.addIssue(cloudData);
      print('✅ 隐患已同步到云端，cloudId: $cloudId');
    } catch (e) {
      print('⚠️ 云端同步异常: $e');
    }

    // 创建本地 Issue 对象（含 cloudId）
    final newIssue = Issue(
      id: 'issue_${DateTime.now().millisecondsSinceEpoch}',
      cloudId: cloudId ?? '', // 保存云端 _id，用于后续更新
      title: issue.title,
      description: issue.description,
      category: issue.category,
      severity: issue.severity,
      photos: issue.photos,
      location: issue.location,
      reporterId: issue.reporterId,
      reporterName: issue.reporterName,
      assigneeId: issue.assigneeId,
      assigneeName: issue.assigneeName,
      deadline: issue.deadline,
      status: IssueStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _issues.insert(0, newIssue);
    // 保持时间倒序排列
    _issues.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _isLoading = false;
    notifyListeners();
    return true;
  }

  Future<bool> updateIssueStatus(String issueId, IssueStatus newStatus, {String? acceptanceNote}) async {
    _isLoading = true;
    notifyListeners();
    
    final index = _issues.indexWhere((i) => i.id == issueId);
    if (index != -1) {
      final issue = _issues[index];
      
      _issues[index] = Issue(
        id: issue.id,
        cloudId: issue.cloudId,
        title: issue.title,
        description: issue.description,
        category: issue.category,
        severity: issue.severity,
        photos: issue.photos,
        location: issue.location,
        department: issue.department,
        reporterId: issue.reporterId,
        reporterName: issue.reporterName,
        assigneeId: issue.assigneeId,
        assigneeName: issue.assigneeName,
        deadline: issue.deadline,
        status: newStatus,
        rectificationPhotos: issue.rectificationPhotos,
        rectificationNote: issue.rectificationNote,
        rejectionNote: issue.rejectionNote,
        acceptanceNote: acceptanceNote ?? issue.acceptanceNote,
        createdAt: issue.createdAt,
        updatedAt: DateTime.now(),
        closedAt: newStatus == IssueStatus.closed ? DateTime.now() : null,
        rectificationHistory: issue.rectificationHistory,
        rejectionHistory: issue.rejectionHistory, // 保留历史驳回记录
      );
      notifyListeners();
      
      // 同步更新到云端（包含验收意见）
      try {
        final cloudService = CloudBaseService.instance;
        // 使用 cloudId 字段（云端 _id）同步；旧数据 fallback 到 issue.id
        final cloudId = issue.cloudId.isNotEmpty ? issue.cloudId : issue.id;
        final statusStr = _statusToString(newStatus);
        final success = await cloudService.updateIssueWithReview(
          cloudId, 
          statusStr, 
          acceptanceNote ?? '验收通过',
          rejectionHistory: issue.rejectionHistory.map((r) => r.toJson()).toList(),
        );
        if (success) {
          print('✅ 隐患状态和验收意见已同步到云端: $cloudId -> $statusStr');
        } else {
          print('⚠️ 云端同步失败，但本地已更新');
        }
      } catch (e) {
        print('⚠️ 云端同步异常: $e');
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }
  
  /// 仅更新驳回意见（驳回时使用）
  Future<bool> updateReviewNote(String issueId, String note) async {
    _isLoading = true;
    notifyListeners();
    
    final index = _issues.indexWhere((i) => i.id == issueId);
    if (index != -1) {
      final issue = _issues[index];
      _issues[index] = Issue(
        id: issue.id,
        cloudId: issue.cloudId,
        title: issue.title,
        description: issue.description,
        category: issue.category,
        severity: issue.severity,
        photos: issue.photos,
        location: issue.location,
        department: issue.department,
        reporterId: issue.reporterId,
        reporterName: issue.reporterName,
        assigneeId: issue.assigneeId,
        assigneeName: issue.assigneeName,
        deadline: issue.deadline,
        status: issue.status,
        rectificationPhotos: issue.rectificationPhotos,
        rectificationNote: issue.rectificationNote,
        rejectionNote: note,
        acceptanceNote: issue.acceptanceNote,
        createdAt: issue.createdAt,
        updatedAt: DateTime.now(),
        closedAt: issue.closedAt,
        rectificationHistory: issue.rectificationHistory,
      );
      notifyListeners();
      
      // 同步到云端
      try {
        final cloudService = CloudBaseService.instance;
        final cloudId = issue.cloudId.isNotEmpty ? issue.cloudId : issue.id;
        await cloudService.updateRejectionNote(cloudId, note);
      } catch (e) {
        print('⚠️ 云端同步驳回意见失败: $e');
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }
  
  /// 驳回问题（一次性同步状态和驳回意见，避免分两次调用导致数据不一致）
  /// 支持多次驳回：每次驳回都会追加到历史记录
  Future<bool> rejectIssue(String issueId, {required String rejectionNote, String? reviewerId, String? reviewerName}) async {
    _isLoading = true;
    notifyListeners();
    
    final index = _issues.indexWhere((i) => i.id == issueId);
    if (index != -1) {
      final issue = _issues[index];
      
      // 构建新的驳回记录
      final newRejection = RejectionRecord(
        timestamp: DateTime.now(),
        note: rejectionNote,
        reviewerId: reviewerId ?? _currentUser?.id ?? '',
        reviewerName: reviewerName ?? _currentUser?.name ?? '未知',
      );
      
      // 追加到驳回历史（保留所有历史记录）
      final updatedRejectionHistory = [...issue.rejectionHistory, newRejection];
      
      // 更新本地数据：状态变为 processing
      _issues[index] = Issue(
        id: issue.id,
        cloudId: issue.cloudId,
        title: issue.title,
        description: issue.description,
        category: issue.category,
        severity: issue.severity,
        photos: issue.photos,
        location: issue.location,
        department: issue.department,
        reporterId: issue.reporterId,
        reporterName: issue.reporterName,
        assigneeId: issue.assigneeId,
        assigneeName: issue.assigneeName,
        deadline: issue.deadline,
        status: IssueStatus.processing, // 驳回后变为整改中
        rectificationPhotos: issue.rectificationPhotos,
        rectificationNote: issue.rectificationNote, // 保留之前的整改反馈
        rejectionNote: rejectionNote, // 保留最新驳回意见（兼容旧数据）
        acceptanceNote: issue.acceptanceNote,
        rejectionHistory: updatedRejectionHistory, // 驳回历史记录
        createdAt: issue.createdAt,
        updatedAt: DateTime.now(),
        closedAt: issue.closedAt,
        rectificationHistory: issue.rectificationHistory,
      );
      notifyListeners();
      print('✅ 本地驳回已保存，状态改为整改中: ${issue.title}，累计驳回 ${updatedRejectionHistory.length} 次');
      
      // 一次性同步到云端：同时包含状态和驳回历史
      try {
        final cloudService = CloudBaseService.instance;
        final cloudId = issue.cloudId.isNotEmpty ? issue.cloudId : issue.id;
        
        // 调用云端驳回方法，一次性同步状态和驳回历史
        final success = await cloudService.rejectIssue(
          cloudId,
          rejectionNote: rejectionNote,
          rejectionHistory: updatedRejectionHistory.map((r) => r.toJson()).toList(),
        );
        
        if (success) {
          print('✅ 云端驳回已同步: $cloudId');
        } else {
          print('⚠️ 云端同步驳回失败，但本地已保存');
        }
      } catch (e) {
        print('⚠️ 云端同步驳回异常: $e，本地已保存');
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }
  
  /// 更新整改责任人
  /// 关键：换人后状态重置为 pending，确保新整改人在"待反馈"中能看到
  Future<bool> updateAssignee(String issueId, String assigneeId, String assigneeName) async {
    _isLoading = true;
    notifyListeners();
    
    final index = _issues.indexWhere((i) => i.id == issueId);
    if (index != -1) {
      final issue = _issues[index];
      // 换人后状态重置为 pending，让新整改人能在"待反馈"列表看到
      final newStatus = IssueStatus.pending;
      _issues[index] = Issue(
        id: issue.id,
        cloudId: issue.cloudId,
        title: issue.title,
        description: issue.description,
        category: issue.category,
        severity: issue.severity,
        photos: issue.photos,
        location: issue.location,
        department: issue.department,
        latitude: issue.latitude,
        longitude: issue.longitude,
        reporterId: issue.reporterId,
        reporterName: issue.reporterName,
        assigneeId: assigneeId,
        assigneeName: assigneeName,
        deadline: issue.deadline,
        status: newStatus,
        rectificationPhotos: issue.rectificationPhotos,
        rectificationNote: issue.rectificationNote,
        createdAt: issue.createdAt,
        updatedAt: DateTime.now(),
        closedAt: issue.closedAt,
        rectificationHistory: issue.rectificationHistory,
        acceptanceNote: issue.acceptanceNote,
        rejectionHistory: issue.rejectionHistory,
      );
      notifyListeners();
      
      // 同步到云端（同时同步 assignee 和 status）
      try {
        final cloudService = CloudBaseService.instance;
        final cloudId = issue.cloudId.isNotEmpty ? issue.cloudId : issue.id;
        await cloudService.updateIssueAssignee(cloudId, assigneeId, assigneeName);
        // 同时更新云端状态
        await cloudService.updateIssueStatus(cloudId, 'pending');
        print('✅ 整改责任人已更新到云端: $assigneeName，状态重置为 pending');
      } catch (e) {
        print('⚠️ 云端同步整改责任人失败: $e');
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }
  
  /// 提交整改反馈（新增整改记录并同步云端）
  /// 策略：先更新本地数据确保立即生效，再同步云端
  /// photos 参数接受 File 对象列表（已压缩的照片）
  Future<bool> submitRectification({
    required String issueId,
    required String description,
    required List<File> photos,
    required String submitterId,
    required String submitterName,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final index = _issues.indexWhere((i) => i.id == issueId);
      if (index == -1) {
        print('❌ 未找到隐患: $issueId');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final issue = _issues[index];

      // 将 File 对象列表转换为路径字符串列表
      final photoPaths = photos.map((f) => f.path).toList();
      print('📷 整改照片数量: ${photoPaths.length}');

      // ====== 第一步：上传照片到云存储，获取可访问的 URL ======
      final cloudService = CloudBaseService.instance;
      final List<String> cloudPhotoUrls = [];
      
      for (int i = 0; i < photos.length; i++) {
        final file = photos[i];
        final fileName = 'rectification_${issueId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final uploadedUrl = await cloudService.uploadImage(file.path, fileName);
        
        if (uploadedUrl != null) {
          cloudPhotoUrls.add(uploadedUrl);
          print('📷 照片 $i 上传成功: $uploadedUrl');
        } else {
          // 上传失败时保留本地路径（兜底）
          cloudPhotoUrls.add(file.path);
          print('⚠️ 照片 $i 上传失败，保留本地路径');
        }
      }

      // 创建新的整改记录（存URL，兼顾本地和云端显示）
      final newRecord = RectificationRecord(
        timestamp: DateTime.now(),
        description: description,
        photos: cloudPhotoUrls, // 用云端URL，本地和云端都能正常显示
        submitterId: submitterId,
        submitterName: submitterName,
      );

      // 添加到历史记录
      final updatedHistory = [...issue.rectificationHistory, newRecord];
      final allPhotos = [...issue.rectificationPhotos, ...cloudPhotoUrls];

      // ====== 第二步：立即更新本地数据 ======
      _issues[index] = Issue(
        id: issue.id,
        cloudId: issue.cloudId, // 保留云端 _id
        title: issue.title,
        description: issue.description,
        category: issue.category,
        severity: issue.severity,
        photos: issue.photos,
        location: issue.location,
        department: issue.department,
        reporterId: issue.reporterId,
        reporterName: issue.reporterName,
        assigneeId: issue.assigneeId,
        assigneeName: issue.assigneeName,
        deadline: issue.deadline,
        status: IssueStatus.reviewing, // 改为待验收
        rectificationPhotos: allPhotos,
        rectificationNote: description, // 整改说明存入 rectificationNote
        createdAt: issue.createdAt,
        updatedAt: DateTime.now(),
        closedAt: issue.closedAt,
        rectificationHistory: updatedHistory,
      );
      notifyListeners();
      print('✅ 本地整改反馈已提交，状态改为待验收: ${issue.title}，cloudId=${issue.cloudId}');

      // ====== 第三步：同步到云端 ======
      try {
        final cloudIdToUpdate = issue.cloudId.isNotEmpty ? issue.cloudId : issue.id;

        final cloudSuccess = await cloudService.updateRectification(
          cloudIdToUpdate,
          updatedHistory.map((r) => r.toJson()).toList(),
          IssueStatus.reviewing.index,
          allPhotos,
          description,
        );

        if (cloudSuccess) {
          print('✅ 云端整改反馈已同步（含照片URL）: cloudId=$cloudIdToUpdate');
        } else {
          print('⚠️ 云端同步整改反馈失败 (cloudId=$cloudIdToUpdate)，本地已提交');
        }
      } catch (e) {
        print('⚠️ 云端同步整改反馈异常: $e，本地已提交');
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ 提交整改反馈异常: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  String _statusToString(IssueStatus status) {
    switch (status) {
      case IssueStatus.pending: return 'pending';
      case IssueStatus.processing: return 'processing';
      case IssueStatus.reviewing: return 'reviewing';
      case IssueStatus.closed: return 'closed';
    }
  }

  Map<String, int> getCategoryStats() {
    final stats = <String, int>{};
    for (final issue in _issues) {
      final name = issue.categoryName;
      stats[name] = (stats[name] ?? 0) + 1;
    }
    return stats;
  }

  /// 根据 ID 获取单个隐患（用于详情页获取最新数据）
  Issue? getIssueById(String issueId) {
    try {
      return _issues.firstWhere((i) => i.id == issueId);
    } catch (e) {
      return null;
    }
  }
  
  /// 获取所有整改责任人列表（从问题中提取）
  List<Map<String, String>> getAllRectifiers() {
    final Map<String, String> rectifiers = {};
    
    for (final issue in _issues) {
      // 排除空值
      if (issue.assigneeId.isNotEmpty && issue.assigneeName.isNotEmpty) {
        // 如果还没有这个整改人，或者需要更新名称
        if (!rectifiers.containsKey(issue.assigneeId)) {
          rectifiers[issue.assigneeId] = issue.assigneeName;
        }
      }
    }
    
    // 转换为列表并按名称排序
    final list = rectifiers.entries
        .map((e) => {'id': e.key, 'name': e.value})
        .toList();
    list.sort((a, b) => a['name']!.compareTo(b['name']!));
    
    return list;
  }

  /// 撤回隐患（仅发起人或管理员）
  /// 策略：先从本地移除（用户立即看到效果），再同步云端
  /// 如果云端失败，不回滚本地（避免用户困惑），但记录错误
  Future<bool> recallIssue(String issueId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // ====== 第一步：立即从本地移除，用户立即看到效果 ======
      final issueIndex = _issues.indexWhere((i) => i.id == issueId);
      if (issueIndex == -1) {
        print('⚠️ 本地未找到该隐患: $issueId');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final removedIssue = _issues[issueIndex];
      _issues.removeAt(issueIndex);
      notifyListeners();
      print('✅ 本地隐患已移除: ${removedIssue.title}');

      // ====== 第二步：异步同步到云端 ======
      // 即使云端失败，也不回滚本地（避免用户困惑）
      try {
        final cloudService = CloudBaseService.instance;
        // 使用 cloudId 同步（云端按 _id 查询）；旧数据 fallback 到 issueId
        final cloudId = removedIssue.cloudId.isNotEmpty ? removedIssue.cloudId : issueId;
        final cloudSuccess = await cloudService.deleteIssue(cloudId);

        if (cloudSuccess) {
          print('✅ 云端隐患已撤回: $cloudId');
        } else {
          print('⚠️ 云端撤回失败 (issueId=$issueId)，本地已移除');
        }
      } catch (e) {
        print('⚠️ 云端撤回异常: $e，本地已移除');
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ 撤回隐患异常: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 修改隐患详情（标题、描述、分类、严重程度、截止日期）
  /// 先更新本地数据，确保用户操作立即生效，再同步云端
  Future<bool> updateIssueDetail(String issueId, {
    String? title,
    String? description,
    String? category,
    String? severity,
    String? deadline,
    String? location,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final index = _issues.indexWhere((i) => i.id == issueId);
      if (index == -1) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final issue = _issues[index];

      // 解析 deadline
      DateTime newDeadline = issue.deadline;
      if (deadline != null) {
        try {
          newDeadline = DateTime.parse(deadline);
        } catch (e) {
          print('日期解析失败: $deadline');
        }
      }

      // 解析 category
      IssueCategory newCategory = issue.category;
      if (category != null) {
        try {
          newCategory = IssueCategory.values.firstWhere(
            (c) => c.name == category,
            orElse: () => issue.category,
          );
        } catch (e) {}
      }

      // 解析 severity
      SeverityLevel newSeverity = issue.severity;
      if (severity != null) {
        try {
          newSeverity = SeverityLevel.values.firstWhere(
            (s) => s.name == severity,
            orElse: () => issue.severity,
          );
        } catch (e) {}
      }

      // ====== 第一步：立即更新本地数据，确保用户看到变化 ======
      _issues[index] = Issue(
        id: issue.id,
        cloudId: issue.cloudId,
        title: title ?? issue.title,
        description: description ?? issue.description,
        category: newCategory,
        severity: newSeverity,
        photos: issue.photos,
        location: location ?? issue.location,
        department: issue.department,
        reporterId: issue.reporterId,
        reporterName: issue.reporterName,
        assigneeId: issue.assigneeId,
        assigneeName: issue.assigneeName,
        deadline: newDeadline,
        status: issue.status,
        rectificationPhotos: issue.rectificationPhotos,
        rectificationNote: issue.rectificationNote,
        createdAt: issue.createdAt,
        updatedAt: DateTime.now(),
        closedAt: issue.closedAt,
        rectificationHistory: issue.rectificationHistory,
      );
      notifyListeners();
      print('✅ 本地隐患数据已更新: $issueId');

      // ====== 第二步：同步到云端 ======
      final newData = <String, dynamic>{
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (title != null) newData['title'] = title;
      if (description != null) newData['description'] = description;
      if (category != null) newData['category'] = category;
      if (severity != null) newData['severity'] = severity;
      if (deadline != null) newData['deadline'] = deadline;
      if (deadline != null) newData['dueDate'] = deadline;
      if (location != null) newData['location'] = location;

      final cloudService = CloudBaseService.instance;
      // 使用 cloudId 同步（云端按 _id 查询）；旧数据 fallback 到 issueId
      final cloudId = issue.cloudId.isNotEmpty ? issue.cloudId : issueId;
      final success = await cloudService.updateIssueDetail(cloudId, newData);
      if (success) {
        print('✅ 云端隐患详情已同步: $cloudId');
      } else {
        print('⚠️ 云端同步失败，但本地已更新成功');
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ 修改隐患异常: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
