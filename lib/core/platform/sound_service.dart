import 'dart:developer' as dev;
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class SoundService {
  AudioPlayer? _player;

  /// Plays the click sound. Intended ONLY for the welcome-screen continue
  /// button, which is the single place in the app that keeps an audible cue.
  Future<void> playClick() async {
    dev.log('[SoundService] Playing click sound');
    await _playAsset('sounds/click.mp3');
  }

  /// Haptic vibration only (sound replaced everywhere else by vibration).
  Future<void> vibrate() async {
    dev.log('[SoundService] Vibration');
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Success feedback: vibration only (no sound).
  Future<void> playSuccess() async {
    dev.log('[SoundService] Success vibration');
    try {
      await HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Alert feedback: vibration only (no sound).
  Future<void> playAlert() async {
    dev.log('[SoundService] Alert vibration');
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }

  Future<void> _playAsset(String path) async {
    try {
      _player?.dispose();
      _player = AudioPlayer();

      if (Platform.isAndroid) {
        await _player!.setAudioContext(AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ));
      }

      await _player!.play(AssetSource(path), volume: 1.0);
      dev.log('[SoundService] Audio started playing');
    } catch (e) {
      dev.log('[SoundService] Audio failed: $e');
      try {
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 150));
        await HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
