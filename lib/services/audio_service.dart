// lib/services/audio_service.dart
// 音频播放服务 - 编程生成beep音，不依赖系统文件/网络

import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  static AudioService? _instance;
  static AudioService get instance {
    _instance ??= AudioService._();
    return _instance!;
  }

  AudioService._();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _soundEnabled = true;
  bool _isPlaying = false;
  bool _beepReady = false;
  String? _beepPath;

  bool get soundEnabled => _soundEnabled;

  /// 初始化：生成 beep 音频文件
  Future<void> init() async {
    await _generateBeepFile();
  }

  /// 切换声音开关
  void toggleSound() {
    _soundEnabled = !_soundEnabled;
  }

  /// 设置声音开关
  void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
  }

  /// 生成悦耳的提示音音频文件（WAV格式，双音和弦，类似手机通知音）
  Future<void> _generateBeepFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _beepPath = '${dir.path}/beep.wav';

      // 检查是否已存在
      if (await File(_beepPath!).exists()) {
        _beepReady = true;
        print('📢 AudioService: 提示音文件已存在，直接使用');
        return;
      }

      // 生成双音和弦提示音（类似手机通知音）
      const sampleRate = 22050;
      const duration = 0.45; // 秒
      final numSamples = (sampleRate * duration).toInt();

      final samples = Uint8List(44 + numSamples * 2);

      // WAV文件头
      _writeString(samples, 0, 'RIFF');
      _writeInt32(samples, 4, 36 + numSamples * 2); // 文件大小-8
      _writeString(samples, 8, 'WAVE');
      _writeString(samples, 12, 'fmt ');
      _writeInt32(samples, 16, 16); // fmt块大小
      _writeInt16(samples, 20, 1); // PCM格式
      _writeInt16(samples, 22, 1); // 单声道
      _writeInt32(samples, 24, sampleRate); // 采样率
      _writeInt32(samples, 28, sampleRate * 2); // 字节率
      _writeInt16(samples, 32, 2); // 块对齐
      _writeInt16(samples, 34, 16); // 位深
      _writeString(samples, 36, 'data');
      _writeInt32(samples, 40, numSamples * 2); // 数据大小

      // 生成双音和弦样本
      // 第一音: 784Hz (G5) - 持续0-200ms
      // 第二音: 1047Hz (C6) - 持续100-450ms（与第一音重叠）
      // 叠加后听起来像"叮-咚"的提示音
      for (int i = 0; i < numSamples; i++) {
        final t = i / sampleRate;
        
        // 淡入（前5%）+ 淡出（后15%）
        double envelope = 1.0;
        final fadeInEnd = numSamples * 0.05;
        final fadeOutStart = numSamples * 0.85;
        if (i < fadeInEnd) {
          envelope = i / fadeInEnd;
        } else if (i > fadeOutStart) {
          envelope = (numSamples - i) / (numSamples - fadeOutStart);
        }

        // 第一音：784Hz，持续前200ms
        final firstToneEnd = (0.2 * sampleRate).toInt();
        double firstTone = 0;
        if (i < firstToneEnd) {
          // 第一音也有自己的淡出
          final firstEnv = 1.0 - (i / firstToneEnd) * 0.3;
          firstTone = firstEnv * 12000 * sin(2 * pi * 784.0 * t);
        }

        // 第二音：1047Hz，从100ms开始到结束
        final secondToneStart = (0.1 * sampleRate).toInt();
        double secondTone = 0;
        if (i >= secondToneStart) {
          // 第二音渐入渐出
          final secondPos = (i - secondToneStart) / (numSamples - secondToneStart);
          double secondEnv = 1.0;
          if (secondPos < 0.2) {
            secondEnv = secondPos / 0.2;
          } else if (secondPos > 0.8) {
            secondEnv = (1.0 - secondPos) / 0.2;
          }
          secondTone = secondEnv * 14000 * sin(2 * pi * 1047.0 * t);
        }

        final sample = (envelope * (firstTone + secondTone) * 0.6).round();
        _writeInt16(samples, 44 + i * 2, sample.clamp(-32768, 32767));
      }

      await File(_beepPath!).writeAsBytes(samples);
      _beepReady = true;
      print('📢 AudioService: 提示音生成成功 (${samples.length} bytes) - 双音和弦通知音');
    } catch (e) {
      print('❌ AudioService: 提示音生成失败: $e');
    }
  }

  void _writeString(Uint8List data, int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      data[offset + i] = s.codeUnitAt(i);
    }
  }

  void _writeInt32(Uint8List data, int offset, int value) {
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
    data[offset + 2] = (value >> 16) & 0xFF;
    data[offset + 3] = (value >> 24) & 0xFF;
  }

  void _writeInt16(Uint8List data, int offset, int value) {
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
  }

  /// 播放提示音（通用入口）
  Future<void> playNotificationSound() async {
    await playMessageSound();
  }

  /// 播放简短提示音（普通新消息）- 每条消息都会响
  Future<void> playMessageSound() async {
    if (!_soundEnabled) return;

    try {
      await _audioPlayer.stop();
      await _playBeep();
    } catch (e) {
      print('⚠️ 提示音播放失败: $e');
    }
  }

  /// 播放警告音（催办/隐患通知，频率更高）
  Future<void> playAlertSound() async {
    if (!_soundEnabled) return;

    // 不用_isPlaying互斥，直接停止当前播放后重新播（避免漏播）
    _isPlaying = true;
    try {
      await _audioPlayer.stop();
      // 播放两声
      await _playBeep();
      await Future.delayed(const Duration(milliseconds: 300));
      if (_soundEnabled) {
        await _playBeep();
      }
    } catch (e) {
      print('⚠️ 警告音播放失败: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () {
        _isPlaying = false;
      });
    }
  }

  /// 播放 beep 音频
  Future<void> _playBeep() async {
    // 优先用本地文件
    if (_beepReady && _beepPath != null) {
      try {
        await _audioPlayer.play(DeviceFileSource(_beepPath!));
        return;
      } catch (e) {
        print('⚠️ 本地beep播放失败: $e');
        // 尝试fallback
        await _playFallbackSound();
        return;
      }
    }

    // 文件未就绪时先生成
    if (!_beepReady) {
      await _generateBeepFile();
      if (_beepReady && _beepPath != null) {
        try {
          await _audioPlayer.play(DeviceFileSource(_beepPath!));
          return;
        } catch (e) {
          print('⚠️ beep重试播放失败: $e');
          await _playFallbackSound();
          return;
        }
      }
    }
  }
  
  /// Fallback: 使用系统通知音效
  Future<void> _playFallbackSound() async {
    try {
      // 尝试使用系统默认通知音
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      // Android系统通知音效URI
      await _audioPlayer.play(UrlSource('file:///system/media/audio/notifications/Antimony.ogg'));
    } catch (e) {
      print('⚠️ Fallback声音播放失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    _audioPlayer.dispose();
  }
}
