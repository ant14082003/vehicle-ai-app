import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../theme/app_theme.dart';

class PredictiveMaintenanceScreen extends StatefulWidget {
  final String vehicleNumber;
  final String vehicleModel;
  const PredictiveMaintenanceScreen({
    super.key,
    required this.vehicleNumber,
    required this.vehicleModel,
  });

  @override
  State<PredictiveMaintenanceScreen> createState() =>
      _PredictiveMaintenanceScreenState();
}

class _PredictiveMaintenanceScreenState
    extends State<PredictiveMaintenanceScreen>
    with SingleTickerProviderStateMixin {
  static const String baseUrl = "http://127.0.0.1:8000";

  bool _isLoading = false;
  Map<String, dynamic>? _data;
  final TextEditingController _mileageController = TextEditingController();
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fetchMaintenance();
  }

  @override
  void dispose() {
    _mileageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchMaintenance({int? mileage}) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/predictive-maintenance"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "vehicleNumber": widget.vehicleNumber,
          "currentMileage": mileage ?? 0,
        }),
      );
      final data = jsonDecode(res.body);
      setState(() => _data = data);
      _animController.forward(from: 0);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Color _priorityColor(String? p) {
    switch (p?.toUpperCase()) {
      case "HIGH":
        return AppTheme.danger;
      case "MEDIUM":
        return AppTheme.warning;
      default:
        return AppTheme.success;
    }
  }

  Color _statusColor(String? s) {
    if (s == "OVERDUE") return AppTheme.danger;
    if (s == "DUE_SOON") return AppTheme.warning;
    if (s == "OK") return AppTheme.success;
    return AppTheme.textMuted;
  }

  String _statusLabel(Map item) {
    if (item["overdue"] == true) return "OVERDUE";
    final km = item["km_until_next"];
    if (km != null) return "Due at ${km} km";
    final mo = item["months_until_next"];
    if (mo != null) return "Due in ${mo} month(s)";
    return "Check recommended";
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
            const Text("Predictive Maintenance"),
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
            onPressed: () => _fetchMaintenance(
              mileage: int.tryParse(_mileageController.text) ?? 0,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: AppTheme.accent,
                strokeWidth: 2,
              ),
            )
          : _data == null
          ? const Center(child: Text("No data"))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final overdue = _data!["overdue_count"] as int? ?? 0;
    final dueSoon = _data!["due_soon_count"] as int? ?? 0;
    final predictions = (_data!["predictions"] as List?) ?? [];
    final aiAnalysis = _data!["ai_analysis"] as String? ?? "";
    final lastService = _data!["last_service"] as String?;
    final ageMonths = _data!["vehicle_age_months"] as int? ?? 0;

    return AnimatedBuilder(
      animation: _animController,
      builder: (_, child) =>
          Opacity(opacity: _animController.value, child: child),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Mileage input ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mileageController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: "Current Mileage (km)",
                        hintText: "e.g. 15000",
                        prefixIcon: Icon(
                          Icons.speed_rounded,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => _fetchMaintenance(
                      mileage: int.tryParse(_mileageController.text) ?? 0,
                    ),
                    style: AppTheme.primaryButton.copyWith(
                      padding: const MaterialStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    child: const Text("Update"),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Summary cards ──────────────────────────────────────────────
            Row(
              children: [
                _summaryCard(
                  "Overdue",
                  overdue.toString(),
                  AppTheme.danger,
                  Icons.error_rounded,
                ),
                const SizedBox(width: 10),
                _summaryCard(
                  "Due Soon",
                  dueSoon.toString(),
                  AppTheme.warning,
                  Icons.warning_amber_rounded,
                ),
                const SizedBox(width: 10),
                _summaryCard(
                  "Age",
                  "${ageMonths}mo",
                  AppTheme.info,
                  Icons.calendar_today_rounded,
                ),
              ],
            ),

            if (lastService != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.success.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.success,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Last service bill uploaded: $lastService",
                      style: TextStyle(
                        color: AppTheme.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── AI analysis ────────────────────────────────────────────────
            if (aiAnalysis.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.accentCardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.smart_toy_rounded,
                          color: AppTheme.accent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "AI Recommendation",
                          style: AppTheme.accentLabel.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      aiAnalysis,
                      style: AppTheme.bodyMedium.copyWith(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ── Maintenance list ───────────────────────────────────────────
            SectionHeader(
              title: "Maintenance Schedule",
              icon: Icons.build_circle_rounded,
            ),
            const SizedBox(height: 12),

            ...predictions.map((item) => _maintenanceItem(item)),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(label, style: AppTheme.labelSmall.copyWith(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _maintenanceItem(Map item) {
    final isOverdue = item["overdue"] == true;
    final priority = item["priority"] as String? ?? "LOW";
    final statusColor = isOverdue ? AppTheme.danger : _priorityColor(priority);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue ? AppTheme.danger.withOpacity(0.4) : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isOverdue
                  ? Icons.error_rounded
                  : priority == "HIGH"
                  ? Icons.warning_amber_rounded
                  : Icons.build_circle_outlined,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item["service"] as String? ?? "",
                  style: AppTheme.titleMedium.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  "Every ${item['interval_km']} km / ${item['interval_months']} months",
                  style: AppTheme.bodyMedium.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Text(
              _statusLabel(item),
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
