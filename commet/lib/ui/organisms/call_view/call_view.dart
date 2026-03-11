import 'dart:async';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
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
    return Center(
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
    );
  }

  Widget callConnectedView() {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final session = widget.currentSession;
    final muted = session.isMicrophoneMuted || session.isDeafened;
    final deafened = session.isDeafened;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                const Color(0xFF4A2DB0), // blurple centre
                surfaceColor,            // app surface at edges
              ],
              radius: 0.90,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final ratio = constraints.maxWidth / constraints.maxHeight;
            if (ratio > 1) {
              return Row(children: generateLayout());
            } else {
              return Column(children: generateLayout());
            }
          },
        ),
        if (Layout.mobile)
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 20,
              children: [
                tiamat.CircleButton(
                  radius: 28,
                  icon: muted ? Icons.mic_off : Icons.mic,
                  color: Colors.white,
                  iconColor: muted ? Colors.red : Colors.black87,
                  onPressed: () async {
                    if (deafened) {
                      await session.setDeafened(false);
                    } else {
                      await widget.setMicrophoneMute
                          ?.call(!session.isMicrophoneMuted);
                    }
                    setState(() {});
                  },
                ),
                tiamat.CircleButton(
                  radius: 28,
                  icon: deafened ? Icons.headset_off : Icons.headphones,
                  color: Colors.white,
                  iconColor: deafened ? Colors.red : Colors.black87,
                  onPressed: () async {
                    await session.setDeafened(!deafened);
                    setState(() {});
                  },
                ),
                tiamat.CircleButton(
                  radius: 28,
                  icon: Icons.call_end,
                  color: Colors.red,
                  iconColor: Colors.white,
                  onPressed: () async {
                    await widget.hangUp?.call();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
      ],
    );
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
