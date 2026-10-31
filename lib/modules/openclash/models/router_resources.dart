// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

class RouterResources {
  final int totalKiB;
  final int? availableKiB;
  final int swapTotalKiB;
  final int swapFreeKiB;
  final int? zramOriginalBytes;
  final int? zramPhysicalBytes;
  final String load;

  const RouterResources({
    required this.totalKiB,
    required this.availableKiB,
    required this.swapTotalKiB,
    required this.swapFreeKiB,
    required this.zramOriginalBytes,
    required this.zramPhysicalBytes,
    required this.load,
  });

  factory RouterResources.parse(String text) {
    final sections = text.split('\nYALA_ZRAM_V1\n');
    if (!text.startsWith('YALA_RESOURCE_V1\n') || sections.length != 2) {
      throw const FormatException('Invalid resource snapshot');
    }
    final memory = <String, int>{};
    for (final match in RegExp(
      r'^(\w+):\s+(\d+) kB$',
      multiLine: true,
    ).allMatches(sections.first)) {
      memory[match[1]!] = int.parse(match[2]!);
    }
    final total = memory['MemTotal'] ?? 0;
    if (total <= 0) throw const FormatException('Missing memory total');
    final rest = sections.last.split('\nYALA_LOAD_V1\n');
    if (rest.length != 2) {
      throw const FormatException('Missing load section');
    }
    final zram = rest.first.trim().split(RegExp(r'\s+'));
    return RouterResources(
      totalKiB: total,
      availableKiB: memory['MemAvailable'],
      swapTotalKiB: memory['SwapTotal'] ?? 0,
      swapFreeKiB: memory['SwapFree'] ?? 0,
      zramOriginalBytes: zram.length >= 3 ? int.tryParse(zram[0]) : null,
      zramPhysicalBytes: zram.length >= 3 ? int.tryParse(zram[2]) : null,
      load: rest.last.trim(),
    );
  }
}
