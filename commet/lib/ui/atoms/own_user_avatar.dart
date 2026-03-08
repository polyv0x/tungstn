import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Avatar for the current user with a live presence indicator.
/// Reads from [ClientManager.ownPresenceFor] — a single subscription per
/// client shared across all instances, so presence state is always consistent.
class OwnUserAvatar extends StatefulWidget {
  const OwnUserAvatar({required this.client, required this.radius, super.key});

  final Client client;
  final double radius;

  @override
  State<OwnUserAvatar> createState() => _OwnUserAvatarState();
}

class _OwnUserAvatarState extends State<OwnUserAvatar> {
  StreamSubscription? _sub;

  UserPresence get _presence =>
      clientManager!.ownPresenceFor(widget.client.identifier);

  @override
  void initState() {
    super.initState();
    _sub = clientManager!.onOwnPresenceChanged
        .where((t) => t.$1 == widget.client.identifier)
        .listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.client.self;
    if (profile == null) return const SizedBox.shrink();

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        ClipOval(
          child: tiamat.Avatar(
            radius: widget.radius,
            image: profile.avatar,
            placeholderColor: profile.defaultColor,
            placeholderText: profile.displayName,
          ),
        ),
        if (_presence.status != UserPresenceStatus.unknown)
          UserPanelView.createPresenceIcon(context, _presence.status),
      ],
    );
  }
}
