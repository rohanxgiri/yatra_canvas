import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Exercise the real compiled shader and its logical-pixel displacement on
  // Skia's canvas path. This does NOT substitute for Impeller backdrop/device QA.
  for (final density in [1, 3]) {
    test(
      'glass shader: actual edge lensing, clear center, density $density',
      () async {
        final width = 200 * density;
        final height = 80 * density;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        for (var x = 0; x < width; x++) {
          canvas.drawRect(
            ui.Rect.fromLTWH(x.toDouble(), 0, 1, height.toDouble()),
            ui.Paint()
              ..color = ui.Color.fromARGB(
                255,
                (x * 255 / width).round(),
                80,
                150,
              ),
          );
        }
        final picture = recorder.endRecording();
        final input = await picture.toImage(width, height);
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/yatra_refractive_glass.frag',
        );
        final shader = program.fragmentShader()
          ..setFloat(0, width.toDouble())
          ..setFloat(1, height.toDouble())
          ..setFloat(2, 200)
          ..setFloat(3, 80)
          ..setFloat(4, 24)
          ..setFloat(5, 3)
          ..setFloat(6, 1.2)
          ..setImageSampler(0, input);
        final outputRecorder = ui.PictureRecorder();
        ui.Canvas(outputRecorder).drawRect(
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..shader = shader,
        );
        final outputPicture = outputRecorder.endRecording();
        final output = await outputPicture.toImage(width, height);
        final bytes = (await output.toByteData())!;
        final original = (await input.toByteData())!;
        int red(int x, int y) =>
            bytes.getUint8(((y * density) * width + x * density) * 4);
        int originalRed(int x, int y) =>
            original.getUint8(((y * density) * width + x * density) * 4);
        // Left edge samples inward (higher red), right edge samples inward (lower).
        expect(red(1, 40) - originalRed(1, 40), inInclusiveRange(2, 6));
        expect(originalRed(198, 40) - red(198, 40), inInclusiveRange(2, 6));
        expect(
          (red(100, 40) - originalRed(100, 40)).abs(),
          lessThanOrEqualTo(1),
        );
        expect(
          bytes.getUint8((40 * density * width + 100 * density) * 4 + 3),
          255,
        );
        output.dispose();
        outputPicture.dispose();
        shader.dispose();
        input.dispose();
        picture.dispose();
      },
    );
  }
}
