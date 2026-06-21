// lib/main.dart
// GZ巡查APP - 应用入口

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/issue_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'services/cloudbase_service.dart';
import 'services/audio_service.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

/// 全局导航和 SnackBar 管理器
class AppNavigator {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  /// 清除所有 SnackBar
  static void clearSnackBars() {
    final context = navigatorKey.currentState?.context;
    if (context != null) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化设置服务（先加载，以便 AudioService 可以读取声音开关）
  final settingsProvider = SettingsProvider();
  await settingsProvider.init();

  // 初始化音频服务（已读取声音开关配置，生成beep音频）
  await AudioService.instance.init();

  // 初始化系统通知服务
  await NotificationService.instance.initialize();

  // 初始化腾讯云开发服务
  final cloudBaseInitialized = await CloudBaseService.instance.init();

  if (!cloudBaseInitialized) {
    // 如果云服务初始化失败，显示警告
    debugPrint('⚠️ 腾讯云服务未配置，应用将以演示模式运行');
  }

  runApp(EnvInspectionApp(settingsProvider: settingsProvider));
}

class EnvInspectionApp extends StatelessWidget {
  final SettingsProvider settingsProvider;

  const EnvInspectionApp({super.key, required this.settingsProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => IssueProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          // 根据设置构建主题
          final isDark = settings.darkMode;
          final baseTextSize = settings.largeFont ? 18.0 : 16.0;
          
          return MaterialApp(
            title: 'GZ巡查',
            debugShowCheckedModeBanner: false,
            navigatorKey: AppNavigator.navigatorKey,
            theme: ThemeData(
              brightness: Brightness.light,
              primaryColor: const Color(0xFF10B981),
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF10B981),
                primary: const Color(0xFF10B981),
                secondary: const Color(0xFF10B981),
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              // 修复部分手机按钮文字不显示的问题
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white, // 明确设置前景色（文字颜色）
                  backgroundColor: const Color(0xFF10B981),
                  textStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  textStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF10B981),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  textStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF10B981),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              textTheme: TextTheme(
                bodyLarge: TextStyle(fontSize: baseTextSize),
                bodyMedium: TextStyle(fontSize: baseTextSize - 2),
                bodySmall: TextStyle(fontSize: baseTextSize - 4),
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                elevation: 0,
                titleTextStyle: TextStyle(
                  fontSize: baseTextSize + 2,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              primaryColor: const Color(0xFF10B981),
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF10B981),
                primary: const Color(0xFF10B981),
                secondary: const Color(0xFF10B981),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              // 修复部分手机按钮文字不显示的问题
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF10B981),
                  textStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  textStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF10B981),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  textStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF10B981),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              textTheme: TextTheme(
                bodyLarge: TextStyle(fontSize: baseTextSize),
                bodyMedium: TextStyle(fontSize: baseTextSize - 2),
                bodySmall: TextStyle(fontSize: baseTextSize - 4),
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: Colors.grey[900],
                foregroundColor: Colors.white,
                elevation: 0,
                titleTextStyle: TextStyle(
                  fontSize: baseTextSize + 2,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: _AuthNavigator(settings: settings),
          );
        },
      ),
    );
  }
}

/// 认证导航器 - 监听登录状态变化，清理 SnackBar
class _AuthNavigator extends StatefulWidget {
  final SettingsProvider settings;
  
  const _AuthNavigator({required this.settings});
  
  @override
  State<_AuthNavigator> createState() => _AuthNavigatorState();
}

class _AuthNavigatorState extends State<_AuthNavigator> with WidgetsBindingObserver {
  bool _wasLoggedIn = false;

  @override
  void initState() {
    super.initState();
    // 注册生命周期监听
    WidgetsBinding.instance.addObserver(this);
    // 应用启动时自动验证登录状态（后台保活）
    _verifyLoginState();
  }

  @override
  void dispose() {
    // 取消注册生命周期监听
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 后台保活：验证登录状态
  Future<void> _verifyLoginState() async {
    // 延迟一点执行，确保 AuthProvider 已初始化
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      final auth = context.read<AuthProvider>();
      // 如果有保存的登录信息，尝试恢复登录状态
      if (!auth.isLoggedIn && auth.hasSavedLogin) {
        print('🔄 后台保活：正在恢复登录状态...');
        await auth.restoreLogin();
      }
    }
  }

  /// 监听应用生命周期变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('📱 应用生命周期变化: $state');

    if (state == AppLifecycleState.resumed) {
      // 应用从后台恢复
      print('📱 应用已恢复到前台，执行保活检查...');
      _verifyLoginState();
    } else if (state == AppLifecycleState.paused) {
      // 应用进入后台
      print('📱 应用进入后台');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final isLoggedIn = auth.isLoggedIn;

        // 当从登录变成未登录（退出登录）时，清除 SnackBar
        if (_wasLoggedIn && !isLoggedIn) {
          Future.microtask(() {
            ScaffoldMessenger.of(context).clearSnackBars();
          });
        }
        _wasLoggedIn = isLoggedIn;

        return isLoggedIn ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
