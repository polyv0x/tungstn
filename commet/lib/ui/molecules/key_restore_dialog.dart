import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class KeyRestoreDialog extends StatefulWidget {
  const KeyRestoreDialog({required this.client, super.key});
  final MatrixClient client;

  static Future<bool?> show(BuildContext context, MatrixClient client) {
    return AdaptiveDialog.show<bool>(
      context,
      title: _labelKeyBackupFound,
      type: DialogType.info,
      builder: (context) => KeyRestoreDialog(client: client),
    );
  }

  static String get _labelKeyBackupFound => Intl.message(
        "Encrypted message backup found",
        name: "_labelKeyBackupFound",
        desc: "Title for dialog shown when key backup is available after login",
      );

  @override
  State<KeyRestoreDialog> createState() => _KeyRestoreDialogState();
}

class _KeyRestoreDialogState extends State<KeyRestoreDialog> {
  final controller = TextEditingController();
  bool isLoading = false;
  bool hasError = false;

  String get _labelRecoveryKeyExplanation => Intl.message(
        "To unlock your old messages, please enter your recovery key that has been generated in a previous session. Your recovery key is NOT your password.",
        name: "_labelRecoveryKeyExplanation",
        desc:
            "Shown when a user is attempting to recover their old messages after login",
      );

  String get _labelRecoveryKeyInvalid => Intl.message(
        "Invalid recovery key or passphrase",
        name: "_labelRecoveryKeyInvalid",
        desc: "Error shown when the recovery key input is incorrect",
      );

  String get _promptRecoveryKeyInput => Intl.message(
        "Recovery key",
        name: "_promptRecoveryKeyInput",
        desc: "Placeholder text for the recovery key input box",
      );

  String get _promptRestore => Intl.message(
        "Restore",
        name: "_promptRestore",
        desc: "Button text to restore encryption keys from backup",
      );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: tiamat.Text.label(_labelRecoveryKeyExplanation),
          ),
          const SizedBox(height: 8),
          tiamat.TextInput(
            controller: controller,
            obscureText: true,
            placeholder: _promptRecoveryKeyInput,
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: tiamat.Text.error(_labelRecoveryKeyInvalid),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : tiamat.Button(
                    text: _promptRestore,
                    onTap: _submit,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      isLoading = true;
      hasError = false;
    });

    final success = await widget.client.restoreKeyBackup(controller.text);

    if (success) {
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        isLoading = false;
        hasError = true;
      });
    }
  }
}
