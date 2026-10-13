import 'package:flutter/material.dart';

import '../../models/auth_controller.dart';
import '../../services/auth_repository.dart';
import 'auth_form.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({required this.auth, super.key});
  final AuthController auth;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    String message;
    try {
      message = await widget.auth.reset(_email.text);
    } on AuthFailure catch (error) {
      message = error.message;
    } catch (_) {
      message = 'Unable to request a reset. Please try again.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _message = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AuthCanvas(
    title: 'Reset your password',
    subtitle: 'Enter your account email.',
    children: [
      Form(
        key: _form,
        child: TextFormField(
          controller: _email,
          validator: validateEmail,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _send(),
          decoration: const InputDecoration(labelText: 'Email address'),
        ),
      ),
      const SizedBox(height: 24),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Semantics(liveRegion: true, child: Text(_message!)),
        ),
      FilledButton(
        onPressed: _busy ? null : _send,
        child: Text(_busy ? 'Requesting…' : 'Send reset link'),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Back to sign in'),
      ),
    ],
  );
}
