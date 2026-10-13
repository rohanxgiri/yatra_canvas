import 'package:flutter/material.dart';

import '../../models/auth_controller.dart';
import 'auth_form.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({this.auth, super.key});
  final AuthController? auth;
  @override
  Widget build(BuildContext context) =>
      AuthForm(auth: auth ?? AuthController.instance, signup: true);
}
