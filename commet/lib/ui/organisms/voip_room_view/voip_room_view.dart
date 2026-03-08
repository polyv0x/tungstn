import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/shader/metaballs_background.dart';
import 'package:commet/ui/atoms/shimmer_loading.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/call_view/call.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class VoipRoomView extends StatefulWidget {
  final VoipRoomComponent voip;
  const VoipRoomView(this.voip, {super.key});

  @override
  State<VoipRoomView> createState() => _VoipRoomViewState();
}

class _VoipRoomViewState extends State<VoipRoomView> {
  VoipSession? currentSession;
  String? callServerUrl;
  late List<String> participants;
  bool joining = false;
  StreamSubscription? sub;

  @override
  void initState() {
    currentSession = widget.voip.currentSession;
    participants = widget.voip.getCurrentParticipants();

    sub = widget.voip.onParticipantsChanged.listen((_) {
      updateCallUrl();
      setState(() {
        participants = widget.voip.getCurrentParticipants();
        currentSession ??= widget.voip.currentSession;
      });
    });

    updateCallUrl();
    super.initState();
  }

  void updateCallUrl() {
    widget.voip.getCallServerUrl().then((url) {
      setState(() {
        callServerUrl = url;
      });
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (currentSession?.state == VoipState.ended) {
      joining = false;
      currentSession = null;
    }

    final showCall = currentSession != null;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      child: showCall
          ? CallWidget(currentSession!,
              key: ValueKey(currentSession!.sessionId))
          : KeyedSubtree(key: const ValueKey('unjoined'), child: unjoinedView()),
    );
  }

  Widget unjoinedView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const MetaballsBackground(),
        // Material provides text-rendering context, eliminating debug underlines.
        Material(
          color: Colors.transparent,
          child: Column(
            children: [
              Expanded(
                child: widget.voip.room.isE2EE && BuildConfig.RELEASE
                    ? _e2eeUnsupportedView()
                    : _joinContent(),
              ),
              _encryptionFooter(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _joinContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Room name
          Text(
            widget.voip.room.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Participant info
          if (participants.isNotEmpty) ...[
            _participantAvatarRow(),
            const SizedBox(height: 6),
            Text(
              participants.length == 1
                  ? '1 person in voice'
                  : '${participants.length} people in voice',
              style: TextStyle(
                color: Colors.white.withAlpha(180),
                fontSize: 13,
              ),
            ),
          ] else ...[
            Text(
              'No one is currently in voice',
              style: TextStyle(
                color: Colors.white.withAlpha(150),
                fontSize: 14,
              ),
            ),
          ],

          const SizedBox(height: 28),

          if (widget.voip.room.isE2EE)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: tiamat.Text.error(
                  'End-to-end encrypted calls are still under development, '
                  'and may contain bugs or security issues. Use at your own risk.'),
            ),

          if (widget.voip.canJoinCall)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withAlpha(38),
                shadowColor: Colors.transparent,
                side: BorderSide(color: Colors.white.withAlpha(80)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
              ).copyWith(
                mouseCursor:
                    const WidgetStatePropertyAll(SystemMouseCursors.click),
              ),
              onPressed: joining ? null : joinRoomCall,
              child: joining
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(CommonStrings.promptJoin,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
            )
          else
            Text(
              'You do not have permission to join this call',
              style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _participantAvatarRow() {
    const maxShow = 5;
    final shown = participants.take(maxShow).toList();
    final extra = participants.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final id in shown)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: () {
              final member = widget.voip.room.getMemberOrFallback(id);
              return tiamat.Avatar(
                radius: 22,
                image: member.avatar,
                placeholderColor: member.defaultColor,
                placeholderText: member.displayName,
              );
            }(),
          ),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white.withAlpha(30),
              child: Text('+$extra',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
      ],
    );
  }

  Widget _encryptionFooter() {
    final shimmerColor =
        Theme.of(context).colorScheme.surfaceContainer;
    return Align(
      alignment: AlignmentGeometry.bottomLeft,
      child: tiamat.Tooltip(
        text: widget.voip.room.isE2EE
            ? 'This room is encrypted, your call is secure and private'
            : 'This room is not encrypted, your call may be accessible by the server operator',
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.voip.room.isE2EE ? Icons.lock : Icons.lock_open,
                color:
                    widget.voip.room.isE2EE ? Colors.greenAccent : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 4),
              Shimmer(
                child: ShimmerLoading(
                  isLoading: callServerUrl == null,
                  child: callServerUrl == null
                      ? Container(
                          height: 12,
                          width: 130,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: shimmerColor,
                          ),
                        )
                      : tiamat.Text.labelLow(callServerUrl!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _e2eeUnsupportedView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Sorry, End-to-end encrypted voice rooms are not yet supported.',
          style: TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  joinRoomCall() async {
    final allowed = await clientManager?.callManager.requestExclusiveSession(
        context, widget.voip.room.identifier, widget.voip.client);
    if (allowed != true) return;

    setState(() => joining = true);

    try {
      final session = await widget.voip.joinCall();
      if (session != null) {
        setState(() => currentSession = session);
      }
    } catch (e, s) {
      Log.onError(e, s);
      AdaptiveDialog.showError(context, e, s);
      setState(() => joining = false);
    }
  }
}
