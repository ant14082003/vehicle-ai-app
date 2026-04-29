import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import 'chat_screen.dart';
import 'damage_detection_screen.dart';
import 'predictive_maintenance_screen.dart';
import 'insurance_claim_screen.dart';
import 'upload_document_screen.dart';

class VehicleDetailScreen extends StatefulWidget {
  final String vehicleNumber;
  const VehicleDetailScreen({super.key, required this.vehicleNumber});

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen>
    with SingleTickerProviderStateMixin {
  static const String baseUrl = "http://127.0.0.1:8000";
  Map<String, dynamic> vehicle = {};
  bool isLoading = true;
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    fetchVehicle();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> fetchVehicle() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/vehicle/${widget.vehicleNumber}"),
      );
      final data = jsonDecode(res.body);
      setState(() => vehicle = data is Map<String, dynamic> ? data : {});
      _anim.forward(from: 0);
    } catch (e) {
      debugPrint("fetchVehicle: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<void> _deleteVehicle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: AppTheme.danger,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "Delete Vehicle",
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("This will permanently delete:", style: AppTheme.bodyMedium),
            const SizedBox(height: 10),
            for (final item in [
              "Vehicle profile & all details",
              "All documents (RC, Insurance, PUC)",
              "All service bills",
              "AI chat history",
              "Scheduled reminders",
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
                        color: AppTheme.danger,
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
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.danger,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "This action cannot be undone.",
                    style: TextStyle(
                      color: AppTheme.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              "Cancel",
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "Delete",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final docs = (vehicle["documents"] as List?) ?? [];
      for (final doc in docs) {
        if (doc["type"] == "Insurance" || doc["type"] == "PUC") {
          await NotificationService.instance.cancelDocumentReminders(
            vehicleNumber: widget.vehicleNumber,
            docType: doc["type"],
          );
        }
      }
      final res = await http.delete(
        Uri.parse("$baseUrl/vehicle/${widget.vehicleNumber}"),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data["deleted"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${widget.vehicleNumber} deleted."),
            backgroundColor: AppTheme.danger,
          ),
        );
        Navigator.pop(context, "deleted");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  // ── Expiry helpers ─────────────────────────────────────────────────────────
  int? _days(String? s) {
    if (s == null) return null;
    try {
      final p = s.split('/');
      return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]))
          .difference(
            DateTime.now().copyWith(
              hour: 0,
              minute: 0,
              second: 0,
              millisecond: 0,
            ),
          )
          .inDays;
    } catch (_) {
      return null;
    }
  }

  Color _statusColor(int? d) {
    if (d == null) return AppTheme.textMuted;
    if (d < 0) return AppTheme.danger;
    if (d <= 7) return AppTheme.warning;
    return AppTheme.success;
  }

  String _statusLabel(int? d) {
    if (d == null) return "No date";
    if (d < 0) return "Expired ${d.abs()}d ago";
    if (d == 0) return "Expires today";
    if (d <= 7) return "Expires in ${d}d";
    return "${d}d remaining";
  }

  IconData _statusIcon(int? d) {
    if (d == null) return Icons.help_outline_rounded;
    if (d < 0) return Icons.error_rounded;
    if (d <= 7) return Icons.warning_amber_rounded;
    return Icons.verified_rounded;
  }

  // ── Hero ───────────────────────────────────────────────────────────────────
  Widget _buildHero() {
    final imageUrl = vehicle["image_url"] as String?;
    return Column(
      children: [
        Container(
          height: 280,
          width: double.infinity,
          color: const Color(0xFFF0F2F5),
          child: Stack(
            children: [
              Positioned.fill(
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        placeholder: (_, __) => Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.accent.withOpacity(0.5),
                            strokeWidth: 2,
                          ),
                        ),
                        errorWidget: (_, __, ___) => _heroPlaceholder(),
                      )
                    : _heroPlaceholder(),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, AppTheme.bg],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: AppTheme.bg,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Number plate
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.accent.withOpacity(0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withOpacity(0.15),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A3A8F),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Center(
                        child: Text(
                          "IN",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      widget.vehicleNumber,
                      style: const TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                vehicle["model"] ?? widget.vehicleNumber,
                style: AppTheme.displayLarge,
              ),
              const SizedBox(height: 4),
              Text(
                "${vehicle["maker"] ?? ''}  ·  ${vehicle["color"] ?? ''}",
                style: AppTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroPlaceholder() => Container(
    color: const Color(0xFFF0F2F5),
    child: Center(
      child: Icon(
        Icons.two_wheeler_rounded,
        size: 80,
        color: Colors.grey.withOpacity(0.4),
      ),
    ),
  );

  // ── Stats strip ────────────────────────────────────────────────────────────
  Widget _buildStatsStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          _stat(
            Icons.local_gas_station_rounded,
            vehicle["fuel_type"] ?? "—",
            "Fuel",
          ),
          Container(width: 1, height: 36, color: AppTheme.border),
          _stat(Icons.settings_rounded, vehicle["engine_cc"] ?? "—", "Engine"),
          Container(width: 1, height: 36, color: AppTheme.border),
          _stat(
            Icons.category_rounded,
            vehicle["vehicle_class"] ?? "—",
            "Class",
          ),
          Container(width: 1, height: 36, color: AppTheme.border),
          _stat(
            Icons.calendar_today_rounded,
            vehicle["registration_date"] ?? "—",
            "Reg.",
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) => Expanded(
    child: Column(
      children: [
        Icon(icon, color: AppTheme.accent, size: 18),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTheme.bodyMedium.copyWith(
            fontSize: 11,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(label, style: AppTheme.labelSmall),
      ],
    ),
  );

  // ── Feature quick actions ──────────────────────────────────────────────────
  Widget _buildFeatureActions() {
    final model = vehicle["model"] as String? ?? widget.vehicleNumber;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: "Tools", icon: Icons.apps_rounded),
          const SizedBox(height: 12),
          Row(
            children: [
              _featureTile(
                icon: Icons.car_crash_rounded,
                label: "Damage\nDetect",
                color: AppTheme.danger,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DamageDetectionScreen(
                      vehicleNumber: widget.vehicleNumber,
                      vehicleModel: model,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _featureTile(
                icon: Icons.build_circle_rounded,
                label: "Maintenance\nPredict",
                color: AppTheme.warning,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PredictiveMaintenanceScreen(
                      vehicleNumber: widget.vehicleNumber,
                      vehicleModel: model,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _featureTile(
                icon: Icons.shield_rounded,
                label: "Insurance\nClaim",
                color: AppTheme.info,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InsuranceClaimScreen(
                      vehicleNumber: widget.vehicleNumber,
                      vehicleModel: model,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _featureTile(
                icon: Icons.smart_toy_rounded,
                label: "AI\nAssistant",
                color: AppTheme.accent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      vehicleNumber: widget.vehicleNumber,
                      vehicleModel: model,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featureTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Registration section ───────────────────────────────────────────────────
  Widget _buildRegistrationSection() {
    return _card(
      title: "Registration",
      icon: Icons.article_rounded,
      child: Column(
        children: [
          _infoRow("Owner", vehicle["owner"] ?? "—"),
          _infoRow("Reg. Date", vehicle["registration_date"] ?? "—"),
          _infoRow("Fitness Upto", vehicle["fitness_upto"] ?? "—"),
          _infoRow("Mfg. Date", vehicle["mfg_date"] ?? "—"),
          _infoRow("Chassis No.", vehicle["chassis_number"] ?? "—"),
          _infoRow("Engine No.", vehicle["engine_number"] ?? "—"),
          _infoRow("State", vehicle["state"] ?? "—"),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    if (value.isEmpty || value == "—") return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppTheme.bodyMedium.copyWith(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTheme.titleMedium.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Documents section ──────────────────────────────────────────────────────
  Widget _buildDocumentsSection() {
    return _card(
      title: "Documents",
      icon: Icons.folder_special_rounded,
      child: Column(
        children: [_docRow("RC"), _docRow("Insurance"), _docRow("PUC")],
      ),
    );
  }

  Widget _docRow(String docType) {
    final documents = (vehicle["documents"] as List?) ?? [];
    final doc = documents.cast<Map>().firstWhere(
      (d) => d["type"] == docType,
      orElse: () => {},
    );
    final exists = doc.isNotEmpty;
    final expiry = exists ? doc["expiry_date"] as String? : null;
    final days = _days(expiry);
    final color = _statusColor(days);
    final pages = exists ? (doc["urls"] as List?)?.length ?? 1 : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: exists ? color.withOpacity(0.35) : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (exists ? color : AppTheme.textMuted).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              exists ? _statusIcon(days) : Icons.upload_file_rounded,
              color: exists ? color : AppTheme.textMuted,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      docType,
                      style: AppTheme.titleMedium.copyWith(fontSize: 14),
                    ),
                    if (exists && pages > 1) ...[
                      const SizedBox(width: 6),
                      StatusBadge(label: "$pages pages", color: AppTheme.info),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  exists
                      ? (expiry != null
                            ? "${_statusLabel(days)} · $expiry"
                            : "Uploaded ✓")
                      : "Not uploaded yet",
                  style: TextStyle(
                    color: exists ? color.withOpacity(0.9) : AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (exists)
            _smallBtn("View", () => _showDocSheet(doc), AppTheme.accent)
          else
            _smallBtn("Upload", () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UploadDocumentScreen(
                    vehicleNumber: widget.vehicleNumber,
                    docType: docType,
                  ),
                ),
              );
              fetchVehicle();
            }, AppTheme.info),
          if (exists && days != null && days <= 7) ...[
            const SizedBox(width: 6),
            _smallBtn("Renew", () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UploadDocumentScreen(
                    vehicleNumber: widget.vehicleNumber,
                    docType: docType,
                  ),
                ),
              );
              fetchVehicle();
            }, color),
          ],
        ],
      ),
    );
  }

  Widget _smallBtn(String label, VoidCallback onTap, Color color) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

  // ── Service history ────────────────────────────────────────────────────────
  Widget _buildServiceHistory() {
    final bills = (vehicle["service_bills"] as List?) ?? [];
    return _card(
      title: "Service History",
      icon: Icons.build_circle_rounded,
      trailing: bills.isNotEmpty
          ? StatusBadge(
              label: "${bills.length} records",
              color: AppTheme.accent,
            )
          : null,
      child: bills.isEmpty
          ? Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.textMuted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "No service bills yet. Upload via the AI chat.",
                    style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                  ),
                ),
              ],
            )
          : Column(
              children: bills
                  .cast<Map>()
                  .map(
                    (bill) => GestureDetector(
                      onTap: () => _showBillSheet(bill),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.receipt_rounded,
                                color: AppTheme.accent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Service Record",
                                    style: AppTheme.titleMedium.copyWith(
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    bill["uploaded_at"] ?? "",
                                    style: AppTheme.bodyMedium.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (bill["explanation"] != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      bill["explanation"],
                                      style: AppTheme.bodyMedium.copyWith(
                                        fontSize: 11,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
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
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  // ── Damage reports ─────────────────────────────────────────────────────────
  Widget _buildDamageReports() {
    final reports = (vehicle["damage_reports"] as List?) ?? [];
    if (reports.isEmpty) return const SizedBox.shrink();

    Color sevColor(String? s) {
      switch (s?.toUpperCase()) {
        case "HIGH":
          return AppTheme.danger;
        case "MEDIUM":
          return AppTheme.warning;
        case "NONE":
          return AppTheme.success;
        default:
          return AppTheme.success;
      }
    }

    return _card(
      title: "Damage Reports",
      icon: Icons.car_crash_rounded,
      trailing: StatusBadge(label: "${reports.length}", color: AppTheme.danger),
      child: Column(
        children: reports
            .cast<Map>()
            .map(
              (r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: sevColor(r["severity"] as String?).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    StatusBadge(
                      label: r["severity"] as String? ?? "—",
                      color: sevColor(r["severity"] as String?),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r["analysed_at"] as String? ?? "",
                        style: AppTheme.bodyMedium.copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Card wrapper ───────────────────────────────────────────────────────────
  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, icon: icon, trailing: trailing),
          Divider(color: AppTheme.border, height: 20),
          child,
        ],
      ),
    );
  }

  // ── Doc details sheet ──────────────────────────────────────────────────────
  void _showDocSheet(Map doc) {
    final expiry = doc["expiry_date"] as String?;
    final days = _days(expiry);
    final color = _statusColor(days);
    final urls =
        (doc["urls"] as List?)?.cast<String>() ?? [doc["url"] as String? ?? ""];
    final isPdf = urls.first.toLowerCase().contains(".pdf");

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
              Row(
                children: [
                  Text("${doc["type"]} Document", style: AppTheme.titleLarge),
                  const Spacer(),
                  if (urls.length > 1)
                    StatusBadge(
                      label: "${urls.length} pages",
                      color: AppTheme.info,
                      icon: Icons.layers_rounded,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (expiry != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(_statusIcon(days), color: color, size: 20),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Expires: $expiry",
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _statusLabel(days),
                            style: TextStyle(
                              color: color.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (!isPdf)
                ...urls.asMap().entries.map(
                  (e) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (urls.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            "Page ${e.key + 1}",
                            style: AppTheme.labelSmall,
                          ),
                        ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: e.value,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => Container(
                            height: 160,
                            color: AppTheme.surface2,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 60,
                            color: AppTheme.surface2,
                            child: const Center(
                              child: Text(
                                "Could not load",
                                style: TextStyle(color: AppTheme.textMuted),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ...urls.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(e.value);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      style: urls.length > 1
                          ? AppTheme.outlineButton
                          : AppTheme.primaryButton,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(
                        urls.length > 1
                            ? "Open Page ${e.key + 1}"
                            : isPdf
                            ? "Open PDF"
                            : "View Full Size",
                      ),
                    ),
                  ),
                ),
              ),
              if (doc["uploaded_at"] != null) ...[
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    "Uploaded ${doc["uploaded_at"]}",
                    style: AppTheme.labelSmall,
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bill sheet ─────────────────────────────────────────────────────────────
  void _showBillSheet(Map bill) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppTheme.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Service Record", style: AppTheme.titleLarge),
                      Text(
                        bill["uploaded_at"] ?? "",
                        style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (bill["explanation"] != null) ...[
                AccentDivider(),
                const SizedBox(height: 12),
                Text(
                  "AI Summary",
                  style: AppTheme.accentLabel.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  bill["explanation"],
                  style: AppTheme.bodyMedium.copyWith(
                    fontSize: 14,
                    height: 1.6,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.bg.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary,
              size: 18,
            ),
          ),
        ),
        actions: [
          GestureDetector(
            onTap: fetchVehicle,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.bg.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: AppTheme.textPrimary,
                size: 18,
              ),
            ),
          ),
          GestureDetector(
            onTap: _deleteVehicle,
            child: Container(
              margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.danger,
                size: 18,
              ),
            ),
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: AppTheme.accent,
                strokeWidth: 2,
              ),
            )
          : RefreshIndicator(
              onRefresh: fetchVehicle,
              color: AppTheme.accent,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildHero(),
                    const SizedBox(height: 16),
                    _buildStatsStrip(),
                    _buildFeatureActions(),
                    const SizedBox(height: 16),
                    _buildRegistrationSection(),
                    _buildDocumentsSection(),
                    _buildServiceHistory(),
                    _buildDamageReports(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }
}
