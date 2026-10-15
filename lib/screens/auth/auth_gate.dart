import 'package:flutter/material.dart';

import '../../models/auth_controller.dart';
import '../../admin/screens/admin_shell.dart';
import '../../admin/screens/offline_admin_screen.dart';
import '../home/home_screen.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';
import 'forgot_password_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.auth,
    this.userBuilder,
    this.adminBuilder,
    this.offlineAdminBuilder,
    this.onboardingBuilder,
    this.requireAuthentication = false,
    super.key,
  });
  final AuthController auth;
  final WidgetBuilder? userBuilder, adminBuilder, offlineAdminBuilder;
  final Widget Function(BuildContext, VoidCallback)? onboardingBuilder;

  /// Only explicit account/admin entry requires a session. Travellers use Home.
  final bool requireAuthentication;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _onboardingComplete = false;
  @override
  void initState() {
    super.initState();
    widget.auth.restore();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.auth,
    builder: (context, _) {
      final auth = widget.auth;
      if (auth.status == AuthStatus.unknown) {
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Restoring session',
            ),
          ),
        );
      }
      final authenticated =
          auth.status == AuthStatus.authenticatedUser ||
          auth.status == AuthStatus.authenticatedAdmin ||
          auth.isOfflineAdmin;
      // Account restoration is optional for travellers. Logout and expiry return
      // to guest Home without replaying onboarding or interrupting planning.
      if (authenticated) _onboardingComplete = true;
      final onboarding =
          !authenticated &&
          !_onboardingComplete &&
          widget.onboardingBuilder != null;
      Widget root(BuildContext context) => !authenticated
          ? onboarding
                ? widget.onboardingBuilder!(context, () {
                    setState(() => _onboardingComplete = true);
                  })
                : widget.requireAuthentication
                ? SignInScreen(auth: auth)
                : (widget.userBuilder?.call(context) ?? const HomeScreen())
          : auth.isOfflineAdmin
          ? (widget.offlineAdminBuilder?.call(context) ??
                OfflineAdminScreen(auth: auth))
          : auth.isAdmin
          ? (widget.adminBuilder?.call(context) ?? AdminShell(auth: auth))
          : (widget.userBuilder?.call(context) ?? const HomeScreen());
      return Navigator(
        key: ValueKey(
          '${onboarding
              ? 'onboarding'
              : authenticated
              ? auth.isOfflineAdmin
                    ? 'offline-admin'
                    : auth.isAdmin
                    ? 'admin'
                    : 'user'
              : widget.requireAuthentication
              ? 'auth'
              : 'user'}-${auth.generation}',
        ),
        onGenerateRoute: (settings) {
          Widget screen = root(context);
          if (!authenticated && !onboarding && widget.requireAuthentication) {
            if (settings.name == '/signup') screen = SignUpScreen(auth: auth);
            if (settings.name == '/forgot-password') {
              screen = ForgotPasswordScreen(auth: auth);
            }
          }
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => screen,
          );
        },
      );
    },
  );
}
