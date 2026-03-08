import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/voip/voip_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';

class CallManager {
  ClientManager clientManager;
  final StreamController<VoipSession> _onSessionStarted =
      StreamController.broadcast();

  String notificationContentUserIsCalling(String user) => Intl.message(
      "$user is calling!",
      desc:
          "Notification body content for when receiving an incoming call from another user",
      args: [user],
      name: "notificationContentUserIsCalling");

  String notificationTitleIncomingCall(String roomName) =>
      Intl.message("Incoming Call! ($roomName)",
          desc: "Notification title for when a call is being received",
          args: [roomName],
          name: "notificationTitleIncomingCall");

  Stream<VoipSession> get onSessionStarted => _onSessionStarted.stream;

  NotifyingList<VoipSession> currentSessions =
      NotifyingList.empty(growable: true);

  CallManager(this.clientManager) {
    clientManager.onClientAdded.stream.listen(_onClientAdded);
    clientManager.onClientRemoved.stream.listen(_onClientRemoved);
  }

  Player? player;
  Player? muteSoundPlayer;
  Player? unmuteSoundPlayer;

  void _onClientAdded(int index) {
    var client = clientManager.clients[index];

    var voip = client.getComponent<VoipComponent>();
    if (voip == null) {
      return;
    }

    voip.onSessionStarted.listen(onClientSessionStarted);
    voip.onSessionEnded.listen(onSessionEnded);
  }

  void _onClientRemoved(StalePeerInfo event) {}

  // Guards against concurrent join attempts racing through requestExclusiveSession
  // before either session appears in currentSessions.
  bool _joiningInProgress = false;

  void onClientSessionStarted(VoipSession event) {
    _joiningInProgress = false;
    var room = event.client.getRoom(event.roomId);
    currentSessions.add(event);

    if (event.state == VoipState.incoming) {
      startRingtone();

      var member = room?.getMemberOrFallback(event.remoteUserId!);

      NotificationManager.notify(CallNotificationContent(
          title: notificationTitleIncomingCall(event.roomName),
          content: notificationContentUserIsCalling(
              event.remoteUserName ?? event.remoteUserId!),
          roomId: event.roomId,
          roomName: event.roomName,
          senderName: member?.displayName ?? event.remoteUserId!,
          roomImage: room?.avatar,
          callId: event.sessionId,
          senderId: event.remoteUserId!,
          senderImage: member?.avatar,
          senderImageId: member?.avatarId,
          roomImageId: room?.avatarId,
          clientId: event.client.identifier,
          isDirectMessage: event.client
                  .getComponent<DirectMessagesComponent>()
                  ?.isRoomDirectMessage(room!) ==
              true));
    }

    if (event.state == VoipState.outgoing) {
      startOutgoingTone();
    }

    if (event.state == VoipState.connected) {
      joinCallSound();
    }

    event.onConnectionStateChanged.listen((_) => onCallStateChanged(event));
  }

  void onSessionEnded(VoipSession event) {
    currentSessions
        .removeWhere((element) => element.sessionId == event.sessionId);

    if (currentSessions.isEmpty) _joiningInProgress = false;

    if (currentSessions.where((e) => e.state == VoipState.incoming).isEmpty) {
      stopRingtone();
    }

    endCallSound();
  }

  /// Ensures at most one voice session is active. Call this before joining any
  /// voice channel or starting a call. Returns true if the caller may proceed,
  /// false if the user cancelled.
  Future<bool> requestExclusiveSession(
      BuildContext context, String targetRoomId, Client targetClient) async {
    final active = currentSessions
        .where((s) => s.state != VoipState.ended)
        .toList();

    if (active.isEmpty) {
      if (_joiningInProgress) return false;
      _joiningInProgress = true;
      return true;
    }

    final existing = active.first;

    if (_sameVoiceContext(existing, targetRoomId, targetClient)) {
      await existing.hangUpCall();
      return true;
    }

    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: "Switch voice channel",
      prompt:
          "You are currently connected to **${existing.roomName}**. Disconnect and join the new call?",
      confirmationText: "Switch",
      cancelText: "Cancel",
    );

    if (confirmed == true) {
      await existing.hangUpCall();
      return true;
    }

    return false;
  }

  bool _sameVoiceContext(
      VoipSession existing, String targetRoomId, Client targetClient) {
    final existingSpaces = existing.client.spaces
        .where((s) => s.containsRoom(existing.roomId))
        .map((s) => s.identifier)
        .toSet();
    final targetSpaces = targetClient.spaces
        .where((s) => s.containsRoom(targetRoomId))
        .map((s) => s.identifier)
        .toSet();
    // Both are DMs (no parent space) → same context, switch silently
    if (existingSpaces.isEmpty && targetSpaces.isEmpty) return true;
    // Share at least one space → same context
    return existingSpaces.intersection(targetSpaces).isNotEmpty;
  }

  VoipSession? getCallInRoom(Client client, String roomId) {
    return currentSessions
        .where(
            (element) => element.client == client && element.roomId == roomId)
        .firstOrNull;
  }

  void startRingtone() {
    // Let push notifications do the ringtone
    if (PlatformUtils.isAndroid) {
      return;
    }

    if (player?.state.playing == true) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/ringtone_in.ogg"));
  }

  void startOutgoingTone() {
    if (player?.state.playing == true) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/ringtone_out.ogg"));
    player?.setPlaylistMode(PlaylistMode.loop);
  }

  void joinCallSound() {
    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/joined_call.ogg"));
    player?.setPlaylistMode(PlaylistMode.none);
  }

  void mute() {
    for (var session in currentSessions) {
      session.setMicrophoneMute(true);
    }

    playMuteSound();
  }

  bool fakeToggle = false;
  void toggleMute() {
    var session = currentSessions.firstOrNull;

    if (session != null) {
      if (session.isMicrophoneMuted) {
        unmute();
      } else {
        mute();
      }
    } else {
      fakeToggle = !fakeToggle;

      // just to give user feedback when not in a call
      if (fakeToggle) {
        playMuteSound();
      } else {
        playUnmuteSound();
      }
    }
  }

  void playMuteSound() {
    if (muteSoundPlayer == null) {
      muteSoundPlayer ??= Player(configuration: PlayerConfiguration());
      muteSoundPlayer!.setVolume(90);
      muteSoundPlayer?.open(Media("asset:///assets/sound/muted.ogg"));
      muteSoundPlayer?.setPlaylistMode(PlaylistMode.none);
    }

    muteSoundPlayer?.seek(Duration.zero);
    muteSoundPlayer?.play();
  }

  void unmute() {
    for (var session in currentSessions) {
      session.setMicrophoneMute(false);
    }

    playUnmuteSound();
  }

  void playUnmuteSound() {
    if (unmuteSoundPlayer == null) {
      unmuteSoundPlayer ??= Player(configuration: PlayerConfiguration());
      unmuteSoundPlayer!.setVolume(90);
      unmuteSoundPlayer?.open(Media("asset:///assets/sound/unmuted.ogg"));
      unmuteSoundPlayer?.setPlaylistMode(PlaylistMode.none);
    }

    unmuteSoundPlayer?.seek(Duration.zero);
    unmuteSoundPlayer?.play();
  }

  void endCallSound() {
    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/left_call.ogg"));
    player?.setPlaylistMode(PlaylistMode.none);
  }

  void stopRingtone() {
    player?.stop();
    player?.dispose();
    player = null;
  }

  void onCallStateChanged(VoipSession event) {
    if (event.state == VoipState.connected ||
        event.state == VoipState.connecting) {
      stopRingtone();
    }

    if (event.state == VoipState.connected) {
      joinCallSound();
    }
  }

  Player getSoundPlayer() {
    player ??= Player(configuration: PlayerConfiguration());
    player!.setVolume(90);

    return player!;
  }
}
