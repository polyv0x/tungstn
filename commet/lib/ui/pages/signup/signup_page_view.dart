import 'dart:ui';

import 'package:commet/client/auth.dart';
import 'package:commet/config/global_config.dart';
import 'package:commet/ui/atoms/shader/star_trails.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SignupPageView extends StatefulWidget {
  const SignupPageView({
    super.key,
    this.progress,
    this.flows,
    this.updateHomeserver,
    this.doRegister,
    this.doSsoLogin,
    this.loadingServerInfo = false,
    this.isServerValid = false,
    this.hasSsoSupport = false,
    this.requiresToken = false,
    required this.isRegistering,
  });

  final double? progress;
  final List<LoginFlow>? flows;
  final bool isRegistering;
  final bool loadingServerInfo;
  final bool isServerValid;
  final bool hasSsoSupport;
  final bool requiresToken;
  final Future<void> Function(String username, String password,
      {String? token})? doRegister;
  final Future<void> Function(SsoLoginFlow flow)? doSsoLogin;
  final Function(String)? updateHomeserver;

  @override
  State<SignupPageView> createState() => _SignupPageViewState();
}

class _SignupPageViewState extends State<SignupPageView> {
  final TextEditingController _homeserverField =
      TextEditingController(text: GlobalConfig.defaultHomeserver);
  final TextEditingController _usernameField = TextEditingController();
  final TextEditingController _passwordField = TextEditingController();
  final TextEditingController _confirmPasswordField = TextEditingController();
  final TextEditingController _tokenField = TextEditingController();

  String? _passwordError;

  @override
  void initState() {
    super.initState();
    if (_homeserverField.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.updateHomeserver?.call(_homeserverField.text);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: const StarTrailsBackground(),
          ),
          SafeArea(
            child: Stack(
              children: [
                Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _card(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.surfaceContainer,
                border: Border.all(
                    color: Theme.of(context).colorScheme.outline, width: 1),
                boxShadow: [
                  BoxShadow(
                      blurRadius: 50,
                      color: Theme.of(context).shadowColor.withAlpha(50))
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: IgnorePointer(
                  ignoring: widget.isRegistering,
                  child: AnimatedOpacity(
                    opacity: widget.isRegistering ? 0.5 : 1.0,
                    duration: Durations.short2,
                    child: _form(context),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.isRegistering)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final ssoFlows = widget.flows?.whereType<SsoLoginFlow>().toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: SvgPicture.asset(
                "assets/images/app_icon/icon.svg",
                theme: SvgTheme(
                    currentColor: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          "Create account",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),

        // Homeserver field
        TextField(
          autocorrect: false,
          controller: _homeserverField,
          readOnly: widget.isRegistering,
          onChanged: widget.updateHomeserver,
          keyboardType: TextInputType.url,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp("[ ]"))],
          decoration: InputDecoration(
            prefixText: 'https://',
            border: const OutlineInputBorder(),
            labelText: "Homeserver",
            suffix: _homeserverSuffix(),
          ),
        ),
        const SizedBox(height: 16),

        // SSO buttons
        if (widget.hasSsoSupport && ssoFlows != null) ...[
          ...ssoFlows.map((flow) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ElevatedButton.icon(
                  icon: SizedBox(
                    width: flow.icon == null ? 0 : 32,
                    height: 48,
                    child:
                        flow.icon != null ? Image(image: flow.icon!) : null,
                  ),
                  label: Text("Continue with ${flow.name}"),
                  onPressed: () => widget.doSsoLogin?.call(flow),
                ),
              )),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Expanded(child: tiamat.Seperator()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: tiamat.Text.labelLow("or"),
                ),
                const Expanded(child: tiamat.Seperator()),
              ],
            ),
          ),
        ],

        // Username
        TextField(
          autocorrect: false,
          controller: _usernameField,
          readOnly: widget.isRegistering,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp("[ ]"))],
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: "Username",
          ),
        ),
        const SizedBox(height: 16),

        // Password
        TextField(
          autocorrect: false,
          controller: _passwordField,
          obscureText: true,
          readOnly: widget.isRegistering,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: "Password",
          ),
        ),
        const SizedBox(height: 16),

        // Confirm password
        TextField(
          autocorrect: false,
          controller: _confirmPasswordField,
          obscureText: true,
          readOnly: widget.isRegistering,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: "Confirm password",
            errorText: _passwordError,
          ),
        ),
        const SizedBox(height: 16),

        // Invite token (only shown when server requires it)
        if (widget.requiresToken) ...[
          TextField(
            autocorrect: false,
            controller: _tokenField,
            readOnly: widget.isRegistering,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "Invite token",
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Register button
        SizedBox(
          height: 50,
          child: tiamat.Button(
            text: "Create account",
            onTap: widget.isServerValid ? _onRegisterPressed : null,
          ),
        ),

        // Progress bar
        SizedBox(
          height: 15,
          child: Center(
            child: SizedBox(
              height: 5,
              child: widget.progress == null
                  ? null
                  : LinearProgressIndicator(value: widget.progress),
            ),
          ),
        ),

        // "Already have an account?" link
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              tiamat.Text.labelLow("Already have an account?"),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Sign in"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _homeserverSuffix() {
    if (widget.loadingServerInfo) {
      return const SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Icon(
      widget.isServerValid ? Icons.check : Icons.close,
      size: 15,
      color: widget.isServerValid ? Colors.greenAccent : Colors.redAccent,
    );
  }

  void _onRegisterPressed() {
    final password = _passwordField.text;
    final confirm = _confirmPasswordField.text;

    if (password != confirm) {
      setState(() {
        _passwordError = "Passwords do not match";
      });
      return;
    }

    setState(() {
      _passwordError = null;
    });

    widget.doRegister?.call(
      _usernameField.text,
      password,
      token: widget.requiresToken ? _tokenField.text : null,
    );
  }
}
