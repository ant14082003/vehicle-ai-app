import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../theme/app_theme.dart';

class InsuranceClaimScreen extends StatefulWidget {
  final String vehicleNumber;
  final String vehicleModel;
  const InsuranceClaimScreen({
    super.key,
    required this.vehicleNumber,
    required this.vehicleModel,
  });

  @override
  State<InsuranceClaimScreen> createState() => _InsuranceClaimScreenState();
}

class _InsuranceClaimScreenState extends State<InsuranceClaimScreen>
    with SingleTickerProviderStateMixin {
  static const String baseUrl = "http://127.0.0.1:8000";
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _descController = TextEditingController();
  final List<Uint8List> _accidentImages = [];
  final List<String> _uploadedUrls = [];

  bool _isSubmitting = false;
  String _statusText = "";
  Map<String, dynamic>? _result;

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
    _descController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<String> _uploadToFirebase(Uint8List bytes, String ext) async {
    final ref = FirebaseStorage.instance.ref().child(
      "claims/${DateTime.now().millisecondsSinceEpoch}_${_accidentImages.length}.$ext",
    );
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  Future<void> _addPhoto({required bool fromCamera}) async {
    Uint8List? bytes;
    String ext = "jpg";
    if (fromCamera) {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (picked == null) return;
      bytes = await picked.readAsBytes();
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: true,
      );
      if (result == null) return;
      for (final file in result.files) {
        setState(() => _accidentImages.add(file.bytes!));
      }
      return;
    }
    setState(() => _accidentImages.add(bytes!));
  }

  Future<void> _submitClaim() async {
    if (_descController.text.trim().length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please provide a detailed accident description (min 20 characters)",
          ),
        ),
      );
      return;
    }
    if (_accidentImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add at least one accident photo")),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _statusText = "Uploading accident photos...";
    });

    try {
      // Upload all accident images
      final urls = <String>[];
      for (int i = 0; i < _accidentImages.length; i++) {
        setState(
          () => _statusText =
              "Uploading photo ${i + 1} of ${_accidentImages.length}...",
        );
        final url = await _uploadToFirebase(_accidentImages[i], "jpg");
        urls.add(url);
      }

      setState(() => _statusText = "Processing claim with AI...");

      final res = await http.post(
        Uri.parse("$baseUrl/insurance-claim"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "vehicleNumber": widget.vehicleNumber,
          "accidentDescription": _descController.text.trim(),
          "imageUrls": urls,
          "documentUrls": [],
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
      setState(() => _isSubmitting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Insurance Claim"),
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
      body: _isSubmitting
          ? _buildLoading()
          : _result == null
          ? _buildForm()
          : _buildResult(),
    );
  }

  Widget _buildLoading() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
        const SizedBox(height: 16),
        Text(_statusText, style: AppTheme.bodyMedium),
        const SizedBox(height: 6),
        Text("Please wait...", style: AppTheme.labelSmall),
      ],
    ),
  );

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: AppTheme.warning,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Claim Assistant", style: AppTheme.titleLarge),
                      Text(
                        "We'll guide you through the claim process step by step.",
                        style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Step 1 — Description
          _stepCard(
            step: "01",
            title: "Accident Description",
            child: Column(
              children: [
                TextField(
                  controller: _descController,
                  maxLines: 5,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    hintText:
                        "Describe the accident: when, where, what happened, other vehicles involved, injuries...",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Step 2 — Photos
          _stepCard(
            step: "02",
            title: "Accident Photos  (${_accidentImages.length} added)",
            child: Column(
              children: [
                if (_accidentImages.isNotEmpty) ...[
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _accidentImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              _accidentImages[i],
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _accidentImages.removeAt(i)),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: AppTheme.danger,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addPhoto(fromCamera: true),
                        style: AppTheme.outlineButton.copyWith(
                          padding: const MaterialStatePropertyAll(
                            EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt_rounded, size: 16),
                        label: const Text("Camera"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addPhoto(fromCamera: false),
                        style: AppTheme.outlineButton.copyWith(
                          padding: const MaterialStatePropertyAll(
                            EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                        icon: const Icon(Icons.photo_library_rounded, size: 16),
                        label: const Text("Gallery"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Step 3 — Important note
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.info.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.info.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppTheme.info,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Before submitting, make sure you have:",
                      style: TextStyle(
                        color: AppTheme.info,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final item in [
                  "Filed a police FIR (if applicable)",
                  "Noted other party's details",
                  "Photographed all damage clearly",
                  "Your RC and insurance documents uploaded",
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.only(right: 8, left: 4),
                          decoration: const BoxDecoration(
                            color: AppTheme.info,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          item,
                          style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Submit
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitClaim,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warning,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text("Submit Claim"),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _stepCard({
    required String step,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    color: AppTheme.bg,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(title, style: AppTheme.titleMedium.copyWith(fontSize: 14)),
            ],
          ),
          Divider(color: AppTheme.border, height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildResult() {
    final checklist = (_result!["checklist"] as List?) ?? [];
    final nextSteps = (_result!["next_steps"] as List?) ?? [];
    final report = _result!["claim_report"] as Map? ?? {};
    final damage = _result!["damage_summary"] as String? ?? "";
    final complete = _result!["checklist_complete"] as bool? ?? false;
    final completed = _result!["completed_items"] as int? ?? 0;
    final total = _result!["total_items"] as int? ?? 0;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Reference number
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.accentCardDecoration,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppTheme.success,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Claim Report Generated",
                        style: AppTheme.titleLarge.copyWith(fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.accent.withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      report["claim_reference"] as String? ?? "",
                      style: AppTheme.plateNumber.copyWith(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "${report['submitted_at'] ?? ''}  ·  ${report['insurance_status'] ?? ''}",
                    style: AppTheme.bodyMedium.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Checklist
            _resultCard(
              title: "Document Checklist ($completed/$total)",
              icon: Icons.checklist_rounded,
              child: Column(
                children: checklist.map<Widget>((item) {
                  final available = item["available"] as bool? ?? false;
                  final required = item["required"] as bool? ?? false;
                  final color = available
                      ? AppTheme.success
                      : required
                      ? AppTheme.danger
                      : AppTheme.warning;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          available
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: color,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item["item"] as String? ?? "",
                                style: AppTheme.titleMedium.copyWith(
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                item["note"] as String? ?? "",
                                style: AppTheme.bodyMedium.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (required && !available)
                          StatusBadge(
                            label: "REQUIRED",
                            color: AppTheme.danger,
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 12),

            // Damage summary from AI
            if (damage.isNotEmpty)
              _resultCard(
                title: "AI Damage Assessment",
                icon: Icons.car_crash_rounded,
                child: Text(
                  damage,
                  style: AppTheme.bodyMedium.copyWith(
                    fontSize: 13,
                    height: 1.5,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Next steps
            _resultCard(
              title: "Next Steps",
              icon: Icons.linear_scale_rounded,
              child: Column(
                children: nextSteps.map<Widget>((step) {
                  final done = step["done"] as bool? ?? false;
                  final urgent = step["urgent"] as bool? ?? false;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: done
                          ? AppTheme.success.withOpacity(0.06)
                          : urgent
                          ? AppTheme.danger.withOpacity(0.06)
                          : AppTheme.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: done
                            ? AppTheme.success.withOpacity(0.3)
                            : urgent
                            ? AppTheme.danger.withOpacity(0.3)
                            : AppTheme.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: done
                                ? AppTheme.success.withOpacity(0.15)
                                : urgent
                                ? AppTheme.danger.withOpacity(0.15)
                                : AppTheme.border,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: done
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: AppTheme.success,
                                    size: 14,
                                  )
                                : Text(
                                    "${step['step']}",
                                    style: TextStyle(
                                      color: urgent
                                          ? AppTheme.danger
                                          : AppTheme.textSecondary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      step["title"] as String? ?? "",
                                      style: AppTheme.titleMedium.copyWith(
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (urgent && !done)
                                    StatusBadge(
                                      label: "URGENT",
                                      color: AppTheme.danger,
                                      icon: Icons.priority_high_rounded,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                step["description"] as String? ?? "",
                                style: AppTheme.bodyMedium.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _result = null),
                style: AppTheme.outlineButton,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text("Start New Claim"),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _resultCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, icon: icon),
          Divider(color: AppTheme.border, height: 16),
          child,
        ],
      ),
    );
  }
}
