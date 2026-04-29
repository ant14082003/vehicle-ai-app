import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';

class UploadDocumentScreen extends StatefulWidget {
  /// null  → RC upload flow  → calls /process (single image only)
  /// set   → Insurance/PUC   → calls /add-document (multi-image)
  final String? vehicleNumber;
  final String? docType;

  const UploadDocumentScreen({super.key, this.vehicleNumber, this.docType});

  @override
  State<UploadDocumentScreen> createState() => _UploadDocumentScreenState();
}

class _UploadDocumentScreenState extends State<UploadDocumentScreen> {
  static const String baseUrl = "http://127.0.0.1:8000";
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false;
  String _uploadStatus = "";

  // For multi-image flow — stores preview info before sending
  final List<_ImageEntry> _selectedImages = [];

  bool get _isRCFlow => widget.vehicleNumber == null;

  // ── Firebase upload ────────────────────────────────────────────────────────
  Future<String> _uploadToFirebase(Uint8List bytes, String extension) async {
    final ref = FirebaseStorage.instance.ref().child(
      "documents/${DateTime.now().millisecondsSinceEpoch}_${_selectedImages.length}.$extension",
    );
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  // ── Camera ─────────────────────────────────────────────────────────────────
  Future<void> _openCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (_isRCFlow) {
      // RC: upload immediately
      await _uploadSingleAndProcess(bytes, "jpg");
    } else {
      // Insurance/PUC: add to staging list
      setState(() {
        _selectedImages.add(_ImageEntry(bytes: bytes, extension: "jpg"));
      });
    }
  }

  // ── File picker ────────────────────────────────────────────────────────────
  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
      allowMultiple: !_isRCFlow, // multi-select only for Insurance/PUC
    );
    if (result == null) return;

    if (_isRCFlow) {
      final file = result.files.first;
      await _uploadSingleAndProcess(file.bytes!, file.extension ?? "jpg");
    } else {
      // Add all picked files to staging
      setState(() {
        for (final file in result.files) {
          _selectedImages.add(
            _ImageEntry(bytes: file.bytes!, extension: file.extension ?? "jpg"),
          );
        }
      });
    }
  }

  // ── RC: upload single image and call /process immediately ─────────────────
  Future<void> _uploadSingleAndProcess(
    Uint8List bytes,
    String extension,
  ) async {
    setState(() {
      _isUploading = true;
      _uploadStatus = "Uploading to storage...";
    });
    try {
      final url = await _uploadToFirebase(bytes, extension);
      setState(() => _uploadStatus = "Processing with OCR...");
      await _sendRCToBackend(url);
    } catch (e) {
      _showSnack("Upload failed: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _sendRCToBackend(String url) async {
    final res = await http.post(
      Uri.parse("$baseUrl/process"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"imageUrl": url}),
    );
    final data = jsonDecode(res.body);
    if (!mounted) return;
    _showSnack(data["message"] ?? "Done");
    final isSuccess =
        (data["vehicle_saved"] == true ||
        (data["message"] as String? ?? "").toLowerCase().contains("created"));
    if (isSuccess && mounted) Navigator.pop(context, true);
  }

  // ── Insurance/PUC: upload all staged images and call /add-document ─────────
  Future<void> _submitAllImages() async {
    if (_selectedImages.isEmpty) {
      _showSnack("Please add at least one image");
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = "Uploading ${_selectedImages.length} image(s)...";
    });

    try {
      // Upload all to Firebase
      final List<String> uploadedUrls = [];
      for (int i = 0; i < _selectedImages.length; i++) {
        setState(
          () => _uploadStatus =
              "Uploading image ${i + 1} of ${_selectedImages.length}...",
        );
        final url = await _uploadToFirebase(
          _selectedImages[i].bytes,
          _selectedImages[i].extension,
        );
        uploadedUrls.add(url);
      }

      setState(() => _uploadStatus = "Extracting data with OCR...");

      // Send all URLs to backend
      final res = await http.post(
        Uri.parse("$baseUrl/add-document"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "imageUrls": uploadedUrls,
          "vehicleNumber": widget.vehicleNumber,
          "docType": widget.docType ?? "OTHER",
        }),
      );

      final data = jsonDecode(res.body);
      final message = data["message"] as String? ?? "Done";
      final expiry = data["expiry_date"] as String?;
      final pages = data["page_count"] as int? ?? uploadedUrls.length;

      if (!mounted) return;

      // Schedule notification if expiry extracted
      if (expiry != null &&
          expiry.isNotEmpty &&
          widget.vehicleNumber != null &&
          widget.docType != null) {
        await NotificationService.instance.scheduleDocumentReminders(
          vehicleNumber: widget.vehicleNumber!,
          docType: widget.docType!,
          expiryDateStr: expiry,
        );
      }

      _showSnack(
        expiry != null
            ? "$message\nExpiry: $expiry  ·  $pages page(s)"
            : "$message  ·  $pages page(s)",
      );

      final isSuccess =
          message.toLowerCase().contains("added") ||
          message.toLowerCase().contains("success");
      if (isSuccess && mounted) Navigator.pop(context, true);
    } catch (e) {
      _showSnack("Error: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final title = _isRCFlow
        ? "Upload RC"
        : "Upload ${widget.docType ?? 'Document'}";

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppTheme.bg,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          ),
        ),
      ),
      body: _isUploading
          ? _buildLoadingState()
          : _isRCFlow
          ? _buildRCUploadUI()
          : _buildMultiImageUI(),
    );
  }

  // ── Loading state ──────────────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: AppTheme.accent,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _uploadStatus,
            style: AppTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text("Please don't close the app", style: AppTheme.labelSmall),
        ],
      ),
    );
  }

  // ── RC Upload UI — single image, simple ────────────────────────────────────
  Widget _buildRCUploadUI() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: AppTheme.cardDecoration,
            child: Column(
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 64,
                  color: AppTheme.accent.withOpacity(0.6),
                ),
                const SizedBox(height: 16),
                Text("Upload RC Document", style: AppTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  "Take a clear photo or upload your RC.\nAll vehicle details will be extracted automatically.",
                  style: AppTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openCamera,
            style: AppTheme.primaryButton,
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text("Take Photo"),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickFiles,
            style: AppTheme.outlineButton,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text("Choose from Device"),
          ),
          const SizedBox(height: 20),
          // Tips
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("📸  Tips for best results", style: AppTheme.accentLabel),
                const SizedBox(height: 8),
                Text(
                  "• Ensure all text is clearly visible",
                  style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                ),
                Text(
                  "• Good lighting, avoid shadows",
                  style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                ),
                Text(
                  "• Keep the document flat",
                  style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Multi-image UI — for Insurance/PUC ────────────────────────────────────
  Widget _buildMultiImageUI() {
    return Column(
      children: [
        // Info banner
        Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppTheme.accent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Add all pages of your ${widget.docType}. "
                  "You can upload multiple photos if the document spans more than one page.",
                  style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ),

        // Image grid
        Expanded(
          child: _selectedImages.isEmpty
              ? _buildEmptyImageState()
              : _buildImageGrid(),
        ),

        // Bottom action bar
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildEmptyImageState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.border, width: 2),
            ),
            child: Icon(
              Icons.add_photo_alternate_rounded,
              size: 36,
              color: AppTheme.accent.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          Text("No images added yet", style: AppTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            "Add photos of your ${widget.docType} below",
            style: AppTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: _selectedImages.length,
      itemBuilder: (_, index) {
        final entry = _selectedImages[index];
        return Container(
          decoration: AppTheme.cardDecoration,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image preview
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.memory(entry.bytes, fit: BoxFit.cover),
              ),
              // Page number badge
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.bg.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                  ),
                  child: Text(
                    "Page ${index + 1}",
                    style: AppTheme.accentLabel.copyWith(fontSize: 10),
                  ),
                ),
              ),
              // Remove button
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => _removeImage(index),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          // Page counter
          if (_selectedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.layers_rounded, color: AppTheme.accent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "${_selectedImages.length} page(s) added",
                    style: AppTheme.accentLabel,
                  ),
                ],
              ),
            ),

          // Add more buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openCamera,
                  style: AppTheme.outlineButton.copyWith(
                    padding: const MaterialStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt_rounded, size: 16),
                  label: const Text("Camera"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFiles,
                  style: AppTheme.outlineButton.copyWith(
                    padding: const MaterialStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text("Files"),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _selectedImages.isEmpty ? null : _submitAllImages,
              style: AppTheme.primaryButton,
              icon: const Icon(Icons.cloud_upload_rounded, size: 20),
              label: Text(
                _selectedImages.isEmpty
                    ? "Add images first"
                    : "Upload ${_selectedImages.length} Page(s)",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Holds a staged image before uploading to Firebase
class _ImageEntry {
  final Uint8List bytes;
  final String extension;
  _ImageEntry({required this.bytes, required this.extension});
}
