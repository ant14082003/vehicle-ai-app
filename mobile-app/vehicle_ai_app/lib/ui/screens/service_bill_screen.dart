import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../theme/app_theme.dart';
import '../../constants.dart';

class ServiceBillScreen extends StatefulWidget {
  final String vehicleNumber;
  final String vehicleModel;

  const ServiceBillScreen({
    super.key,
    required this.vehicleNumber,
    required this.vehicleModel,
  });

  @override
  State<ServiceBillScreen> createState() => _ServiceBillScreenState();
}

class _ServiceBillScreenState extends State<ServiceBillScreen>
    with SingleTickerProviderStateMixin {
  final String baseUrl = AppConstants.baseUrl;
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false;
  bool _isLoading = true;
  String _statusText = "";

  List<Map> _bills = [];
  Map<String, dynamic>? _latestResult;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _loadBills();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Load existing bills from vehicle profile ───────────────────────────────
  Future<void> _loadBills() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/vehicle/${widget.vehicleNumber}"),
      );
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        final bills = (data["service_bills"] as List?) ?? [];
        setState(() => _bills = bills.cast<Map>());
      }
      _animController.forward(from: 0);
    } catch (e) {
      _snack("Could not load bills: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Upload helpers ─────────────────────────────────────────────────────────
  Future<String> _uploadToFirebase(Uint8List bytes, String ext) async {
    final ref = FirebaseStorage.instance.ref().child(
      "service_bills/${widget.vehicleNumber}_${DateTime.now().millisecondsSinceEpoch}.$ext",
    );
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  Future<void> _pickAndUpload({required ImageSource source}) async {
    try {
      Uint8List? bytes;
      String ext = "jpg";

      if (source == ImageSource.camera) {
        final picked = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
        );
        if (picked == null) return;
        bytes = await picked.readAsBytes();
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
          withData: true,
        );
        if (result == null) return;
        bytes = result.files.first.bytes!;
        ext = result.files.first.extension ?? "jpg";
      }

      await _upload(bytes, ext);
    } catch (e) {
      _snack("Error: $e");
    }
  }

  Future<void> _upload(Uint8List bytes, String ext) async {
    setState(() {
      _isUploading = true;
      _latestResult = null;
      _statusText = "Uploading bill...";
    });

    try {
      final firebaseUrl = await _uploadToFirebase(bytes, ext);
      setState(() => _statusText = "Extracting service details with AI...");

      final res = await http.post(
        Uri.parse("$baseUrl/upload-service-bill"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "imageUrl": firebaseUrl,
          "vehicleNumber": widget.vehicleNumber,
        }),
      );

      final data = jsonDecode(res.body);
      if (data["message"] != null &&
          (data["message"] as String).contains("uploaded")) {
        setState(() => _latestResult = data);
        _animController.forward(from: 0);
        await _loadBills(); // refresh the list
        _snack("Service bill uploaded successfully");
      } else {
        _snack(data["message"] ?? "Upload failed");
      }
    } catch (e) {
      _snack("Upload failed: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppTheme.borderHigh,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text("Upload Service Bill", style: AppTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              "Upload your workshop bill to track service history "
              "and get an AI explanation of what was done.",
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _pickAndUpload(source: ImageSource.camera);
              },
              style: AppTheme.primaryButton,
              icon: const Icon(Icons.camera_alt_rounded, size: 20),
              label: const Text("Take Photo of Bill"),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _pickAndUpload(source: ImageSource.gallery);
              },
              style: AppTheme.outlineButton,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text("Choose from Device (JPG / PDF)"),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppTheme.accent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Tip: Photograph the full bill clearly in good lighting. "
                      "Include the total amount, date, and list of services.",
                      style: AppTheme.bodyMedium.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Show full bill detail ──────────────────────────────────────────────────
  void _showBillDetail(Map bill) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.borderHigh,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppTheme.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Service Record", style: AppTheme.titleLarge),
                        Text(
                          "Uploaded ${bill['uploaded_at'] ?? ''}",
                          style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              AccentDivider(width: 60),
              const SizedBox(height: 16),

              // AI Explanation
              if (bill["explanation"] != null &&
                  (bill["explanation"] as String).isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.smart_toy_rounded,
                      color: AppTheme.accent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "AI Summary",
                      style: AppTheme.accentLabel.copyWith(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    bill["explanation"],
                    style: AppTheme.bodyMedium.copyWith(
                      fontSize: 13,
                      height: 1.6,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Preview text
              if (bill["preview"] != null &&
                  (bill["preview"] as String).isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.text_snippet_rounded,
                      color: AppTheme.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text("Raw OCR Preview", style: AppTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    bill["preview"],
                    style: AppTheme.bodyMedium.copyWith(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ── Latest upload result card ──────────────────────────────────────────────
  Widget _buildLatestResult() {
    if (_latestResult == null) return const SizedBox.shrink();
    final explanation = _latestResult!["explanation"] as String? ?? "";

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.accentCardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.success,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  "Bill Uploaded & Analysed",
                  style: TextStyle(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                explanation,
                style: AppTheme.bodyMedium.copyWith(
                  fontSize: 13,
                  height: 1.5,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              TextButton(
                onPressed: () {
                  if (_bills.isNotEmpty) {
                    _showBillDetail(_bills.last);
                  }
                },
                style: AppTheme.ghostButton,
                child: const Text("Read full summary →"),
              ),
            ],
          ],
        ),
      ),
    );
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
            const Text("Service Bills"),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadBills,
            color: AppTheme.textSecondary,
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.accentGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _isUploading ? null : _showUploadSheet,
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: _isUploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: AppTheme.bg,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(
                  Icons.upload_file_rounded,
                  color: AppTheme.bg,
                  size: 20,
                ),
          label: Text(
            _isUploading ? _statusText : "Upload Bill",
            style: const TextStyle(
              color: AppTheme.bg,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: AppTheme.accent,
                strokeWidth: 2,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadBills,
              color: AppTheme.accent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Latest result
                    if (_latestResult != null) ...[
                      const SizedBox(height: 16),
                      _buildLatestResult(),
                    ],

                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        children: [
                          SectionHeader(
                            title: "Service History",
                            icon: Icons.history_rounded,
                            trailing: _bills.isNotEmpty
                                ? StatusBadge(
                                    label: "${_bills.length} record(s)",
                                    color: AppTheme.accent,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),

                    // Bills list
                    if (_bills.isEmpty)
                      _buildEmptyState()
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                        itemCount: _bills.length,
                        itemBuilder: (_, index) {
                          // Show newest first
                          final bill = _bills[_bills.length - 1 - index];
                          return _billCard(bill, index);
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Bill card ──────────────────────────────────────────────────────────────
  Widget _billCard(Map bill, int index) {
    final explanation = bill["explanation"] as String? ?? "";
    final uploadedAt = bill["uploaded_at"] as String? ?? "";
    final preview = bill["preview"] as String? ?? "";

    // Try to extract service date from preview text
    String serviceDate = uploadedAt;
    final dateMatch = RegExp(r'Service Date:\s*(\S+)').firstMatch(preview);
    if (dateMatch != null) {
      serviceDate = dateMatch.group(1) ?? uploadedAt;
    }

    // Try to extract odometer from preview
    String odometer = "";
    final odoMatch = RegExp(
      r'Odometer:\s*([\d,]+)\s*km',
      caseSensitive: false,
    ).firstMatch(preview);
    if (odoMatch != null) {
      odometer = "${odoMatch.group(1)} km";
    }

    return GestureDetector(
      onTap: () => _showBillDetail(bill),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Text(
                      "#${_bills.length - index}",
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Service Record",
                        style: AppTheme.titleMedium.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 11,
                            color: AppTheme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            serviceDate,
                            style: AppTheme.bodyMedium.copyWith(fontSize: 11),
                          ),
                          if (odometer.isNotEmpty) ...[
                            Text(
                              "  ·  ",
                              style: AppTheme.bodyMedium.copyWith(fontSize: 11),
                            ),
                            Icon(
                              Icons.speed_rounded,
                              size: 11,
                              color: AppTheme.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              odometer,
                              style: AppTheme.bodyMedium.copyWith(fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textMuted,
                  size: 18,
                ),
              ],
            ),

            // AI explanation preview
            if (explanation.isNotEmpty) ...[
              Divider(color: AppTheme.border, height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.smart_toy_rounded,
                    color: AppTheme.accent,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      explanation,
                      style: AppTheme.bodyMedium.copyWith(
                        fontSize: 12,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Center(
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
                Icons.receipt_long_rounded,
                size: 36,
                color: AppTheme.accent.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 20),
            Text("No service bills yet", style: AppTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              "Upload your workshop bills to track\nservice history and get AI explanations.",
              style: AppTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _showUploadSheet,
              style: AppTheme.primaryButton,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text("Upload First Bill"),
            ),
          ],
        ),
      ),
    );
  }
}
