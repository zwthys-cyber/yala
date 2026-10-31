// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/openclash_screen.dart';

class OpenClashModule extends LuciModule {
  @override
  String get id => 'openclash';
  @override
  String get name => 'OpenClash';
  @override
  String get description => 'Proxy status, service controls, modes and nodes';
  @override
  IconData get icon => Icons.public;
  @override
  LuciModuleCategory get category => LuciModuleCategory.services;
  @override
  int get priority => 35;
  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) =>
      const OpenClashScreen();
}
