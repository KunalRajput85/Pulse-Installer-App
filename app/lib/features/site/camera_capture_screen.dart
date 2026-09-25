import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models/models.dart';
import '../../core/models/survey.dart';
import '../../core/utils/hashing.dart';
import '../branding/brand.dart';

/// Full-screen live camera. Gallery access is never offered, satisfying the
/// "Live Camera Capture Only" requirement (RM Pulse Section 3). Honours the
/// control's `cam_type` (front/back) and `subtype` (caption capture mode).
///
/// Returns a [CapturedPhoto] (with SHA-256 for duplicate detection) or null.
class CameraCaptureScreen extends StatefulWidget {
  final Control control;
  final bool liveCameraOnly;

  const CameraCaptureScreen({
    super.key,
    required this.control,
    required this.liveCameraOnly,
  });

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras();
      final wantBack = widget.control.camType == 2;
      final cam = _cameras.firstWhere(
        (c) => wantBack
            ? c.lensDirection == CameraLensDirection.back
            : c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      // Medium resolution keeps memory + file size low so capture works on
      // old / low-RAM phones and photos upload quickly on weak networks.
      final controller =
          CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
      // Copy the shot out of the camera's temp/cache dir into app documents so
      // it can NEVER be lost before it uploads (the OS may clear the cache dir).
      final durablePath = await _persist(file.path, uniqueId);
      final hash = await Hashing.sha256OfFile(durablePath);
      String? caption;
      if (widget.control.subtype != 0) {
        caption = await _askCaption();
      }
      if (!mounted) return;
      Navigator.of(context).pop(CapturedPhoto(
        // JSON control id (wireId) — this is what file.php stores as quesId so it
        // matches the quesId in the data.php survey payload. The photos map is
        // still keyed by the namespaced control.id via addPhoto().
        controlId: widget.control.wireId,
        localPath: durablePath,
        sha256: hash,
        caption: caption,
        capturedAt: DateTime.now(),
        // Epoch-millis id (matches the server's fileUniqueId format).
        fileUniqueId: uniqueId,
      ));
    } catch (e) {
      setState(() {
        _error = 'Capture failed: $e';
        _busy = false;
      });
    }
  }

  /// Copies a freshly captured photo into a persistent app-documents folder so
  /// it survives cache clearing / app restarts until it has been uploaded.
  Future<String> _persist(String srcPath, String uniqueId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'rm_captures'));
      if (!await folder.exists()) await folder.create(recursive: true);
      final dest = p.join(folder.path, '$uniqueId.jpg');
      await File(srcPath).copy(dest);
      return dest;
    } catch (_) {
      // If the copy fails for any reason, fall back to the original path.
      return srcPath;
    }
  }

  /// Caption capture per `subtype` (1 radio, 2 checkbox, 3 dropdown, 4 text).
  Future<String?> _askCaption() async {
    final opts = widget.control.options;
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        String? sel;
        final textCtrl = TextEditingController();
        return AlertDialog(
          title: const Text('Add caption'),
          content: widget.control.subtype == 4
              ? TextField(
                  controller: textCtrl,
                  decoration: const InputDecoration(hintText: 'Enter caption'),
                )
              : StatefulBuilder(
                  builder: (_, setInner) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: opts
                        .map((o) => RadioListTile<String>(
                              title: Text(o),
                              value: o,
                              groupValue: sel,
                              onChanged: (v) => setInner(() => sel = v),
                            ))
                        .toList(),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                  ctx, widget.control.subtype == 4 ? textCtrl.text : sel),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
            widget.control.labelFor(context.read<AppState>().strings.lang),
            style: const TextStyle(fontSize: 15)),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center),
              ),
            )
          : _controller == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(child: CameraPreview(_controller!)),
                          // "LIVE" indicator pill.
                          Positioned(
                            top: 14,
                            left: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.fiber_manual_record,
                                      size: 10, color: Color(0xFFFF5A5A)),
                                  SizedBox(width: 6),
                                  Text('LIVE',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.only(top: 16, bottom: 26),
                      color: Colors.black,
                      child: Column(
                        children: [
                          const Text('Hold steady • Live camera only',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          const SizedBox(height: 14),
                          GestureDetector(
                            onTap: _busy ? null : _capture,
                            child: Container(
                              width: 78,
                              height: 78,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: Brand.accentGradient,
                              ),
                              padding: const EdgeInsets.all(5),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                      color: Colors.white24, width: 3),
                                ),
                                child: _busy
                                    ? const Padding(
                                        padding: EdgeInsets.all(20),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 3),
                                      )
                                    : const Icon(Icons.camera_alt,
                                        size: 32, color: Brand.royalBlue),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
