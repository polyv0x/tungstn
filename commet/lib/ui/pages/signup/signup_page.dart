import 'dart:async';

import 'package:commet/client/auth.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/signup/signup_page_view.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SignupPage extends StatefulWidget {
  const SignupPage({super.key, this.onSuccess});
  final Function(Client loggedInClient)? onSuccess;

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  StreamSubscription? progressSubscription;
  double? progress;
  List<LoginFlow>? loginFlows;
  Client? signupClient;

  final Debouncer homeserverUpdateDebouncer = Debouncer(
    delay: const Duration(seconds: 1),
  );

  bool loadingServerInfo = false;
  bool isServerValid = false;
  bool isRegistering = false;
  bool requiresToken = false;

  @override
  void initState() {
    super.initState();
    MatrixClient.create(RandomUtils.getRandomString(20)).then((client) {
      signupClient = client;
      progressSubscription =
          signupClient!.connectionStatusChanged.stream.listen(
        _onProgressChanged,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SignupPageView(
      progress: progress,
      flows: loginFlows,
      isRegistering: isRegistering,
      loadingServerInfo: loadingServerInfo,
      isServerValid: isServerValid,
      requiresToken: requiresToken,
      hasSsoSupport: loginFlows?.whereType<SsoLoginFlow>().isNotEmpty == true,
      updateHomeserver: (value) {
        setState(() {
          loginFlows = null;
          isServerValid = false;
          loadingServerInfo = true;
        });
        homeserverUpdateDebouncer.run(() => _updateHomeserver(value));
      },
      doRegister: _doRegister,
      doSsoLogin: _doSsoLogin,
    );
  }

  Future<void> _updateHomeserver(String input) async {
    if (signupClient == null) return;

    setState(() {
      loginFlows = null;
      loadingServerInfo = true;
      isServerValid = false;
    });

    var uri = Uri.https(input);
    var result = await signupClient!.setHomeserver(uri);

    setState(() {
      loadingServerInfo = false;
      isServerValid = result.$1;
      loginFlows = result.$2;
      requiresToken = result.$4;
    });
  }

  Future<void> _doRegister(String username, String password,
      {String? token}) async {
    if (signupClient is! MatrixClient) return;
    if (!isServerValid) return;

    setState(() {
      isRegistering = true;
    });

    final result = await (signupClient as MatrixClient)
        .register(username, password, registrationToken: token);

    if (result is! LoginResultSuccess) {
      setState(() {
        isRegistering = false;
      });

      final message = switch (result) {
        LoginResultError e => e.errorMessage,
        LoginResultFailed _ => "Registration failed",
        _ => "Registration failed",
      };

      if (mounted) {
        AdaptiveDialog.show(
          context,
          title: "Registration failed",
          builder: (_) => tiamat.Text(message),
        );
      }
      return;
    }

    clientManager?.addClient(signupClient!);
    widget.onSuccess?.call(signupClient!);
  }

  Future<void> _doSsoLogin(SsoLoginFlow flow) async {
    if (signupClient == null) return;
    if (!isServerValid) return;

    setState(() {
      isRegistering = true;
    });

    final result = await signupClient!.executeLoginFlow(flow);

    if (result is! LoginResultSuccess) {
      setState(() {
        isRegistering = false;
      });

      final message = switch (result) {
        LoginResultError e => e.errorMessage,
        LoginResultCancelled _ => null,
        _ => "Login failed",
      };

      if (message != null && mounted) {
        AdaptiveDialog.show(
          context,
          title: "Login failed",
          builder: (_) => tiamat.Text(message),
        );
      }
      return;
    }

    clientManager?.addClient(signupClient!);
    widget.onSuccess?.call(signupClient!);
  }

  void _onProgressChanged(ClientConnectionStatusUpdate event) {
    if (!mounted) return;
    setState(() {
      progress = event.progress;
    });
  }
}
