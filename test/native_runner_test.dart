import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// GTK copies the region into a widget's input-shape state, so the caller
/// owns its reference and must release it. A tooltip is rebuilt per open and
/// the bootstrap once per process, so an unpaired region leaks per surface.
void main() {
  final source = _withoutComments(
    File('linux/runner/my_application.cc').readAsStringSync(),
  );

  test('every cairo input region is destroyed', () {
    final creates = _count(source, 'cairo_region_create(');
    final destroys = _count(source, 'cairo_region_destroy(');
    expect(creates, greaterThan(0), reason: 'no input region is created');
    expect(
      destroys,
      creates,
      reason: 'every input region must be released by its creator',
    );
  });

  test('both click-through windows route through the helper', () {
    final helper = RegExp(
      r'static void trickster_make_click_through\(GtkWidget\* widget\)'
      r'\s*\{([^}]*)\}',
    ).firstMatch(source);
    expect(helper, isNotNull, reason: 'click-through helper not found');

    final body = helper!.group(1)!;
    expect(_count(body, 'cairo_region_create('), 1);
    expect(_count(body, 'gtk_widget_input_shape_combine_region('), 1);
    expect(_count(body, 'cairo_region_destroy('), 1);

    final outsideHelper = source.replaceFirst(helper.group(0)!, '');
    expect(
      _count(outsideHelper, 'trickster_make_click_through('),
      2,
      reason: 'the tooltip and bootstrap windows both need the helper',
    );
    expect(
      _count(outsideHelper, 'gtk_widget_input_shape_combine_region('),
      0,
      reason: 'input regions belong in the helper only',
    );
  });
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

int _count(String source, String token) {
  var count = 0;
  var index = source.indexOf(token);
  while (index != -1) {
    count++;
    index = source.indexOf(token, index + token.length);
  }
  return count;
}
