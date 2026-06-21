// lib/utils/phone_service.dart
// 拨打电话服务

import 'package:url_launcher/url_launcher.dart';

class PhoneService {
  /// 一键拨打电话
  static Future<bool> makePhoneCall(String phoneNumber) async {
    try {
      // 清理电话号码（移除空格和特殊字符）
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      
      // 确保是有效的电话号码
      if (cleanNumber.isEmpty || cleanNumber.length < 7) {
        print('❌ 无效的电话号码: $phoneNumber');
        return false;
      }
      
      // 构建tel:链接
      final uri = Uri(scheme: 'tel', path: cleanNumber);
      
      print('📞 正在拨打电话: $cleanNumber');
      
      // 检查是否可以打开
      if (await canLaunchUrl(uri)) {
        // 打开电话拨号界面（不会自动拨打，需要用户确认）
        await launchUrl(uri);
        return true;
      } else {
        print('❌ 无法拨打电话: $phoneNumber');
        return false;
      }
    } catch (e) {
      print('❌ 拨打电话异常: $e');
      return false;
    }
  }
  
  /// 发送短信
  static Future<bool> sendSMS(String phoneNumber, {String? body}) async {
    try {
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      
      Uri uri;
      if (body != null && body.isNotEmpty) {
        uri = Uri(scheme: 'sms', path: cleanNumber, queryParameters: {'body': body});
      } else {
        uri = Uri(scheme: 'sms', path: cleanNumber);
      }
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      }
      return false;
    } catch (e) {
      print('❌ 发送短信异常: $e');
      return false;
    }
  }
  
  /// 打开APP（用于视频通话）
  static Future<bool> launchApp(String scheme, String appName) async {
    try {
      print('📱 正在打开 $appName...');
      final uri = Uri.parse(scheme);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        print('❌ 无法打开 $appName');
        return false;
      }
    } catch (e) {
      print('❌ 打开APP异常: $e');
      return false;
    }
  }
  
  /// 格式化电话号码显示
  static String formatPhoneNumber(String phone) {
    if (phone.length == 11) {
      // 手机号格式: 138 0000 0000
      return '${phone.substring(0, 3)} ${phone.substring(3, 7)} ${phone.substring(7)}';
    } else if (phone.length == 7) {
      // 固话格式: 0531 0000000
      return phone;
    }
    return phone;
  }
}
