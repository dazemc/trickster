import 'dart:math' show max, min;

import 'package:flutter/rendering.dart'
    show
        BoxConstraints,
        BoxHitTestResult,
        ContainerBoxParentData,
        ContainerRenderObjectMixin,
        PaintingContext,
        RenderBox,
        RenderBoxContainerDefaultsMixin;
import 'package:flutter/widgets.dart';

/// Packs children into rows (columns on vertical strips) without flattening
/// their natural size. A child that fits the main axis keeps its natural
/// width and fills the band's cross extent; a child that overgrows the main
/// axis is re-laid with a bounded main axis and an unbounded cross axis so it
/// can wrap internally and report the taller band it needs.
class BarFlow extends MultiChildRenderObjectWidget {
  const BarFlow({
    required this.horizontal,
    required this.alignment,
    this.spacing = 4,
    this.crossExtent,
    super.children,
    super.key,
  });

  final bool horizontal;
  final MainAxisAlignment alignment;
  final double spacing;

  /// The band a fitting child fills (the strip's current cross extent).
  /// Null uses the bounded cross constraint, or the child's natural size.
  final double? crossExtent;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderBarFlow(
    horizontal: horizontal,
    alignment: alignment,
    spacing: spacing,
    crossExtent: crossExtent,
  );

  @override
  void updateRenderObject(BuildContext context, RenderBarFlow renderObject) {
    renderObject
      ..horizontal = horizontal
      ..alignment = alignment
      ..spacing = spacing
      ..crossExtent = crossExtent;
  }
}

class _BarFlowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderBarFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BarFlowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BarFlowParentData> {
  RenderBarFlow({
    required this.horizontal,
    required this.alignment,
    required this.spacing,
    this.crossExtent,
  });

  bool horizontal;
  MainAxisAlignment alignment;
  double spacing;
  double? crossExtent;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BarFlowParentData) {
      child.parentData = _BarFlowParentData();
    }
  }

  @override
  void performLayout() {
    final mainMax = horizontal ? constraints.maxWidth : constraints.maxHeight;
    final boundedCross = horizontal
        ? constraints.maxHeight
        : constraints.maxWidth;
    final band = crossExtent ?? (boundedCross.isFinite ? boundedCross : null);

    final runs = <List<RenderBox>>[];
    var current = <RenderBox>[];
    var currentMain = 0.0;
    var widest = 0.0;

    void closeRun() {
      if (current.isEmpty) {
        return;
      }
      runs.add(current);
      widest = max(widest, currentMain);
      current = <RenderBox>[];
      currentMain = 0;
    }

    var child = firstChild;
    while (child != null) {
      // Natural pass: unbounded main, band-bound cross, so a pill keeps its
      // width and fills the band.
      child.layout(
        horizontal
            ? BoxConstraints(maxHeight: band ?? double.infinity)
            : BoxConstraints(maxWidth: band ?? double.infinity),
        parentUsesSize: true,
      );
      final naturalMain = horizontal ? child.size.width : child.size.height;
      if (mainMax.isFinite && naturalMain > mainMax) {
        // Overgrown module: give it the full main budget with an unbounded
        // cross so it wraps internally and reports the taller band it needs.
        child.layout(
          horizontal
              ? BoxConstraints(maxWidth: mainMax)
              : BoxConstraints(maxHeight: mainMax),
          parentUsesSize: true,
        );
        closeRun();
        current.add(child);
        currentMain = horizontal ? child.size.width : child.size.height;
        closeRun();
      } else {
        if (current.isNotEmpty &&
            currentMain + spacing + naturalMain > mainMax) {
          closeRun();
        }
        if (current.isNotEmpty) {
          currentMain += spacing;
        }
        current.add(child);
        currentMain += naturalMain;
      }
      child = childAfter(child);
    }
    closeRun();

    var totalCross = 0.0;
    for (var i = 0; i < runs.length; i++) {
      totalCross += _runCross(runs[i]);
      if (i != runs.length - 1) {
        totalCross += spacing;
      }
    }

    final mainSize = min(widest, mainMax);
    size = constraints.constrain(
      horizontal ? Size(mainSize, totalCross) : Size(totalCross, mainSize),
    );

    var runOffset = 0.0;
    for (final run in runs) {
      final runCross = _runCross(run);
      var runMain = 0.0;
      for (final box in run) {
        runMain += horizontal ? box.size.width : box.size.height;
      }
      runMain += (run.length - 1) * spacing;
      var offset = switch (alignment) {
        MainAxisAlignment.end =>
          (horizontal ? size.width : size.height) - runMain,
        MainAxisAlignment.center =>
          ((horizontal ? size.width : size.height) - runMain) / 2,
        _ => 0.0,
      };
      for (final box in run) {
        final boxMain = horizontal ? box.size.width : box.size.height;
        final boxCross = horizontal ? box.size.height : box.size.width;
        final parentData = box.parentData! as _BarFlowParentData;
        parentData.offset = horizontal
            ? Offset(offset, runOffset + (runCross - boxCross) / 2)
            : Offset(runOffset + (runCross - boxCross) / 2, offset);
        offset += boxMain + spacing;
      }
      runOffset += runCross + spacing;
    }
  }

  double _runCross(List<RenderBox> run) {
    var cross = 0.0;
    for (final box in run) {
      cross = max(cross, horizontal ? box.size.height : box.size.width);
    }
    return cross;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
