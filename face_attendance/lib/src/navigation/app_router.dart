import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';

RouterConfig<Object> buildRouter() {
  return RouterConfig<Object>(
    routerDelegate: _AppRouterDelegate(),
    routeInformationParser: _AppRouteParser(),
    routeInformationProvider: PlatformRouteInformationProvider(
      initialRouteInformation: const RouteInformation(location: '/'),
    ),
  );
}

class _AppRouteParser extends RouteInformationParser<List<String>> {
  @override
  Future<List<String>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final String location = routeInformation.location ?? '/';
    final Uri uri = Uri.parse(location);
    return uri.pathSegments;
  }
}

class _AppRouterDelegate extends RouterDelegate<List<String>>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<List<String>> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  List<String> _segments = const [];

  @override
  List<String>? get currentConfiguration => _segments;

  @override
  Future<void> setNewRoutePath(List<String> configuration) async {
    _segments = configuration;
  }

  void _goTo(String path) {
    _segments = path == '/' ? const [] : path.split('/').where((e) => e.isNotEmpty).toList();
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    final bool isSettings = _segments.isNotEmpty && _segments.first == 'settings';
    return Navigator(
      key: navigatorKey,
      pages: [
        MaterialPage(
          key: const ValueKey('home'),
          child: HomeScreen(
            onOpenSettings: () => _goTo('/settings'),
          ),
        ),
        if (isSettings)
          MaterialPage(
            key: const ValueKey('settings'),
            child: const SettingsScreen(),
          ),
      ],
      onPopPage: (route, result) {
        if (!route.didPop(result)) {
          return false;
        }
        if (_segments.isNotEmpty) {
          _segments = const [];
          notifyListeners();
        }
        return true;
      },
    );
  }
}


