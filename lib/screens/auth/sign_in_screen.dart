import 'package:flutter/material.dart';

import '../../models/auth_controller.dart';
import 'auth_form.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({this.auth, super.key});
  final AuthController? auth;
  @override
  Widget build(BuildContext context) =>
      AuthForm(auth: auth ?? AuthController.instance);
}
