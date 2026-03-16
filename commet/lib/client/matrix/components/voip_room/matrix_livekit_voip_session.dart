import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/webrtc_screencapture_source.dart';
import 'package:commet/client/components/voip/android_screencapture_source.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix_api_lite.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class MatrixLivekitVoipSession implements VoipSession {
  MatrixRoom room;
  lk.Room livekitRoom;
  Timer? heartbeatTimer;
  String? heartbeatDelayId;

  final StreamController<void> _onVolumeChanged = StreamController.broadcast();
  final StreamController<void> _onParticipantsChanged =
      StreamController.broadcast();

  MatrixLivekitVoipSession(this.room, this.livekitRoom,
      {VoipState initialState = VoipState.connected}) {
    state = initialState;
    clientManager?.callManager.onClientSessionStarted(this);
    addInitialStreams();

    final listener = livekitRoom.createListener();
    listener.on(onTrackPublished);
    listener.on(onTrackUnpublished);
    listener.on(onLocalTrackPublished);
    listener.on(onLocalTrackUnpublished);
    listener.on(onTrackStreamEvent);
    listener.on(onTrackMutedEvent);
    listener.on(onTrackUnmutedEvent);
    listener.on(onParticipantConnected);
    listener.on(onParticipantDisconnected);
    listener.on<lk.RoomDisconnectedEvent>(onRoomDisconnected);

    Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (state == VoipState.ended) timer.cancel();
      _onVolumeChanged.add(());
    });

    if (initialState == VoipState.connected) {
      startHeartbeat();
    }
  }

  /// Called by the backend once the LiveKit connection is fully established.
  Future<void> completeConnection() async {
    state = VoipState.connected;
    _stateChanged.add(());
    _onConnectionChanged.add(state);
    await startHeartbeat();
  }

  /// Called by the backend when background connection fails.
  void failConnection() {
    state = VoipState.ended;
    _stateChanged.add(());
    _onConnectionChanged.add(state);
    clientManager?.callManager.onSessionEnded(this);
  }

  StreamController _stateChanged = StreamController.broadcast();
  final StreamController<VoipState> _onConnectionChanged =
      StreamController.broadcast();

  @override
  Stream<VoipState> get onConnectionStateChanged => _onConnectionChanged.stream;

  void addInitialStreams() {
    if (livekitRoom.localParticipant != null) {
      for (var entry
          in livekitRoom.localParticipant!.trackPublications.entries) {
        if (entry.value.muted && entry.value.kind == lk.TrackType.VIDEO) {
          continue;
        }

        streams.add(
            MatrixLivekitVoipStream(entry.value, room.client.self!.identifier));
      }
    }

    for (var entry in livekitRoom.remoteParticipants.entries) {
      for (var stream in entry.value.trackPublications.entries) {
        if (stream.value.kind == lk.TrackType.VIDEO && stream.value.muted) {
          continue;
        }

        String userId = entry.key;
        userId = userId.split(":").getRange(0, 2).join(":");

        streams.add(MatrixLivekitVoipStream(stream.value, userId));
      }
    }
  }

  @override
  Future<void> acceptCall(
      {bool withMicrophone = false, bool withCamera = false}) {
    throw UnimplementedError();
  }

  void onTrackStreamEvent(lk.TrackStreamStateUpdatedEvent event) {
    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }
  }

  void onTrackMutedEvent(lk.TrackMutedEvent event) {
    if (event.publication.track?.mediaType ==
        RTCRtpMediaType.RTCRtpMediaTypeVideo) {
      streams.removeWhere((e) =>
          (e as MatrixLivekitVoipStream).publication.sid ==
          event.publication.sid);
    }

    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }

    print("Track muted");

    _stateChanged.add(());
  }

  void onTrackUnmutedEvent(lk.TrackUnmutedEvent event) {
    final participant =
        event.participant.identity.split(":").getRange(0, 2).join(":");

    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }

    if (streams.any((e) => e.streamId == event.publication.sid)) {
      return;
    }

    streams.add(MatrixLivekitVoipStream(event.publication, participant));
    _stateChanged.add(());
  }

  void onTrackPublished(lk.TrackPublishedEvent event) {
    final participant =
        event.participant.identity.split(":").getRange(0, 2).join(":");

    streams.add(MatrixLivekitVoipStream(event.publication, participant));
    _stateChanged.add(());
  }

  void onParticipantConnected(lk.ParticipantConnectedEvent event) {
    clientManager?.callManager.joinCallSound();
    _onParticipantsChanged.add(());
  }

  void onParticipantDisconnected(lk.ParticipantDisconnectedEvent event) {
    clientManager?.callManager.endCallSound();
    _onParticipantsChanged.add(());
  }

  void onRoomDisconnected(lk.RoomDisconnectedEvent event) {
    if (state == VoipState.ended) return;
    Log.w("LiveKit room disconnected unexpectedly (reason: ${event.reason}), ending session");
    hangUpCall();
  }

  void onLocalTrackPublished(lk.LocalTrackPublishedEvent event) {
    final participant =
        event.participant.identity.split(":").getRange(0, 2).join(":");

    streams.add(MatrixLivekitVoipStream(event.publication, participant));
    _stateChanged.add(());
  }

  void onLocalTrackUnpublished(lk.LocalTrackUnpublishedEvent event) {
    streams.removeWhere((e) =>
        (e as MatrixLivekitVoipStream).publication.sid ==
        event.publication.sid);

    _stateChanged.add(());
  }

  void onTrackUnpublished(lk.TrackUnpublishedEvent event) {
    streams.removeWhere((e) =>
        (e as MatrixLivekitVoipStream).publication.sid ==
        event.publication.sid);

    _stateChanged.add(());
  }

  @override
  Client get client => room.client;

  @override
  VoipState state = VoipState.connecting;

  @override
  Future<void> declineCall() {
    throw UnimplementedError();
  }

  @override
  Future<void> hangUpCall() async {
    Log.i("Hanging up call");

    await Future.wait([
      clearRoomCallState(),
      disconnectCall(),
      stopHeartbeat(),
    ]);

    state = VoipState.ended;
    _stateChanged.add(());
    _onConnectionChanged.add(state);

    clientManager?.callManager.onSessionEnded(this);
  }

  @override
  bool get isCameraEnabled =>
      livekitRoom.localParticipant?.isCameraEnabled() ?? false;

  bool _isMicrophoneMuted = false;

  @override
  bool get isMicrophoneMuted => _isMicrophoneMuted;

  bool _isDeafened = false;

  @override
  bool get isDeafened => _isDeafened;

  @override
  bool get isSharingScreen =>
      livekitRoom.localParticipant?.isScreenShareEnabled() ?? false;

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  @override
  String? get remoteUserId => null;

  @override
  VoipStream? get remoteUserMediaStream => null;

  @override
  String? get remoteUserName => null;

  @override
  String get roomId => room.identifier;

  @override
  String get roomName => room.displayName;

  @override
  String get sessionId => "";

  @override
  Future<void> setMicrophoneMute(bool state) async {
    _isMicrophoneMuted = state;
    await livekitRoom.localParticipant?.setMicrophoneEnabled(!state);
    _stateChanged.add(());
  }

  @override
  Future<void> setDeafened(bool deafened) async {
    _isDeafened = deafened;
    // Mute mic when deafening
    await livekitRoom.localParticipant?.setMicrophoneEnabled(!deafened);
    // Disable/enable all remote audio tracks
    for (final participant in livekitRoom.remoteParticipants.values) {
      for (final pub in participant.trackPublications.values) {
        final track = pub.track;
        if (track != null && track.kind == lk.TrackType.AUDIO) {
          if (deafened) {
            await track.disable();
          } else {
            await track.enable();
          }
        }
      }
    }
    _stateChanged.add(());
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {
    if (source is WebrtcAndroidScreencaptureSource ||
        source is _WebScreencaptureSource) {
      await livekitRoom.localParticipant?.setScreenShareEnabled(true);
      _stateChanged.add(());
      return;
    }

    final src = (source as WebrtcScreencaptureSource).source;

    var framerate = double.tryParse(preferences.streamFramerate.value) ?? 30.0;
    var codec = preferences.streamCodec.value;

    final resolutionMap = {
      "720p": (lk.VideoDimensions(1280, 720), 4_000_000),
      "1080p": (lk.VideoDimensions(1920, 1080), 8_000_000),
      "1440p": (lk.VideoDimensions(2560, 1440), 16_000_000),
      "Source": (lk.VideoDimensions(3840, 2160), 20_000_000),
    };
    final (dims, autoBitrate) =
        resolutionMap[preferences.streamResolution.value] ??
            (lk.VideoDimensions(1920, 1080), 8_000_000);
    var bitrate = preferences.streamBitrate.value > 0
        ? (preferences.streamBitrate.value * 1_000_000).toInt()
        : autoBitrate;

    Log.i(
        "Starting stream with settings: ${bitrate ~/ 1_000_000}Mbps, ${framerate}FPS, $codec $dims");

    var track = await lk.LocalVideoTrack.createScreenShareTrack(
        lk.ScreenShareCaptureOptions(
      sourceId: src.id,
      maxFrameRate: framerate,
      params: lk.VideoParameters(
        dimensions: dims,
        encoding: lk.VideoEncoding(
            maxFramerate: framerate.toInt(), maxBitrate: bitrate),
      ),
    ));

    print("Available codecs");
    livekitRoom.engine.enabledPublishCodecs?.forEach((i) => print(i.mime));

    await livekitRoom.localParticipant?.publishVideoTrack(track,
        publishOptions: lk.VideoPublishOptions(
          simulcast: preferences.doSimulcast.value,
          screenShareEncoding:
              lk.VideoEncoding(maxFramerate: framerate.toInt(), maxBitrate: bitrate),
          videoEncoding:
              lk.VideoEncoding(maxFramerate: framerate.toInt(), maxBitrate: bitrate),
          videoCodec: preferences.streamCodec.value,
        ));

    await track
        .setDegradationPreference(lk.DegradationPreference.maintainFramerate);

    _stateChanged.add(());
  }

  @override
  Future<void> setCamera(MediaDeviceInfo? device) async {
    if (isCameraEnabled) {
      Log.e("Tried to enable camera when camera already enabled!");
      return;
    }

    await livekitRoom.localParticipant?.setCameraEnabled(true);
    _stateChanged.add(());
  }

  @override
  Future<void> stopCamera() async {
    await livekitRoom.localParticipant?.setCameraEnabled(false);

    _stateChanged.add(());
  }

  @override
  Future<void> stopScreenshare() async {
    await livekitRoom.localParticipant?.setScreenShareEnabled(false);

    if (PlatformUtils.isAndroid) {
      try {
        await FlutterBackground.disableBackgroundExecution();
      } catch (error) {
        Log.e('error disabling screen share: $error');
      }
    }

    _stateChanged.add(());
  }

  @override
  List<VoipStream> streams = List<VoipStream>.empty(growable: true);

  @override
  Stream<void> get onParticipantsChanged => _onParticipantsChanged.stream;

  @override
  List<String> get connectedParticipants {
    final localId = room.client.self?.identifier;
    final participants = <String>[];
    if (localId != null) participants.add(localId);

    for (var entry in livekitRoom.remoteParticipants.entries) {
      final userId = entry.key.split(":").getRange(0, 2).join(":");
      if (!participants.contains(userId)) {
        participants.add(userId);
      }
    }
    return participants;
  }

  @override
  bool get supportsScreenshare => true;

  double? _latencyMs;
  double? _packetLossRate;

  @override
  double? get latencyMs => _latencyMs;

  @override
  double? get packetLossRate => _packetLossRate;

  @override
  Future<void> updateStats() async {
    final pubPc = livekitRoom.engine.publisher?.pc;
    final subPc = livekitRoom.engine.subscriber?.pc;

    final rtt = await _getRttMs(pubPc) ?? await _getRttMs(subPc);
    if (rtt != null) _latencyMs = rtt;

    final loss = await _getPacketLossRate(pubPc) ?? await _getPacketLossRate(subPc);
    if (loss != null) _packetLossRate = loss;
  }

  Future<double?> _getRttMs(dynamic pc) async {
    if (pc == null) return null;
    try {
      final stats = await pc.getStats() as List;

      // Prefer candidate-pair currentRoundTripTime (transport-level RTT)
      String? selectedPairId;
      for (final report in stats) {
        if (report.type == 'transport') {
          selectedPairId =
              report.values['selectedCandidatePairId'] as String?;
          break;
        }
      }
      for (final report in stats) {
        if (report.type != 'candidate-pair') continue;
        final isSelected = selectedPairId != null
            ? report.id == selectedPairId
            : (report.values['nominated'] == true ||
                report.values['state'] == 'succeeded');
        if (!isSelected) continue;
        final rttRaw = report.values['currentRoundTripTime'];
        if (rttRaw != null) return (rttRaw as num).toDouble() * 1000;
      }

      // Fall back to RTCP-based RTT from remote-inbound-rtp
      for (final report in stats) {
        if (report.type != 'remote-inbound-rtp') continue;
        final rttRaw = report.values['roundTripTime'];
        if (rttRaw != null) return (rttRaw as num).toDouble() * 1000;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<double?> _getPacketLossRate(dynamic pc) async {
    if (pc == null) return null;
    try {
      final stats = await pc.getStats() as List;
      final losses = <double>[];
      for (final report in stats) {
        if (report.type != 'remote-inbound-rtp') continue;
        final raw = report.values['fractionLost'];
        if (raw != null) losses.add((raw as num).toDouble());
      }
      if (losses.isEmpty) return null;
      return losses.reduce((a, b) => a + b) / losses.length;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async {
    if (PlatformUtils.isWeb) {
      return _WebScreencaptureSource();
    }
    if (PlatformUtils.isAndroid) {
      return WebrtcAndroidScreencaptureSource.getCaptureSource(context);
    }
    return WebrtcScreencaptureSource.showSelectSourcePrompt(context);
  }

  Future<void> clearRoomCallState() async {
    Log.i("Clearing call state");
    final stateKey =
        "_${room.client.self!.identifier}_${room.matrixRoom.client.deviceID!}_m.call";

    await room.matrixRoom.client.setRoomStateWithKey(room.matrixRoom.id,
        MatrixVoipRoomComponent.callMemberStateEvent, stateKey, {});

    Log.i("Cleared call state");
  }

  Future<void> stopHeartbeat() async {
    heartbeatTimer?.cancel();
    heartbeatTimer = null;

    if (heartbeatDelayId == null) {
      return;
    }

    await room.matrixRoom.client.request(RequestType.POST,
        "/client/unstable/org.matrix.msc4140/delayed_events/${Uri.encodeComponent(heartbeatDelayId!)}",
        contentType: "application/json",
        data: jsonEncode({"action": "cancel"}));

    heartbeatDelayId = null;
    Log.i("Stopped heartbeat");
  }

  Future<void> startHeartbeat() async {
    final capabilities = await room.matrixRoom.client.getVersions();
    Log.d("${capabilities}");
    if (capabilities.unstableFeatures?["org.matrix.msc4140"] != true) {
      Log.e("Homeserver does not support delayed events");
      return;
    }

    final stateKey =
        "_${room.client.self!.identifier}_${room.matrixRoom.client.deviceID!}_m.call";

    final timerLength = Duration(seconds: 30);

    final result = await room.matrixRoom.client.request(RequestType.PUT,
        "/client/v3/rooms/${Uri.encodeComponent(room.matrixRoom.id)}/state/${Uri.encodeComponent(MatrixVoipRoomComponent.callMemberStateEvent)}/${Uri.encodeComponent(stateKey)}",
        contentType: "application/json",
        data: "{}",
        query: {
          "org.matrix.msc4140.delay": timerLength.inMilliseconds.toString()
        });

    final delayId = result["delay_id"] as String;
    heartbeatDelayId = delayId;

    heartbeatTimer =
        Timer.periodic(timerLength - Duration(seconds: 5), (timer) async {
      if (state == VoipState.ended) {
        timer.cancel();
        return;
      }
      try {
        await room.matrixRoom.client.request(RequestType.POST,
            "/client/unstable/org.matrix.msc4140/delayed_events/${Uri.encodeComponent(delayId)}",
            contentType: "application/json",
            data: jsonEncode({"action": "restart"}));
      } catch (e) {
        Log.w("Heartbeat failed: $e — ending session");
        timer.cancel();
        heartbeatDelayId = null;
        if (state != VoipState.ended) hangUpCall();
      }
    });
  }

  @override
  double get generalAudioLevel {
    double result =
        streams.fold(0.0, (value, stream) => max(value, stream.audiolevel));
    return result;
  }

  @override
  Stream<void> get onUpdateVolumeVisualizers => _onVolumeChanged.stream;

  Future<void> disconnectCall() async {
    Log.i("Disconnecting livekit room");
    await livekitRoom.disconnect();
    Log.i("Disconnected livekit room");
  }
}

class _WebScreencaptureSource implements ScreenCaptureSource {}
