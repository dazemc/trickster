import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/grim_sampler.dart';

const _redPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAQMAAACTPww9AAAAIGNIUk0AAHomAACAhAAA'
    '+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAADUExUReAwQKcCmhkAAAAHdElNRQfq'
    'CQ4CJSavvgZyAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTE0VDAyOjM3OjM4KzAw'
    'OjAwVbun3AAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0xNFQwMjozNzozOCswMDow'
    'MCTmH2AAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMTRUMDI6Mzc6MzgrMDA6'
    'MDBz8z6/AAAAC0lEQVQI12NggAAAAAgAAS8g3TEAAAAASUVORK5CYII=';

const _output = LayerOutput(name: 'HDMI-A-2', width: 2560, height: 1440);

void main() {
  test('the strip band sits beside the strip, never inside it', () {
    expect(
      stripBand(_output, SystemBarSide.top, 32),
      const Rect.fromLTWH(0, 32, 2560, 32),
    );
    expect(
      stripBand(_output, SystemBarSide.bottom, 32),
      const Rect.fromLTWH(0, 1376, 2560, 32),
    );
    expect(
      stripBand(_output, SystemBarSide.left, 32),
      const Rect.fromLTWH(32, 0, 32, 1440),
    );
    expect(
      stripBand(_output, SystemBarSide.right, 32),
      const Rect.fromLTWH(2496, 0, 32, 1440),
    );
    expect(stripBand(_output, SystemBarSide.hidden, 32), isNull);
  });

  test('a missing grim degrades to no candidates without running it', () async {
    var runs = 0;
    final sampler = GrimSampler(
      available: false,
      run: (_) async {
        runs++;
        return null;
      },
    );
    expect(
      await sampler.sample(
        output: _output,
        side: SystemBarSide.top,
        thickness: 32,
      ),
      isEmpty,
    );
    expect(runs, 0);
  });

  test('captures the band and extracts its candidates', () async {
    final commands = <List<String>>[];
    final sampler = GrimSampler(
      available: true,
      run: (args) async {
        commands.add(args);
        return base64Decode(_redPng);
      },
      extract: (_) async => const <Color>[Color(0xffe03050)],
    );
    final candidates = await sampler.sample(
      output: _output,
      side: SystemBarSide.top,
      thickness: 32,
    );
    expect(candidates, const <Color>[Color(0xffe03050)]);
    expect(
      commands.single,
      containsAllInOrder(<String>['-o', 'HDMI-A-2', '-g', '0,32 2560x32']),
    );
  });

  test('a failed capture or decode resolves to no candidates', () async {
    final failing = GrimSampler(
      available: true,
      run: (_) async => throw const ProcessException('grim', <String>[]),
    );
    expect(
      await failing.sample(
        output: _output,
        side: SystemBarSide.top,
        thickness: 32,
      ),
      isEmpty,
    );

    final undecodable = GrimSampler(
      available: true,
      run: (_) async => base64Decode(_redPng),
      extract: (_) async => throw const FormatException('nope'),
    );
    expect(
      await undecodable.sample(
        output: _output,
        side: SystemBarSide.top,
        thickness: 32,
      ),
      isEmpty,
    );
  });
}
