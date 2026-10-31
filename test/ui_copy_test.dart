// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/l10n/ui_copy.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/wireless_interface_card.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';

Widget app(Widget child, {Locale locale = const Locale('zh')}) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('Chinese wireless card translates copy and preserves SSID and IDs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const iface = WirelessInterface(
      ifName: 'phy1-ap0',
      sectionName: 'default_radio1',
      ssid: 'More Options',
      mode: 'MASTER',
      encryption: 'psk2',
      securityMode: WifiSecurityMode.wpa2Psk,
      pmfState: PmfState.optional,
      channel: '36',
      isEnabled: true,
      stations: [],
    );
    const radio = WirelessRadio(
      name: 'radio1',
      isUp: true,
      channel: '36',
      country: 'CN',
      interfaces: [iface],
    );
    await tester.pumpWidget(app(const WirelessInterfaceCard(radio: radio, interface: iface)));
    await tester.pumpAndSettle();
    expect(find.text('More Options'), findsOneWidget);
    expect(find.text('接入点'), findsOneWidget);
    expect(find.text('配置段：default_radio1（phy1-ap0）'), findsOneWidget);
    expect(find.text('MASTER'), findsNothing);
    expect(find.byTooltip('显示 Wi-Fi 二维码'), findsOneWidget);
    expect(iface.mode, 'MASTER');
    expect(radio.name, 'radio1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Interpolated copy preserves Unicode, quotes and placeholder-like data', (tester) async {
    const name = r'家里 "$1" {arg1} \ Wi-Fi';
    await tester.pumpWidget(app(const LocalizedUiText('New Guest Wi-Fi "$name" created successfully!')));
    await tester.pumpAndSettle();
    expect(find.text('已创建新的访客 Wi-Fi“$name”！'), findsOneWidget);
  });

  testWidgets('Only marked semantic action arguments are translated', (tester) async {
    await tester.pumpWidget(app(Builder(builder: (context) => Column(children: [
      LocalizedUiText('Failed to update static lease for update.'),
      Text(localizeRadioName(context, 'radio1')),
      Text(localizeRadioName(context, 'custom-radio-id')),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('为 update 执行静态租约更新操作失败。'), findsOneWidget);
    expect(find.text('射频 1'), findsOneWidget);
    expect(find.text('custom-radio-id'), findsOneWidget);
  });

  testWidgets('Existing typed ARB messages retain numeric argument order', (tester) async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    final source = en.wirelessRadioSummary('5 GHz', '36', 4, 3, 1);
    await tester.pumpWidget(app(LocalizedUiText(source)));
    await tester.pumpAndSettle();
    expect(find.text(zh.wirelessRadioSummary('5 GHz', '36', 4, 3, 1)), findsOneWidget);
  });

  testWidgets('Form labels and validators use the selected app language', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(app(Builder(builder: (context) => Form(
      key: key,
      child: TextFormField(
        decoration: (const InputDecoration(labelText: 'Guest SSID Name')).localized(context),
        validator: localizeUiValidator<String>(context, (_) => 'Guest SSID name cannot be empty'),
      ),
    ))));
    await tester.pumpAndSettle();
    expect(key.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('访客网络名称（SSID）'), findsOneWidget);
    expect(find.text('访客网络名称不能为空'), findsOneWidget);
    expect(find.text('Guest SSID name cannot be empty'), findsNothing);
  });

  testWidgets('Guardrails translate labels and keep operation results unchanged', (tester) async {
    bool? result;
    await tester.pumpWidget(app(Builder(builder: (context) => TextButton(
      onPressed: () async {
        result = await LuciGuardrail.showConfirmation(context,
          title: 'Security Downgrade Warning',
          subtitle: 'You are lowering the Wi-Fi security standard from WPA3-SAE to WPA2-PSK. This weakens encryption protection for connecting clients.',
          confirmLabel: 'Proceed with Downgrade',
        );
      },
      child: const Text('open'),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('降低安全等级提示'), findsOneWidget);
    expect(find.textContaining('WPA3-SAE'), findsOneWidget);
    await tester.tap(find.text('确认降低安全等级'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('English and unknown technical data are preserved', (tester) async {
    await tester.pumpWidget(app(const Column(children: [
      LocalizedUiText('Target Physical Radio'),
      LocalizedUiText('unmapped-device-001'),
    ]), locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Target Physical Radio'), findsOneWidget);
    expect(find.text('unmapped-device-001'), findsOneWidget);
  });

  testWidgets('Copy follows language changes without restarting the app', (tester) async {
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
      valueListenable: locale,
      builder: (_, current, _) => app(const LocalizedUiText('Target Physical Radio'), locale: current),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Target Physical Radio'), findsOneWidget);
    locale.value = const Locale('zh');
    await tester.pumpAndSettle();
    expect(find.text('目标物理射频'), findsOneWidget);
    expect(find.text('Target Physical Radio'), findsNothing);
  });
}
