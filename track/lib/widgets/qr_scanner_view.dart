import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera preview with a scanning frame, torch, camera switch, zoom slider and
/// tap-to-focus. Reports QR payloads through [onDetect]; it performs no
/// validation or networking itself.
class QrScannerView extends StatefulWidget {
  const QrScannerView({
    super.key,
    required this.onDetect,
    this.onPermissionDenied,
    this.autoZoom = false,
    this.busy = false,
  });

  /// Called with the raw payloads of every QR code seen in one frame.
  final ValueChanged<List<String>> onDetect;
  final VoidCallback? onPermissionDenied;
  final bool autoZoom;

  /// Shows a "submitting" badge over the preview.
  final bool busy;

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    autoZoom: widget.autoZoom,
  );

  Offset? _focusIndicator;
  Timer? _focusTimer;
  bool _reportedPermissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onScannerStateChanged);
  }

  // A provided controller is not managed by MobileScanner, so pause the
  // camera when the app is backgrounded and resume afterwards.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        unawaited(_safely(_controller.start));
      case AppLifecycleState.inactive:
        unawaited(_safely(_controller.stop));
    }
  }

  void _onScannerStateChanged() {
    final denied =
        _controller.value.error?.errorCode ==
        MobileScannerErrorCode.permissionDenied;
    if (denied && !_reportedPermissionDenied) {
      _reportedPermissionDenied = true;
      widget.onPermissionDenied?.call();
    } else if (!denied) {
      _reportedPermissionDenied = false;
    }
  }

  void _handleCapture(BarcodeCapture capture) {
    final payloads = capture.barcodes
        .where((b) => b.format == BarcodeFormat.qrCode)
        .map((b) => b.rawValue ?? '')
        .toList();
    if (payloads.isNotEmpty) widget.onDetect(payloads);
  }

  Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } on MobileScannerException catch (e) {
      debugPrint('Scanner action failed: ${e.errorCode}');
    } catch (e) {
      debugPrint('Scanner action failed: $e');
    }
  }

  void _focusAt(Offset localPosition, Size size) {
    if (!_controller.value.isRunning) return;
    unawaited(
      _safely(
        () => _controller.setFocusPoint(
          Offset(localPosition.dx / size.width, localPosition.dy / size.height),
        ),
      ),
    );
    setState(() => _focusIndicator = localPosition);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _focusIndicator = null);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onScannerStateChanged);
    _focusTimer?.cancel();
    super.dispose();
    unawaited(_controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final frameSize = (size.shortestSide * 0.68).clamp(140.0, 340.0);
            return Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _focusAt(d.localPosition, size),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _handleCapture,
                    fit: BoxFit.cover,
                    placeholderBuilder: (_) => const _CameraMessage(
                      icon: null,
                      title: 'Starting camera…',
                    ),
                    errorBuilder: (context, error) => _ScannerError(
                      error: error,
                      onRetry: () => _safely(_controller.start),
                    ),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: _controller,
                  builder: (context, state, _) {
                    if (!state.isRunning || state.error != null) {
                      return const SizedBox.shrink();
                    }
                    return IgnorePointer(
                      child: CustomPaint(
                        painter: _ScanFramePainter(
                          frameSize: frameSize,
                          color: widget.busy
                              ? Colors.amberAccent
                              : Colors.white,
                        ),
                      ),
                    );
                  },
                ),
                if (_focusIndicator != null)
                  Positioned(
                    left: _focusIndicator!.dx - 28,
                    top: _focusIndicator!.dy - 28,
                    child: IgnorePointer(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.amberAccent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: IgnorePointer(
                    child: Center(
                      child: _Pill(
                        icon: widget.busy
                            ? Icons.cloud_upload_outlined
                            : Icons.qr_code_scanner,
                        text: widget.busy
                            ? 'Submitting…'
                            : 'Align the QR code inside the frame.',
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _ScannerControls(controller: _controller),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScannerControls extends StatelessWidget {
  const _ScannerControls({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        if (!state.isInitialized || !state.isRunning || state.error != null) {
          return const SizedBox.shrink();
        }
        final torchAvailable = state.torchState != TorchState.unavailable;
        final torchOn = state.torchState == TorchState.on;
        final canSwitch =
            state.availableCameras == null || state.availableCameras! > 1;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: torchOn
                      ? 'Turn flashlight off'
                      : 'Turn flashlight on',
                  color: torchOn ? Colors.amberAccent : Colors.white,
                  disabledColor: Colors.white38,
                  onPressed: torchAvailable
                      ? () => _ignoreErrors(controller.toggleTorch())
                      : null,
                  icon: Icon(
                    torchAvailable
                        ? (torchOn ? Icons.flash_on : Icons.flash_off)
                        : Icons.no_flash,
                  ),
                ),
                const Icon(Icons.zoom_out, color: Colors.white70, size: 18),
                Expanded(
                  child: Slider(
                    // 0.0–1.0 maps to the device's own min..max zoom range.
                    value: state.zoomScale.clamp(0.0, 1.0),
                    onChanged: (v) => _ignoreErrors(controller.setZoomScale(v)),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    semanticFormatterCallback: (v) =>
                        'Zoom ${(v * 100).round()} percent',
                  ),
                ),
                const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
                if (canSwitch)
                  IconButton(
                    tooltip: 'Switch camera',
                    color: Colors.white,
                    onPressed: () => _ignoreErrors(controller.switchCamera()),
                    icon: const Icon(Icons.cameraswitch_outlined),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Camera control calls can fail if the camera stops mid-gesture; the
/// scanner state already reflects any real error, so these are only logged.
void _ignoreErrors(Future<void> action) {
  unawaited(
    action.catchError((Object e) => debugPrint('Scanner control failed: $e')),
  );
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error, required this.onRetry});

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      String title,
      String detail,
    ) = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => (
        Icons.no_photography_outlined,
        'Camera permission denied',
        'The scanner needs the camera to read QR codes. Allow camera access '
            'for this app in system settings, then tap Try again. You can '
            'still type registration numbers below.',
      ),
      MobileScannerErrorCode.unsupported => (
        Icons.videocam_off_outlined,
        'Camera not available',
        'This device does not support camera scanning. Use manual entry below.',
      ),
      _ => (
        Icons.error_outline,
        'Camera could not start',
        'Another app may be using the camera. Close it and try again.',
      ),
    };
    return _CameraMessage(
      icon: icon,
      title: title,
      detail: detail,
      action: error.errorCode == MobileScannerErrorCode.unsupported
          ? null
          : FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });

  final IconData? icon;
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon == null)
                const CircularProgressIndicator(color: Colors.white)
              else
                Icon(icon, color: Colors.white, size: 40),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(
                  detail!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims the preview outside a centred square and draws corner brackets.
class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({required this.frameSize, required this.color});

  final double frameSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: frameSize,
      height: frameSize,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rrect),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    final corners = [
      (rect.topLeft, const Offset(1, 0), const Offset(0, 1)),
      (rect.topRight, const Offset(-1, 0), const Offset(0, 1)),
      (rect.bottomLeft, const Offset(1, 0), const Offset(0, -1)),
      (rect.bottomRight, const Offset(-1, 0), const Offset(0, -1)),
    ];
    for (final (point, h, v) in corners) {
      canvas.drawLine(point, point + h * len, paint);
      canvas.drawLine(point, point + v * len, paint);
    }
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) =>
      old.frameSize != frameSize || old.color != color;
}
