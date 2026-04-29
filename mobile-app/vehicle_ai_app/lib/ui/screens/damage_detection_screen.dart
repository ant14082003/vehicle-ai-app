import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../theme/app_theme.dart';

class DamageDetectionScreen extends StatefulWidget {
  final String vehicleNumber;
  final String vehicleModel;
  const DamageDetectionScreen({
    super.key,
    required this.vehicleNumber,
    required this.vehicleModel,
  });

  @override
  State<DamageDetectionScreen> createState() => _DamageDetectionScreenState();
}

class _DamageDetectionScreenState extends State<DamageDetectionScreen>
    with SingleTickerProviderStateMixin {
  static const String baseUrl = "http://127.0.0.1:8000";
  final ImagePicker _picker = ImagePicker();

  bool _isAnalysing = false;
  String _statusText = "";
  Map<String, dynamic>? _result;
  Uint8List? _previewBytes;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<String> _uploadToFirebase(Uint8List bytes, String ext) async {
    final ref = FirebaseStorage.instance.ref().child(
      "damage/${DateTime.now().millisecondsSinceEpoch}.$ext",
    );
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  Future<void> _pickFromCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _previewBytes = bytes);
    await _analyse(bytes, "jpg");
  }

  Future<void> _pickFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;
    final file = result.files.first;
    setState(() => _previewBytes = file.bytes);
    await _analyse(file.bytes!, file.extension ?? "jpg");
  }

  Future<void> _analyse(Uint8List bytes, String ext) async {
    setState(() {
      _isAnalysing = true;
      _result = null;
      _statusText = "Uploading image...";
    });
    try {
      final url = await _uploadToFirebase(bytes, ext);
      setState(() => _statusText = "Analysing damage with AI...");
      final res = await http.post(
        Uri.parse("$baseUrl/detect-damage"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "imageUrl": url,
          "vehicleNumber": widget.vehicleNumber,
        }),
      );
      final data = jsonDecode(res.body);
      setState(() => _result = data);
      _animController.forward(from: 0);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isAnalysing = false);
    }
  }

  Color _severityColor(String? s) {
    switch (s?.toUpperCase()) {
      case "HIGH":
        return AppTheme.danger;
      case "MEDIUM":
        return AppTheme.warning;
      case "LOW":
      case "NONE":
        return AppTheme.success;
      default:
        return AppTheme.textMuted;
    }
  }

  IconData _severityIcon(String? s) {
    switch (s?.toUpperCase()) {
      case "HIGH":
        return Icons.error_rounded;
      case "MEDIUM":
        return Icons.warning_amber_rounded;
      case "NONE":
        return Icons.check_circle_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  String _severityLabel(String? s) {
    switch (s?.toUpperCase()) {
      case "HIGH":
        return "Immediate attention needed";
      case "MEDIUM":
        return "Repair recommended soon";
      case "LOW":
        return "Minor cosmetic damage";
      case "NONE":
        return "No damage detected";
      default:
        return "Analysis complete";
    }
  }

  List<Map<String, String>> _parseSections(String text) {
    final sections = <Map<String, String>>[];
    final headers = [
      "DAMAGE DETECTED",
      "AFFECTED AREAS",
      "SEVERITY",
      "REPAIR RECOMMENDATIONS",
      "ESTIMATED PRIORITY",
    ];
    for (int i = 0; i < headers.length; i++) {
      final start = text.toUpperCase().indexOf(headers[i]);
      if (start == -1) continue;
      final cStart = text.indexOf('\n', start) + 1;
      final next = i + 1 < headers.length
          ? text.toUpperCase().indexOf(headers[i + 1])
          : -1;
      final content =
          (next != -1 ? text.substring(cStart, next) : text.substring(cStart))
              .trim();
      if (content.isNotEmpty)
        sections.add({"title": headers[i], "content": content});
    }
    if (sections.isEmpty)
      sections.add({"title": "ANALYSIS", "content": text.trim()});
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Damage Detection"),
            Text(
              widget.vehicleModel,
              style: AppTheme.bodyMedium.copyWith(fontSize: 11),
            ),
          ],
        ),
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
      body: _isAnalysing
          ? _buildLoading()
          : _result == null
          ? _buildUploadUI()
          : _buildResult(),
    );
  }

  Widget _buildLoading() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_previewBytes != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              _previewBytes!,
              height: 180,
              width: 240,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 24),
        ],
        CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
        const SizedBox(height: 16),
        Text(_statusText, style: AppTheme.bodyMedium),
        const SizedBox(height: 6),
        Text("Please wait...", style: AppTheme.labelSmall),
      ],
    ),
  );

  Widget _buildUploadUI() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.cardDecoration,
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accent.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.car_crash_rounded,
                  color: AppTheme.accent,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text("AI Damage Detection", style: AppTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                "Photograph your vehicle to detect scratches, dents, cracks and assess severity.",
                style: AppTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: "Detects", icon: Icons.search_rounded),
              Divider(color: AppTheme.border, height: 16),
              for (final item in [
                "Scratches & Paint Damage",
                "Dents & Body Deformation",
                "Cracks & Fractures",
                "Rust & Corrosion",
                "Broken or Missing Parts",
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_rounded,
                        color: AppTheme.accent,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item,
                        style: AppTheme.bodyMedium.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _pickFromCamera,
            style: AppTheme.primaryButton,
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text("Take Photo"),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickFromGallery,
            style: AppTheme.outlineButton,
            icon: const Icon(Icons.photo_library_rounded, size: 18),
            label: const Text("Choose from Gallery"),
          ),
        ),
      ],
    ),
  );

  Widget _buildResult() {
    final severity = _result!["severity"] as String? ?? "MEDIUM";
    final analysis = _result!["analysis"] as String? ?? "";
    final sections = _parseSections(analysis);
    final color = _severityColor(severity);
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_previewBytes != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: AppTheme.cardDecoration,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(
                    _previewBytes!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withOpacity(0.4), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _severityIcon(severity),
                      color: color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "$severity SEVERITY",
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          _severityLabel(severity),
                          style: TextStyle(
                            color: color.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...sections.map(
              (s) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s["title"]!,
                      style: AppTheme.accentLabel.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s["content"]!,
                      style: AppTheme.bodyMedium.copyWith(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _result = null;
                  _previewBytes = null;
                }),
                style: AppTheme.outlineButton,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text("Analyse Another Image"),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Analysed ${_result!['analysed_at'] ?? ''}",
              style: AppTheme.labelSmall,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
