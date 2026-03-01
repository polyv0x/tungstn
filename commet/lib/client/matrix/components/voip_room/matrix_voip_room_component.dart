import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/matrix/components/matrix_sync_listener.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:matrix/matrix.dart';

class MatrixVoipRoomComponent
    implements
        VoipRoomComponent<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener {
  static const callMemberStateEvent = "org.matrix.msc3401.call.member";

  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  late MatrixLivekitBackend backend;

  VoipSession? currentSession;

  MatrixVoipRoomComponent(this.client, this.room) {
    backend = MatrixLivekitBackend(room);
  }

  static bool isVoipRoom(MatrixRoom room) {
    return room.matrixRoom.getState(EventTypes.RoomCreate)?.content['type'] ==
        "org.matrix.msc3417.call";
  }

  StreamController _onParticipantsChanged = StreamController.broadcast();

  @override
  onSync(JoinedRoomUpdate update) {
    final hasCallMemberEvent =
        update.timeline?.events?.any((e) => e.type == callMemberStateEvent) ==
                true ||
            update.state?.any((e) => e.type == callMemberStateEvent) ==
                true;

    if (hasCallMemberEvent) {
      _onParticipantsChanged.add(());
    }
  }

  @override
  List<String> getCurrentParticipants() {
    final state = room.matrixRoom.states[callMemberStateEvent];
    if (state == null) {
      return [];
    }

    final localUserId = client.matrixClient.userID;

    List<String> participants = List.empty(growable: true);

    // Optimistically include ourselves if we've joined, before the server sync
    // comes back with our updated state.
    if (currentSession != null && localUserId != null) {
      participants.add(localUserId);
    }

    for (var pair in state.entries) {
      if (pair.value.content.isEmpty) {
        continue;
      }

      final sender = pair.value.senderId;

      // Optimistically exclude ourselves if we've left the call, before the
      // server sync comes back with our cleared state.
      if (currentSession == null && sender == localUserId) {
        continue;
      }

      if (participants.contains(sender)) {
        continue;
      }

      participants.add(sender);
    }

    return participants;
  }

  @override
  Stream<void> get onParticipantsChanged => _onParticipantsChanged.stream;

  @override
  Future<VoipSession?> joinCall() async {
    currentSession = await backend.join();
    currentSession?.onStateChanged.listen(onStateChanged);
    _onParticipantsChanged.add(());
    return currentSession;
  }

  @override
  Future<String?> getCallServerUrl() async {
    final url = await backend.getFociUrl();
    return url.firstOrNull?.authority.toString();
  }

  void onStateChanged(void event) {
    final state = currentSession?.state;
    print("Got call state: ${state}");

    if (state == VoipState.ended) {
      currentSession = null;
      _onParticipantsChanged.add(());
    }
  }

  @override
  bool get canJoinCall => room.matrixRoom.canChangeStateEvent(
        MatrixVoipRoomComponent.callMemberStateEvent,
      );

  @override
  Future<void> clearAllCallMembershipStatus() async {
    final state = room.matrixRoom.states[callMemberStateEvent];
    if (state == null) {
      return;
    }

    var futures = [
      for (var entry in state.entries)
        if (entry.value.senderId == client.matrixClient.userID)
          client.matrixClient.setRoomStateWithKey(
            room.identifier,
            MatrixVoipRoomComponent.callMemberStateEvent,
            entry.key,
            {},
          ),
    ];

    await Future.wait(futures);
  }
}
