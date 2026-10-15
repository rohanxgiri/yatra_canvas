import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/auth_controller.dart';
import '../../services/offline_admin_access.dart';
import '../../theme/yc_style.dart';
import '../../widgets/yatra_brand.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';
import 'forgot_password_screen.dart';

String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Enter your email address.';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
    return 'Enter a valid email address.';
  }
  return null;
}

class AuthCanvas extends StatelessWidget {
  const AuthCanvas({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });
  final String title, subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Theme(
    data: YCStyle.theme(context),
    child: Scaffold(
      backgroundColor: YCStyle.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              children: [
                const YatraBrand(compact: true),
                const SizedBox(height: 48),
                Text(title, style: YCStyle.sectionTitle.copyWith(fontSize: 28)),
                const SizedBox(height: 12),
                Text(subtitle, style: YCStyle.secondary),
                const SizedBox(height: 32),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthForm extends StatefulWidget {
  const AuthForm({required this.auth, this.signup = false, super.key});
  final AuthController auth;
  final bool signup;
  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController();
  final _password = TextEditingController(), _confirm = TextEditingController();
  bool _hidden = true, _confirmHidden = true;
  bool _offlineAdmin = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.auth.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    final accepted = widget.signup
        ? await widget.auth.signup(_name.text, _email.text, _password.text)
        : _offlineAdmin
        ? await widget.auth.loginOfflineAdmin(_email.text, _password.text)
        : await widget.auth.login(_email.text, _password.text);
    if (!mounted) return;
    if (accepted) {
      TextInput.finishAutofillContext();
    } else {
      setState(() => _error = widget.auth.error);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    bool password = false,
    bool confirm = false,
    List<String>? autofill,
    TextInputType? keyboard,
  }) {
    final hidden = confirm ? _confirmHidden : _hidden;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        key: ValueKey(label),
        controller: controller,
        validator: validator,
        keyboardType: keyboard,
        autofillHints: autofill,
        obscureText: password && hidden,
        autocorrect: !password && keyboard != TextInputType.emailAddress,
        enableSuggestions: !password,
        textInputAction: confirm || password && !widget.signup
            ? TextInputAction.done
            : TextInputAction.next,
        onFieldSubmitted: confirm || password && !widget.signup
            ? (_) => _submit()
            : null,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: YCStyle.border),
          ),
          suffixIcon: password
              ? IconButton(
                  tooltip: hidden ? 'Show $label' : 'Hide $label',
                  onPressed: () => setState(() {
                    if (confirm) {
                      _confirmHidden = !_confirmHidden;
                    } else {
                      _hidden = !_hidden;
                    }
                  }),
                  icon: Icon(
                    hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.auth,
    builder: (context, _) => AuthCanvas(
      title: widget.signup
          ? 'Create your account'
          : _offlineAdmin
          ? 'Offline admin'
          : 'Welcome back',
      subtitle: widget.signup
          ? 'Start building trips around the places you love.'
          : _offlineAdmin
          ? 'Sign in to the city data stored on this device. No internet needed.'
          : 'Continue planning journeys made for you.',
      children: [
        if (!widget.signup && !kIsWeb) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Online')),
              ButtonSegment(value: true, label: Text('Offline admin')),
            ],
            selected: {_offlineAdmin},
            onSelectionChanged: widget.auth.busy
                ? null
                : (selection) => setState(() {
                    _offlineAdmin = selection.single;
                    _error = null;
                    if (_offlineAdmin && _email.text.isEmpty) {
                      _email.text = OfflineAdminAccess.email;
                    }
                  }),
          ),
          const SizedBox(height: 24),
        ],
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.signup)
                  _field(
                    'Full name',
                    _name,
                    keyboard: TextInputType.name,
                    autofill: const [AutofillHints.name],
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter your full name.'
                        : null,
                  ),
                _field(
                  'Email address',
                  _email,
                  keyboard: TextInputType.emailAddress,
                  autofill: const [AutofillHints.email],
                  validator: validateEmail,
                ),
                _field(
                  'Password',
                  _password,
                  password: true,
                  autofill: [
                    widget.signup
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter your password.';
                    if (widget.signup &&
                        (v.length < 8 || utf8.encode(v).length > 72)) {
                      return 'Use 8 or more characters, up to 72 UTF-8 bytes.';
                    }
                    return null;
                  },
                ),
                if (widget.signup)
                  _field(
                    'Confirm password',
                    _confirm,
                    password: true,
                    confirm: true,
                    autofill: const [AutofillHints.newPassword],
                    validator: (v) =>
                        v != _password.text ? 'Passwords do not match.' : null,
                  ),
                if (!widget.signup)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.auth.busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ForgotPasswordScreen(auth: widget.auth),
                              ),
                            ),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                if (_error != null || widget.auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error ?? widget.auth.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: widget.auth.busy ? null : _submit,
                  child: widget.auth.busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.signup ? 'Create account' : 'Sign In'),
                ),
                if (widget.auth.logoutIncomplete)
                  TextButton(
                    onPressed: widget.auth.logout,
                    child: const Text('Retry signing out'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        if (!widget.signup)
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('or'),
              ),
              Expanded(child: Divider()),
            ],
          ),
        const SizedBox(height: 16),
        Text(
          widget.signup ? 'Already have an account?' : 'New to YatraCanvas?',
          textAlign: TextAlign.center,
          style: YCStyle.secondary,
        ),
        TextButton(
          onPressed: widget.auth.busy
              ? null
              : () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => widget.signup
                        ? SignInScreen(auth: widget.auth)
                        : SignUpScreen(auth: widget.auth),
                  ),
                ),
          child: Text(widget.signup ? 'Sign in' : 'Create an account'),
        ),
        if (!widget.signup)
          TextButton(
            onPressed: widget.auth.busy ? null : widget.auth.enterGuest,
            child: const Text('Continue as a guest'),
          ),
      ],
    ),
  );
}
