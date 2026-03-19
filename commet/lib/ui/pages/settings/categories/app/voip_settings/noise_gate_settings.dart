import 'dart:async';
import 'dart:math' as math;

import 'package:commet/client/components/voip/webrtc_default_devices.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:commet/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:flutter_webrtc_noise_suppressor/flutter_webrtc_noise_suppressor.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// ---------------------------------------------------------------------------
// dB scale helpers
//
// The meter shows -60 dBFS to 0 dBFS in a [0, 1] display position.
// This range keeps pre-APM silence (typically -40 to -60 dBFS) visible
// as a small bar, while speech (-20 to -6 dBFS) fills the right portion.
// ---------------------------------------------------------------------------

const double _kDbMin = -60.0; // left edge of meter
const double _kDbRange = 60.0; // displayed range in dB

/// Convert linear RMS to meter display position [0..1].
double _toDisplayPos(double linearRms) {
  if (linearRms <= 0) return 0;
  final dBFS = 20.0 * math.log(linearRms) / math.ln10;
  return ((dBFS - _kDbMin) / _kDbRange).clamp(0.0, 1.0);
}

/// Convert a meter display position back to linear RMS.
double _fromDisplayPos(double pos) {
  final dBFS = pos * _kDbRange + _kDbMin;
  return math.pow(10.0, dBFS / 20.0).toDouble();
}

/// Short dBFS label for a display position, e.g. "-12dB".
String _dBLabel(double pos) {
  final dBFS = (pos * _kDbRange + _kDbMin).round();
  return '${dBFS}dB';
}

class NoiseGateSettings extends StatefulWidget {
  const NoiseGateSettings({super.key});

  @override
  State<NoiseGateSettings> createState() => _NoiseGateSettingsState();
}

class _NoiseGateSettingsState extends State<NoiseGateSettings> {
  webrtc.RTCPeerConnection? _monitorPc;
  webrtc.MediaStream? _monitorStream;
  Timer? _levelTimer;

  /// Raw linear RMS from getAudioLevel(), clamped to [0, 1].
  double _currentLevel = 0.0;
  bool _monitoring = false;
  bool _showAdvanced = false;
  StreamSubscription? _prefSub;

  @override
  void initState() {
    super.initState();
    _prefSub = preferences.onSettingChanged.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _prefSub?.cancel();
    unawaited(_stopMonitoring());
    super.dispose();
  }

  Future<void> _startMonitoring() async {
    try {
      // On web the gate works by patching getUserMedia, so initialize before
      // the call so the AudioWorkletNode is created with the stream.
      // On desktop the ADM pipeline starts after getUserMedia (see below).
      if (PlatformUtils.isWeb) {
        await NoiseSuppressor.initialize();
        await NoiseSuppressor.setMode(NoiseProcessingMode.rmsGate);
        await _configureProcessor();
      }

      _monitorStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': false,
        },
        'video': false,
      });

      // getUserMedia alone does not start the WebRTC ADM recording pipeline on
      // desktop — the ADM only starts when a PeerConnection actively uses an
      // audio track. Create a local PC and set a local description to trigger it.
      _monitorPc = await webrtc.createPeerConnection({
        'iceServers': [],
        'sdpSemantics': 'unified-plan',
      });
      for (final track in _monitorStream!.getAudioTracks()) {
        await _monitorPc!.addTrack(track, _monitorStream!);
      }
      final offer = await _monitorPc!.createOffer({});
      await _monitorPc!.setLocalDescription(offer);

      if (!PlatformUtils.isWeb) {
        // Register our processor so it sits in the now-active ADM pipeline.
        await NoiseSuppressor.initialize();
        await NoiseSuppressor.setMode(NoiseProcessingMode.rmsGate);
        await _configureProcessor();
      }

      if (mounted) setState(() => _monitoring = true);

      _levelTimer =
          Timer.periodic(const Duration(milliseconds: 50), (_) async {
        if (!mounted) return;
        final raw = await NoiseSuppressor.getAudioLevel();
        final clamped = raw.clamp(0.0, 1.0);
        // Asymmetric EMA: fast attack so peaks are caught immediately,
        // slow release so the bar decays smoothly rather than jumping.
        const attackAlpha = 0.8;
        const releaseAlpha = 0.15;
        final alpha = clamped > _currentLevel ? attackAlpha : releaseAlpha;
        final smoothed = alpha * clamped + (1 - alpha) * _currentLevel;
        if (mounted) setState(() => _currentLevel = smoothed);
      });
    } catch (_) {}
  }

  Future<void> _stopMonitoring() async {
    _levelTimer?.cancel();
    _levelTimer = null;
    await _monitorPc?.close();
    _monitorPc = null;
    _monitorStream?.getTracks().forEach((t) => t.stop());
    await _monitorStream?.dispose();
    _monitorStream = null;
    if (mounted) {
      setState(() {
        _monitoring = false;
        _currentLevel = 0.0;
      });
    }
  }

  Future<void> _configureProcessor() => NoiseSuppressor.configure(
        threshold: preferences.noiseGateThreshold.value,
        holdMs: preferences.noiseGateHoldMs.value.toInt(),
        residualGain: preferences.noiseGateResidualGain.value,
        attackMs: preferences.noiseGateAttackMs.value,
        releaseMs: preferences.noiseGateReleaseMs.value,
      );

  Future<void> _onSettingChanged() async {
    await WebrtcDefaultDevices.applyNoiseSuppressorSettings();
    if (_monitoring) await _configureProcessor();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        BooleanPreferenceToggle(
          preference: preferences.noiseGateEnabled,
          title: "Enable Noise Gate",
          description:
              "Attenuates audio when the microphone level drops below the threshold. Useful for suppressing background noise between speech.",
          onChanged: (_) => _onSettingChanged(),
        ),
        if (preferences.noiseGateEnabled.value) ...[
          _buildMeter(context, scheme),
          tiamat.Button.secondary(
            text: _showAdvanced
                ? "Hide Advanced Settings"
                : "Show Advanced Settings",
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOut,
            firstCurve: Curves.easeInOut,
            secondCurve: Curves.easeInOut,
            crossFadeState: _showAdvanced
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _buildAdvancedSliders(),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ],
    );
  }

  Widget _buildMeter(BuildContext context, ColorScheme scheme) {
    final threshold = preferences.noiseGateThreshold.value;
    final thresholdPos = _toDisplayPos(threshold);
    final levelPos = _toDisplayPos(_currentLevel);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withAlpha(100),
        border: BoxBorder.all(color: scheme.secondary.withAlpha(20)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              tiamat.Text("Input Level"),
              tiamat.Button.secondary(
                text: _monitoring ? "Stop" : "Test Microphone",
                onTap: _monitoring ? _stopMonitoring : _startMonitoring,
              ),
            ],
          ),
          // Combined level meter + threshold slider.
          Row(
            children: [
              tiamat.Text.labelLow("Threshold: ${_dBLabel(thresholdPos)}"),
              Expanded(
                child: tiamat.LevelMeterSlider(
                  value: thresholdPos,
                  level: levelPos,
                  onChanged: (pos) {
                    final linear = _fromDisplayPos(pos);
                    preferences.noiseGateThreshold
                        .set(double.parse(linear.toStringAsFixed(5)));
                    setState(() {});
                  },
                  onChangeEnd: (_) => _onSettingChanged(),
                ),
              ),
            ],
          ),
          if (_monitoring && preferences.developerMode.value)
            tiamat.Text.labelLow(
                "raw RMS: ${_currentLevel.toStringAsFixed(5)}  "
                "dBFS: ${_currentLevel > 0 ? (20.0 * math.log(_currentLevel) / math.ln10).toStringAsFixed(1) : '-∞'}"),
          if (!PlatformUtils.isWeb && !_monitoring)
            tiamat.Text.labelLow(
                "Press 'Test Microphone' to preview your mic level."),
        ],
      ),
    );
  }

  Widget _buildAdvancedSliders() {
    return Column(
      spacing: 8,
      children: [
        DoublePreferenceSlider(
          preference: preferences.noiseGateHoldMs,
          min: 0,
          max: 2000,
          numDecimals: 0,
          units: " ms",
          title: "Hold Time",
          description:
              "How long to keep the gate open after the level drops below threshold.",
          onChanged: (_) => _onSettingChanged(),
        ),
        DoublePreferenceSlider(
          preference: preferences.noiseGateResidualGain,
          min: 0.0,
          max: 1.0,
          numDecimals: 2,
          title: "Residual Gain",
          description:
              "Audio level when the gate is closed. 0 = silence, 1 = no attenuation.",
          onChanged: (_) => _onSettingChanged(),
        ),
        DoublePreferenceSlider(
          preference: preferences.noiseGateAttackMs,
          min: 1.0,
          max: 100.0,
          numDecimals: 1,
          units: " ms",
          title: "Attack",
          description: "How fast the gate opens when sound is detected.",
          onChanged: (_) => _onSettingChanged(),
        ),
        DoublePreferenceSlider(
          preference: preferences.noiseGateReleaseMs,
          min: 10.0,
          max: 500.0,
          numDecimals: 0,
          units: " ms",
          title: "Release",
          description: "How fast the gate closes after hold time expires.",
          onChanged: (_) => _onSettingChanged(),
        ),
      ],
    );
  }
}
