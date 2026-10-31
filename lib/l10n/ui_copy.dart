// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'app_localizations.dart';

part 'ui_copy_catalog.g.dart';

/// Localizes legacy application copy through the normal ARB resources.
///
/// Only use this for application-owned labels and messages. Router names,
/// SSIDs, interface identifiers, YAML, commands and diagnostic logs are data
/// and must be rendered without this adapter.
String localizeUiCopy(BuildContext context, String text) {
  final l10n = AppLocalizations.of(context);
  if (l10n == null || l10n.localeName.startsWith('en')) return text;
  final catalog = _catalogs.putIfAbsent(
    l10n.localeName,
    () => _buildUiCopyCatalog(l10n),
  );
  return catalog.translate(text);
}

final _catalogs = <String, _UiCopyCatalog>{};

String _localizeUiKeyword(AppLocalizations l10n, String keyword) =>
    _catalogs[l10n.localeName]?.translate(keyword) ?? keyword;

/// Formats the label of a physical radio without changing its UCI identifier.
String localizeRadioName(BuildContext context, String identifier) {
  final match = RegExp(r'^radio(\d+)$', caseSensitive: false).firstMatch(identifier);
  if (match == null) return identifier;
  final l10n = AppLocalizations.of(context);
  if (l10n == null || l10n.localeName.startsWith('en')) {
    return identifier.toUpperCase();
  }
  return localizeUiCopy(context, 'Radio ${match.group(1)}');
}

class _UiCopyCatalog {
  final Map<String, String> exact;
  final Map<String, List<_UiCopyRule>> _rules = {};

  _UiCopyCatalog(this.exact, List<_UiCopyRule> rules) {
    for (final rule in rules) {
      final word = _firstWord(rule.template);
      (_rules[word] ??= []).add(rule);
    }
  }

  static String _firstWord(String text) =>
      RegExp(r'^[A-Za-z][A-Za-z-]*').firstMatch(text)?.group(0) ?? '';

  String translate(String text) {
    final direct = exact[text];
    if (direct != null) return direct;
    final word = _firstWord(text);
    for (final rule in _rules[word] ?? const <_UiCopyRule>[]) {
      final translated = rule.translate(text);
      if (translated != null) return translated;
    }
    if (word.isNotEmpty) {
      for (final rule in _rules[''] ?? const <_UiCopyRule>[]) {
        final translated = rule.translate(text);
        if (translated != null) return translated;
      }
    }
    return text;
  }
}

class _UiCopyRule {
  final String template;
  final String? Function(List<String>) resolve;
  RegExp? _pattern;

  _UiCopyRule(this.template, this.resolve);

  String? translate(String text) {
    _pattern ??= RegExp(
      '^${template.split(RegExp(r'\{\w+\}')).map(RegExp.escape).join(r'([\s\S]*?)')}\$',
    );
    final match = _pattern!.firstMatch(text);
    if (match == null) return null;
    return resolve([
      for (var index = 1; index <= match.groupCount; index++)
        match.group(index)!,
    ]);
  }
}

/// Keeps the existing Text layout and const call sites while localizing fixed
/// application copy at build time, including after an in-app language change.
class LocalizedUiText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const LocalizedUiText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  @override
  Widget build(BuildContext context) => Text(
    localizeUiCopy(context, data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel,
    semanticsIdentifier: semanticsIdentifier,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}

extension LocalizedUiDecoration on InputDecoration {
  InputDecoration localized(BuildContext context) => copyWith(
    labelText: labelText == null ? null : localizeUiCopy(context, labelText!),
    hintText: hintText == null ? null : localizeUiCopy(context, hintText!),
    helperText: helperText == null ? null : localizeUiCopy(context, helperText!),
    errorText: errorText == null ? null : localizeUiCopy(context, errorText!),
  );
}

FormFieldValidator<T>? localizeUiValidator<T>(
  BuildContext context,
  FormFieldValidator<T>? validator,
) {
  if (validator == null) return null;
  return (value) {
    final message = validator(value);
    return message == null ? null : localizeUiCopy(context, message);
  };
}
