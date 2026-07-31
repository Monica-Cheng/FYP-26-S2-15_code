// lib/utils/widget_capture.dart
// Shared off-tree "render this widget to PNG bytes" helper. Both
// post_session_summary_screen.dart's old _captureAndShare() and
// nutrition_scan_screen.dart's old _shareResult() built this exact
// RenderRepaintBoundary/RenderView/PipelineOwner technique independently
// — extracted here once both are wired through the shared card-picker
// flow (see widgets/share_card_picker.dart) so the logic exists once.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

Future<Uint8List?> captureWidgetAsPngBytes(
  BuildContext context,
  Widget widget, {
  required Size size,
  double pixelRatio = 3.0,
}) async {
  final repaintBoundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: View.of(context),
    child: RenderPositionedBox(
      alignment: Alignment.topLeft,
      child: repaintBoundary,
    ),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: pixelRatio,
    ),
  );

  final pipelineOwner = PipelineOwner();
  final buildOwner = BuildOwner(focusManager: FocusManager());

  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();

  final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
    container: repaintBoundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData.fromView(View.of(context)),
        child: widget,
      ),
    ),
  ).attachToRenderTree(buildOwner);

  buildOwner.buildScope(rootElement);
  buildOwner.finalizeTree();

  pipelineOwner.flushLayout();
  pipelineOwner.flushCompositingBits();
  pipelineOwner.flushPaint();

  final image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}
