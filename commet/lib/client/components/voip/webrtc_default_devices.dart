import 'package:collection/collection.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:flutter_webrtc_noise_suppressor/flutter_webrtc_noise_suppressor.dart';

class WebrtcDefaultDevices {
  static Future<webrtc.MediaStream?> getDefaultMicrophone() async {
    if (PlatformUtils.isAndroid) return null;

    var devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
        .where((i) => i.kind == "audioinput");

    Map<String, dynamic> constraints = {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': false,
    };

    if (preferences.voipDefaultAudioInput.value != null) {
      var pickedDevice = devices.firstWhereOrNull(
          (i) => i.label == preferences.voipDefaultAudioInput.value);

      if (pickedDevice != null) {
        print(
            "Picked device id: ${pickedDevice.deviceId} (${pickedDevice.label})");
        constraints["deviceId"] = {'exact': pickedDevice.deviceId};

        webrtc.Helper.selectAudioInput(pickedDevice.deviceId);
      } else {
        print("Preferred audio device not found!");
      }
    } else {
      print("No default device set picking first");
    }

    // On web the gate works by patching getUserMedia, so initialize must run
    // BEFORE the call so the hook is in place when the stream is returned.
    // On native the processor hooks into the ADM which only starts after getUserMedia.
    if (PlatformUtils.isWeb) await _applyNoiseSuppressor();

    final stream = await webrtc.navigator.mediaDevices
        .getUserMedia({"audio": constraints});

    if (!PlatformUtils.isWeb) await _applyNoiseSuppressor();

    return stream;
  }

  static Future<void> _applyNoiseSuppressor() async {
    if (PlatformUtils.isAndroid) return;

    if (preferences.noiseGateEnabled.value) {
      await NoiseSuppressor.initialize();
      await NoiseSuppressor.setMode(NoiseProcessingMode.rmsGate);
      await NoiseSuppressor.configure(
        threshold: preferences.noiseGateThreshold.value,
        holdMs: preferences.noiseGateHoldMs.value.toInt(),
        residualGain: preferences.noiseGateResidualGain.value,
        attackMs: preferences.noiseGateAttackMs.value,
        releaseMs: preferences.noiseGateReleaseMs.value,
      );
    } else {
      try {
        await NoiseSuppressor.dispose();
      } catch (_) {}
    }
  }

  /// Re-apply noise suppressor settings without restarting the mic stream.
  /// Call this when noise gate preferences change.
  static Future<void> applyNoiseSuppressorSettings() =>
      _applyNoiseSuppressor();

  static Future<String?> getDefaultMicrophoneId() async {
    if (PlatformUtils.isAndroid || PlatformUtils.isWeb) return null;

    var devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
        .where((i) => i.kind == "audioinput");

    if (preferences.voipDefaultAudioInput.value == null) return null;

    return devices
        .firstWhereOrNull(
            (i) => i.label == preferences.voipDefaultAudioInput.value)
        ?.deviceId;
  }

  static Future<void> selectInputDevice() async {
    var devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
        .where((i) => i.kind == "audioinput");

    if (preferences.voipDefaultAudioInput.value != null) {
      var pickedDevice = devices.firstWhereOrNull(
          (i) => i.label == preferences.voipDefaultAudioInput.value);

      if (pickedDevice != null) {
        print(
            "Picked device id: ${pickedDevice.deviceId} (${pickedDevice.label})");

        webrtc.Helper.selectAudioInput(pickedDevice.deviceId);
      } else {
        print("Preferred audio device not found!");
      }
    }
  }

  static Future<void> selectOutputDevice() async {
    if (preferences.voipDefaultAudioOutput.value == null) return;

    var devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
        .where((i) => i.kind == "audiooutput");

    var device = devices.firstWhereOrNull(
        (i) => i.label == preferences.voipDefaultAudioOutput.value);

    if (device != null) {
      Log.i("Setting webrtc output to: ${device.label}  (${device.deviceId})");
      webrtc.Helper.selectAudioOutput(device.deviceId);
    }
  }
}
