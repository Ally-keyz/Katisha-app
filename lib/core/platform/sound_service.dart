import 'dart:developer' as dev;
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class SoundService {
  AudioPlayer? _player;
  bool _androidContextConfigured = false;

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
      // One player for the lifetime of the service. Creating a fresh
      // `AudioPlayer` per tap spun up a new platform player and a new
      // `AudioContext` (a cross-platform channel round-trip) every time.
      final player = _player ??= AudioPlayer();

      if (Platform.isAndroid && !_androidContextConfigured) {
        _androidContextConfigured = true;
        await player.setAudioContext(AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ));
      }

      // Restart cleanly if a previous cue is still playing.
      await player.stop();
      await player.play(AssetSource(path), volume: 0.35);
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
    _androidContextConfigured = false;
  }
}
