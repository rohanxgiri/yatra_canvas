import 'package:flutter/material.dart';

/// The shared interaction language for YatraCanvas.
///
/// Motion is intentionally brief: it explains state and spatial continuity
/// without making routine navigation feel ceremonial.
abstract final class YCMotion {
  static const instant = Duration(milliseconds: 100);
  static const press = Duration(milliseconds: 130);
  static const component = Duration(milliseconds: 220);
  static const navigation = Duration(milliseconds: 320);
  static const journey = Duration(milliseconds: 380);

  static const standard = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutQuart;
  static const exit = Curves.easeInCubic;

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

/// A restrained fade-and-travel transition used by ordinary app navigation.
class YCPageTransitionsBuilder extends PageTransitionsBuilder {
  const YCPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context) || route.isFirst) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: YCMotion.standard,
      reverseCurve: YCMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.055, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Explicit routes for the few moments that need stronger continuity than the
/// standard platform route (detail opening and major journey completion).
abstract final class YCRoutes {
  static Route<T> standard<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) => PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: YCMotion.navigation,
    reverseTransitionDuration: YCMotion.component,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: YCMotion.standard,
        reverseCurve: YCMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.055, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );

  static Route<T> detail<T>({required WidgetBuilder builder}) =>
      PageRouteBuilder<T>(
        transitionDuration: YCMotion.navigation,
        reverseTransitionDuration: YCMotion.component,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: YCMotion.emphasized,
            reverseCurve: YCMotion.exit,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: .975, end: 1).animate(curved),
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          );
        },
      );

  static Route<T> journey<T>({required WidgetBuilder builder}) =>
      PageRouteBuilder<T>(
        transitionDuration: YCMotion.journey,
        reverseTransitionDuration: YCMotion.navigation,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: YCMotion.emphasized,
            reverseCurve: YCMotion.exit,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .035),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}
