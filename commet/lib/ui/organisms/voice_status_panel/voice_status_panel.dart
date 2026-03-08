import 'dart:async';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/preferences.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class VoiceStatusPanel extends StatefulWidget {
  const VoiceStatusPanel(this.callManager, {super.key});
  final CallManager callManager;

  @override
  State<VoiceStatusPanel> createState() => _VoiceStatusPanelState();
}

class _VoiceStatusPanelState extends State<VoiceStatusPanel>
    with TickerProviderStateMixin {
  late List<StreamSubscription> _subs;
  bool _showStreamSettings = false;
  StreamSubscription? _sessionSub;
  StreamSubscription? _audioSub;
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  late AnimationController _settingsController;
  late Animation<double> _settingsAnimation;

  // Kept alive during the collapse animation so content doesn't vanish mid-slide.
  VoipSession? _displayedSession;

  VoipSession? get _session =>
      widget.callManager.currentSessions.firstOrNull;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    );
    _slideController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _displayedSession = null);
      }
    });

    _settingsController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _settingsAnimation = CurvedAnimation(
      parent: _settingsController,
      curve: Curves.easeInOut,
    );

    _subs = [
      widget.callManager.currentSessions.onListUpdated.listen((_) {
        _rebindSession();
        setState(() {});
      }),
    ];
    _rebindSession();

    // Already in a session on first build — skip the entrance animation.
    if (_displayedSession != null) _slideController.value = 1.0;
  }

  void _rebindSession() {
    _sessionSub?.cancel();
    _audioSub?.cancel();

    final session = _session;
    if (session == null || session.state == VoipState.ended) {
      _slideController.reverse();
      return;
    }

    _displayedSession = session;
    _slideController.forward();

    _sessionSub = session.onStateChanged.listen((_) {
      if (session.state == VoipState.ended) {
        _audioSub?.cancel();
        _slideController.reverse();
        _settingsController.reverse();
        _showStreamSettings = false;
      }
      // Collapse settings if streaming stopped while settings were open.
      if (_showStreamSettings &&
          !session.isSharingScreen &&
          !session.isCameraEnabled) {
        _settingsController.reverse();
        _showStreamSettings = false;
      }
      setState(() {});
    });
    _audioSub = session.onUpdateVolumeVisualizers.listen((_) async {
      await session.updateStats();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (var sub in _subs) {
      sub.cancel();
    }
    _sessionSub?.cancel();
    _audioSub?.cancel();
    _slideController.dispose();
    _settingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _displayedSession;

    return SizeTransition(
      sizeFactor: _slideAnimation,
      axisAlignment: 1.0,
      child: ClipRect(
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(_slideAnimation),
          child: FadeTransition(
            opacity: _slideAnimation,
            child: session == null
                ? const SizedBox.shrink()
                : _buildContent(context, session),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, VoipSession session) {
    final room = session.client.getRoom(session.roomId);
    final spaceName = clientManager?.spaces
        .where((s) => s.containsRoom(session.roomId))
        .firstOrNull
        ?.displayName;

    final roomLabel = spaceName != null
        ? '${room?.displayName ?? session.roomName} / $spaceName'
        : (room?.displayName ?? session.roomName);

    final connected = session.state == VoipState.connected;

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusHeader(context, session, roomLabel, connected),
          if (connected) _actionButtons(context, session),
          if (connected && (session.isSharingScreen || session.isCameraEnabled))
            SizeTransition(
              sizeFactor: _settingsAnimation,
              axisAlignment: -1.0,
              child: ClipRect(
                child: FadeTransition(
                  opacity: _settingsAnimation,
                  child: _streamSettingsPanel(context),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Divider(height: 1),
          ),
        ],
      ),
    );
  }

  /// Returns a quality score in [0.0, 1.0], or null if no stats yet.
  double? _qualityScore(VoipSession session) {
    final latency = session.latencyMs;
    final loss = session.packetLossRate;
    if (latency == null && loss == null) return null;
    double score = 1.0;
    if (latency != null) {
      if (latency > 400) score = score.clamp(0.0, 0.15);
      else if (latency > 200) score = score.clamp(0.0, 0.40);
      else if (latency > 100) score = score.clamp(0.0, 0.65);
    }
    if (loss != null) {
      if (loss > 0.10) score = score.clamp(0.0, 0.15);
      else if (loss > 0.05) score = score.clamp(0.0, 0.40);
      else if (loss > 0.01) score = score.clamp(0.0, 0.65);
    }
    return score;
  }

  Widget _signalIcon(double? quality, Color borderColor) {
    final Color iconColor;
    final IconData iconData;

    if (quality == null) {
      iconColor = Colors.grey;
      iconData = Icons.signal_cellular_0_bar;
    } else if (quality >= 0.65) {
      iconColor = Colors.lightGreen;
      iconData = Icons.signal_cellular_alt;
    } else if (quality >= 0.35) {
      iconColor = Colors.orange;
      iconData = Icons.signal_cellular_alt_2_bar;
    } else {
      iconColor = Colors.red;
      iconData = Icons.signal_cellular_alt_1_bar;
    }

    return SizedBox.square(
      dimension: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: borderColor.withAlpha(30),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: borderColor.withAlpha(80), width: 1),
        ),
        child: Center(child: Icon(iconData, color: iconColor, size: 16)),
      ),
    );
  }

  Widget _statusHeader(BuildContext context, VoipSession session,
      String roomLabel, bool connected) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = connected ? Colors.lightGreen : scheme.primary;
    final statusText = switch (session.state) {
      VoipState.connected => 'Voice Connected',
      VoipState.connecting => 'Connecting...',
      VoipState.outgoing => 'Calling...',
      _ => session.state.name,
    };

    final latency = session.latencyMs;
    final loss = session.packetLossRate;
    final latencyLabel = latency != null ? '${latency.round()} ms' : 'Unknown';
    final lossLabel = loss != null
        ? '${(loss * 100).toStringAsFixed(1)}%'
        : 'Unknown';
    final quality = connected ? _qualityScore(session) : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Signal quality icon spanning both rows
            JustTheTooltip(
              content: Padding(
                padding: const EdgeInsets.all(8),
                child: tiamat.Text('Latency: $latencyLabel\nPacket loss: $lossLabel'),
              ),
              preferredDirection: AxisDirection.up,
              offset: 5,
              tailLength: 5,
              tailBaseWidth: 5,
              backgroundColor: scheme.surfaceContainerLowest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
                child: Center(
                  child: _signalIcon(quality, statusColor),
                ),
              ),
            ),
            // Middle: two lines of text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    statusText,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: statusColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    roomLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withAlpha(180)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Disconnect button spanning both rows
            Center(
              child: SizedBox.square(
                dimension: 32,
                child: tiamat.IconButton(
                  icon: Icons.call_end,
                  iconColor: scheme.error,
                  size: 16,
                  onPressed: () => session.hangUpCall(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButtons(BuildContext context, VoipSession session) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: 0,
        children: [
          if (session.supportsScreenshare) ...[
            if (!session.isSharingScreen)
              _actionButton(
                icon: Icons.screen_share_outlined,
                onPressed: () async {
                  final source = await session.pickScreenCapture(context);
                  if (source != null) await session.setScreenShare(source);
                },
              ),
            if (session.isSharingScreen)
              _actionButton(
                icon: Icons.stop_screen_share,
                onPressed: () => session.stopScreenshare(),
              ),
          ],
          if (session.isCameraEnabled)
            _actionButton(
              icon: Icons.no_photography,
              onPressed: () => session.stopCamera(),
            )
          else
            _actionButton(
              icon: Icons.camera_alt_outlined,
              onPressed: () => session.setCamera(null),
            ),
          if (session.isSharingScreen || session.isCameraEnabled)
            _actionButton(
              icon: _showStreamSettings
                  ? Icons.settings
                  : Icons.settings_outlined,
              onPressed: () {
                setState(() => _showStreamSettings = !_showStreamSettings);
                if (_showStreamSettings) {
                  _settingsController.forward();
                } else {
                  _settingsController.reverse();
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _actionButton({required IconData icon, required VoidCallback onPressed}) {
    return SizedBox.square(
      dimension: 32,
      child: tiamat.IconButton(
        icon: icon,
        size: 16,
        onPressed: onPressed,
      ),
    );
  }

  Widget _streamSettingsPanel(BuildContext context) {
    final resOptions = Preferences.streamResolutionOptions;
    final fpsOptions = Preferences.streamFramerateOptions;
    final resIdx = resOptions
        .indexOf(preferences.streamResolution.value)
        .clamp(0, resOptions.length - 1)
        .toDouble();
    final fpsIdx = fpsOptions
        .indexOf(preferences.streamFramerate.value)
        .clamp(0, fpsOptions.length - 1)
        .toDouble();
    final bitrate = preferences.streamBitrate.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sliderRow(
            context,
            label: 'Res',
            valueLabel: resOptions[resIdx.round()],
            value: resIdx,
            min: 0,
            max: (resOptions.length - 1).toDouble(),
            divisions: resOptions.length - 1,
            onChanged: (v) {
              preferences.streamResolution.set(resOptions[v.round()]);
              setState(() {});
            },
          ),
          _sliderRow(
            context,
            label: 'FPS',
            valueLabel: fpsOptions[fpsIdx.round()],
            value: fpsIdx,
            min: 0,
            max: (fpsOptions.length - 1).toDouble(),
            divisions: fpsOptions.length - 1,
            onChanged: (v) {
              preferences.streamFramerate.set(fpsOptions[v.round()]);
              setState(() {});
            },
          ),
          _sliderRow(
            context,
            label: 'Mbps',
            valueLabel:
                bitrate == 0 ? 'Auto' : bitrate.toStringAsFixed(0),
            value: bitrate,
            min: Preferences.streamBitrateMin,
            max: Preferences.streamBitrateMax,
            divisions: Preferences.streamBitrateMax.toInt(),
            onChanged: (v) {
              preferences.streamBitrate.set(v.roundToDouble());
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _sliderRow(
    BuildContext context, {
    required String label,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: tiamat.Text.labelLow(label),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
