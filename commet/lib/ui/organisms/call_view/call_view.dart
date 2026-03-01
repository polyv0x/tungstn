import 'dart:async';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/preferences.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/layout/bento.dart';
import 'package:commet/ui/organisms/call_view/voip_fullscreen_stream_view.dart';
import 'package:commet/ui/organisms/call_view/voip_stream_view.dart';
import 'package:commet/utils/animation/ring_shaker.dart';
import 'package:commet/utils/animation/ripple.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CallView extends StatefulWidget {
  const CallView(
    this.currentSession, {
    this.setMicrophoneMute,
    this.pickScreenshareSource,
    this.stopScreenshare,
    this.pickCamera,
    this.disableCamera,
    this.hangUp,
    this.declineCall,
    this.acceptCall,
    super.key,
  });
  final VoipSession currentSession;

  static const Duration volumeAnimationDuration = Duration(milliseconds: 500);

  final Future<void> Function(bool)? setMicrophoneMute;
  final Future<void> Function()? pickScreenshareSource;
  final Future<void> Function()? stopScreenshare;
  final Future<void> Function()? pickCamera;
  final Future<void> Function()? disableCamera;
  final Future<void> Function()? hangUp;
  final Future<void> Function()? declineCall;
  final Future<void> Function()? acceptCall;

  @override
  State<CallView> createState() => _CallViewState();
}

class _CallViewState extends State<CallView> {
  Timer? statTimer;
  StreamSubscription? sub;
  bool isMouseHovering = false;
  bool _showStreamSettings = false;
  VoipStream? mainStream;
  late Room room;

  @override
  void initState() {
    super.initState();
    sub = widget.currentSession.onStateChanged.listen((event) {
      setState(() {});
    });

    room = widget.currentSession.client.getRoom(widget.currentSession.roomId)!;
    statTimer = Timer.periodic(const Duration(milliseconds: 200), timer);
  }

  @override
  void dispose() {
    statTimer?.cancel();
    sub?.cancel();
    super.dispose();
  }

  void timer(Timer timer) async {
    await widget.currentSession.updateStats();
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Tile.lowest(
      child: switch (widget.currentSession.state) {
        VoipState.connected => callConnectedView(),
        VoipState.outgoing => callOutgoingView(),
        VoipState.connecting => callOutgoingView(),
        VoipState.ended => callEndedView(),
        VoipState.incoming => callIncomingView(),
        _ => const Placeholder()
      },
    );
  }

  Widget callOutgoingView() {
    return callButtons(
      canHangUp: true,
      child: Center(
        child: RippleAnimation(
          ripplesCount: 3,
          scale: 1,
          color: Theme.of(context).colorScheme.primary,
          repeat: true,
          child: Avatar.large(
              image: room.avatar,
              placeholderColor: room.defaultColor,
              placeholderText: room.displayName),
        ),
      ),
    );
  }

  Widget callButtons(
      {bool canMute = false,
      bool canScreenshare = false,
      bool canHangUp = false,
      bool canToggleCamera = false,
      required Widget child}) {
    final buttonRadius = Layout.mobile ? 24.0 : 18.0;
    return MouseRegion(
      onEnter: (event) {
        setState(() {
          isMouseHovering = true;
        });
      },
      onExit: (event) {
        setState(() {
          isMouseHovering = false;
        });
      },
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          child,
          AnimatedOpacity(
            opacity: Layout.mobile || isMouseHovering ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _showStreamSettings
                      ? _streamSettingsPanel()
                      : const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      if (canScreenshare)
                        tiamat.CircleButton(
                            radius: buttonRadius,
                            icon: Icons.screen_share_outlined,
                            onPressed: widget.pickScreenshareSource),
                      if (widget.currentSession.isSharingScreen && canScreenshare)
                        tiamat.CircleButton(
                          radius: buttonRadius,
                          icon: Icons.stop_screen_share,
                          onPressed: widget.stopScreenshare,
                        ),
                      if (canMute)
                        tiamat.CircleButton(
                          radius: buttonRadius,
                          icon: widget.currentSession.isMicrophoneMuted
                              ? Icons.mic_off
                              : Icons.mic,
                          onPressed: () async {
                            await widget.setMicrophoneMute
                                ?.call(!widget.currentSession.isMicrophoneMuted);
                            setState(() {});
                          },
                        ),
                      if (canToggleCamera)
                        tiamat.CircleButton(
                          radius: buttonRadius,
                          icon: widget.currentSession.isCameraEnabled
                              ? Icons.no_photography
                              : Icons.camera_alt_outlined,
                          onPressed: widget.currentSession.isCameraEnabled
                              ? widget.disableCamera
                              : widget.pickCamera,
                        ),
                      if (canScreenshare)
                        tiamat.CircleButton(
                          radius: buttonRadius,
                          icon: _showStreamSettings
                              ? Icons.settings
                              : Icons.settings_outlined,
                          onPressed: () => setState(
                              () => _showStreamSettings = !_showStreamSettings),
                        ),
                      if (canHangUp)
                        tiamat.CircleButton(
                          color: Theme.of(context).colorScheme.errorContainer,
                          radius: buttonRadius,
                          icon: Icons.call_end,
                          onPressed: () async {
                            await widget.hangUp?.call();
                            setState(() {});
                          },
                        )
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget callConnectedView() {
    return callButtons(
        canMute: true,
        canHangUp: true,
        canScreenshare: true,
        canToggleCamera: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            var ratio = constraints.maxWidth / constraints.maxHeight;

            if (ratio > 1) {
              return Row(children: generateLayout());
            } else {
              return Column(children: generateLayout());
            }
          },
        ));
  }

  List<Widget> generateLayout() {
    return [
      if (mainStream != null)
        Flexible(
          flex: 100,
          fit: FlexFit.tight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    mainStream = null;
                  });
                },
                child: VoipStreamView(
                  mainStream!,
                  widget.currentSession,
                  borderColor: Colors.white,
                  onFullscreen: () {
                    Lightbox.show(context,
                        aspectRatio: mainStream!.aspectRatio,
                        customWidget: VoipFullscreenStreamView(
                          session: widget.currentSession,
                          stream: mainStream!,
                        ));
                  },
                  fit: BoxFit.contain,
                  key: ValueKey(
                      "callView_mainStreamView_${mainStream!.streamId}"),
                ),
              ),
            ),
          ),
        ),
      Flexible(
        fit: FlexFit.tight,
        flex: 75,
        child: Center(
          child: BentoLayout(widget.currentSession.streams
              .where((element) => element != mainStream)
              .map((e) => GestureDetector(
                  onTap: () {
                    setState(() {
                      mainStream = e;
                    });
                  },
                  child: VoipStreamView(
                    key: ValueKey("callView__${e.streamId}"),
                    e,
                    fit: e.type == VoipStreamType.screenshare
                        ? BoxFit.contain
                        : BoxFit.cover,
                    widget.currentSession,
                    onFullscreen: () {
                      Lightbox.show(context,
                          aspectRatio: e.aspectRatio,
                          customWidget: VoipFullscreenStreamView(
                            session: widget.currentSession,
                            stream: e,
                          ));
                    },
                  )))
              .toList()),
        ),
      )
    ];
  }

  Widget _streamSettingsPanel() {
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer.withAlpha(220),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sliderRow(
              label: "Resolution",
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
              label: "FPS",
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
              label: "Bitrate",
              valueLabel:
                  bitrate == 0 ? "Auto" : "${bitrate.toStringAsFixed(0)} Mbps",
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
      ),
    );
  }

  Widget _sliderRow({
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
          width: 72,
          child: tiamat.Text.labelLow(label),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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
          width: 60,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  Widget callEndedView() {
    return const Center(child: tiamat.Text.label("Call ended"));
  }

  Widget callIncomingView() {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Center(
          child: RingShakerAnimation(
            child: Avatar.large(
                image: room.avatar,
                placeholderColor: room.defaultColor,
                placeholderText: room.displayName),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 5,
            children: [
              tiamat.CircleButton(
                icon: Icons.call,
                onPressed: () async {
                  await widget.acceptCall?.call();
                  setState(() {});
                },
              ),
              tiamat.CircleButton(
                icon: Icons.call_end,
                onPressed: () async {
                  await widget.declineCall?.call();
                  setState(() {});
                },
              )
            ],
          ),
        ),
      ],
    );
  }
}
