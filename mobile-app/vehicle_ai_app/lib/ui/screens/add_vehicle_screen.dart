import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../theme/app_theme.dart';
import 'upload_document_screen.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen>
    with SingleTickerProviderStateMixin {
  static const String baseUrl = "http://127.0.0.1:8000";

  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _fetchedVehicle;
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _fetchAndCreate() async {
    final number = _controller.text
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('-', '');
    if (number.isEmpty) {
      _snack("Please enter a vehicle number");
      return;
    }
    setState(() {
      _isLoading = true;
      _fetchedVehicle = null;
    });
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/add-vehicle-manual"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"vehicle_number": number}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data["message"] == "Vehicle created" && data["vehicle"] != null) {
        setState(() => _fetchedVehicle = data["vehicle"]);
        _anim.forward(from: 0);
      } else {
        _snack(data["message"] ?? "Something went wrong");
      }
    } catch (e) {
      _snack("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Vehicle result card ────────────────────────────────────────────────────
  Widget _buildResult() {
    final v = _fetchedVehicle!;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 30 * (1 - _anim.value)),
        child: Opacity(opacity: _anim.value, child: child),
      ),
      child: Container(
        decoration: AppTheme.accentCardDecoration,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.success,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Vehicle Added", style: AppTheme.titleMedium),
                    Text(
                      "Profile created successfully",
                      style: AppTheme.bodyMedium.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),

            Divider(color: AppTheme.border, height: 24),

            // Details grid
            _detailGrid(v),

            const SizedBox(height: 20),

            // Go to Garage button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: AppTheme.primaryButton,
                icon: const Icon(Icons.garage_rounded, size: 18),
                label: const Text("Go to Garage"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailGrid(Map v) {
    final fields = [
      ["Reg. Number", v["vehicle_number"] ?? ""],
      ["Owner", v["owner"] ?? ""],
      ["Model", v["model"] ?? ""],
      ["Maker", v["maker"] ?? ""],
      ["Fuel", v["fuel_type"] ?? ""],
      ["Colour", v["color"] ?? ""],
      ["Class", v["vehicle_class"] ?? ""],
      ["Reg. Date", v["registration_date"] ?? ""],
    ];

    return Column(
      children: fields
          .where((f) => (f[1] as String).isNotEmpty)
          .map(
            (f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      f[0] as String,
                      style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      f[1] as String,
                      style: AppTheme.titleMedium.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text("Add Vehicle"),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Heading
            Text("Choose a method", style: AppTheme.displayMedium),
            const SizedBox(height: 6),
            Text(
              "Upload your RC or enter the registration number",
              style: AppTheme.bodyMedium,
            ),
            AccentDivider(width: 60),
            const SizedBox(height: 28),

            // ── Option 1: RC Upload ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.cardDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppTheme.accentGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          "01",
                          style: TextStyle(
                            color: AppTheme.bg,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text("Upload RC Document", style: AppTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Take a photo or upload your RC. Vehicle number and all details are extracted automatically.",
                    style: AppTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UploadDocumentScreen(),
                          ),
                        );
                        if (result == true && mounted) Navigator.pop(context);
                      },
                      style: AppTheme.primaryButton,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text("Upload RC"),
                    ),
                  ),
                ],
              ),
            ),

            // Divider
            Row(
              children: [
                Expanded(child: Divider(color: AppTheme.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Text("OR", style: AppTheme.labelSmall),
                ),
                Expanded(child: Divider(color: AppTheme.border)),
              ],
            ),

            // ── Option 2: Manual entry ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.cardDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.borderHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "02",
                          style: AppTheme.labelSmall.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text("Enter Vehicle Number", style: AppTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Enter your registration number and we'll fetch all details automatically.",
                    style: AppTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),

                  // Input field
                  TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                    decoration: InputDecoration(
                      labelText: "Vehicle Number",
                      hintText: "KA04JN6024",
                      prefixIcon: const Icon(
                        Icons.pin_rounded,
                        color: AppTheme.accent,
                      ),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: AppTheme.textMuted,
                                size: 18,
                              ),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _fetchedVehicle = null);
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) {
                      if (_fetchedVehicle != null) {
                        setState(() => _fetchedVehicle = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: _isLoading
                        ? Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: AppTheme.accent,
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  "Fetching vehicle details...",
                                  style: AppTheme.bodyMedium,
                                ),
                              ],
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _fetchAndCreate,
                            style: AppTheme.outlineButton,
                            icon: const Icon(Icons.search_rounded, size: 18),
                            label: const Text("Fetch & Add Vehicle"),
                          ),
                  ),
                ],
              ),
            ),

            // ── Result card ──────────────────────────────────────────────────
            if (_fetchedVehicle != null) ...[
              const SizedBox(height: 20),
              _buildResult(),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
