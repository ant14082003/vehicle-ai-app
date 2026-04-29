import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';

import '../../theme/app_theme.dart';
import 'vehicle_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  static const String baseUrl = "http://127.0.0.1:8000";

  bool isLoading = true;
  Map<String, dynamic> dashData = {};
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _loadDashboard();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse("$baseUrl/dashboard"));
      final data = jsonDecode(res.body);
      setState(() => dashData = data is Map<String, dynamic> ? data : {});
      _animController.forward(from: 0);
    } catch (e) {
      debugPrint("Dashboard error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Color _urgencyColor(String? u) {
    if (u == "HIGH") return AppTheme.danger;
    if (u == "MEDIUM") return AppTheme.warning;
    return AppTheme.success;
  }

  Color _healthColor(int score) {
    if (score >= 70) return AppTheme.success;
    if (score >= 40) return AppTheme.warning;
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          // ── App bar ────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: AppTheme.bg,
            expandedHeight: 100,
            pinned: true,
            elevation: 0,
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
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "OVERVIEW",
                        style: AppTheme.accentLabel.copyWith(fontSize: 9),
                      ),
                      Text(
                        "Dashboard",
                        style: AppTheme.displayMedium.copyWith(fontSize: 20),
                      ),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loadDashboard,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: AppTheme.textSecondary,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: isLoading
                ? SizedBox(
                    height: 400,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.accent,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : AnimatedBuilder(
                    animation: _animController,
                    builder: (_, child) =>
                        Opacity(opacity: _animController.value, child: child),
                    child: _buildDashboard(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final summary = dashData["summary"] as Map? ?? {};
    final docSummary = dashData["document_summary"] as Map? ?? {};
    final alerts = (dashData["expiry_alerts"] as List?) ?? [];
    final maintenance = (dashData["maintenance_alerts"] as List?) ?? [];
    final reminders = (dashData["monthly_reminders"] as List?) ?? [];
    final health = (dashData["vehicle_health"] as List?) ?? [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Summary row ──────────────────────────────────────────────────
          Row(
            children: [
              _metricTile(
                "Vehicles",
                summary["total_vehicles"]?.toString() ?? "0",
                Icons.garage_rounded,
                AppTheme.accent,
              ),
              const SizedBox(width: 10),
              _metricTile(
                "Documents",
                summary["total_documents"]?.toString() ?? "0",
                Icons.folder_rounded,
                AppTheme.info,
              ),
              const SizedBox(width: 10),
              _metricTile(
                "Alerts",
                summary["expiry_alerts"]?.toString() ?? "0",
                Icons.notifications_rounded,
                AppTheme.warning,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Document coverage ────────────────────────────────────────────
          _sectionCard(
            title: "Document Coverage",
            icon: Icons.pie_chart_rounded,
            child: Row(
              children: [
                _docCoverage(
                  "RC",
                  docSummary["RC"] ?? 0,
                  summary["total_vehicles"] ?? 0,
                ),
                _docCoverage(
                  "Insurance",
                  docSummary["Insurance"] ?? 0,
                  summary["total_vehicles"] ?? 0,
                ),
                _docCoverage(
                  "PUC",
                  docSummary["PUC"] ?? 0,
                  summary["total_vehicles"] ?? 0,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Expiry alerts ────────────────────────────────────────────────
          if (alerts.isNotEmpty)
            _sectionCard(
              title: "Expiry Alerts",
              icon: Icons.schedule_rounded,
              trailing: StatusBadge(
                label: "${alerts.length}",
                color: AppTheme.warning,
                icon: Icons.warning_amber_rounded,
              ),
              child: Column(
                children: alerts.take(5).map<Widget>((alert) {
                  final color = _urgencyColor(alert["urgency"] as String?);
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VehicleDetailScreen(
                          vehicleNumber: alert["vehicle_number"],
                        ),
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            color: color,
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${alert['vehicle_number']} · ${alert['doc_type']}",
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  alert["message"] as String? ?? "",
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "${alert['days_remaining']}d",
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 12),

          // ── Upcoming reminders ────────────────────────────────────────────
          if (reminders.isNotEmpty)
            _sectionCard(
              title: "Upcoming Renewals (90 days)",
              icon: Icons.event_rounded,
              child: Column(
                children: reminders
                    .take(5)
                    .map<Widget>(
                      (r) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.accent.withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    (r["date"] as String? ?? "").split("/")[0],
                                    style: TextStyle(
                                      color: AppTheme.accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    (r["date"] as String? ?? "")
                                                .split("/")
                                                .length >
                                            1
                                        ? _monthShort(
                                            (r["date"] as String).split("/")[1],
                                          )
                                        : "",
                                    style: AppTheme.labelSmall.copyWith(
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${r['type']} Renewal",
                                    style: AppTheme.titleMedium.copyWith(
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    r["vehicle"] as String? ?? "",
                                    style: AppTheme.bodyMedium.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(
                              label: "${r['days']}d left",
                              color: r["days"] <= 7
                                  ? AppTheme.danger
                                  : AppTheme.warning,
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          const SizedBox(height: 12),

          // ── Vehicle health ───────────────────────────────────────────────
          if (health.isNotEmpty)
            _sectionCard(
              title: "Vehicle Health",
              icon: Icons.monitor_heart_rounded,
              child: Column(
                children: health.map<Widget>((v) {
                  final score = v["health_score"] as int? ?? 0;
                  final color = _healthColor(score);
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VehicleDetailScreen(
                          vehicleNumber: v["vehicle_number"],
                        ),
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          // Vehicle thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: v["image_url"] != null
                                ? CachedNetworkImage(
                                    imageUrl: v["image_url"],
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      width: 48,
                                      height: 48,
                                      color: AppTheme.surface2,
                                      child: const Icon(
                                        Icons.two_wheeler_rounded,
                                        color: AppTheme.textMuted,
                                        size: 24,
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 48,
                                    height: 48,
                                    color: AppTheme.surface2,
                                    child: const Icon(
                                      Icons.two_wheeler_rounded,
                                      color: AppTheme.textMuted,
                                      size: 24,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v["model"] as String? ?? v["vehicle_number"],
                                  style: AppTheme.titleMedium.copyWith(
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // Health bar
                                Stack(
                                  children: [
                                    Container(
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: AppTheme.border,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: score / 100,
                                      child: Container(
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${v['documents_count']} docs · ${v['bills_count']} service records",
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "$score%",
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          // ── Maintenance alerts ────────────────────────────────────────────
          if (maintenance.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionCard(
              title: "Maintenance Notices",
              icon: Icons.build_rounded,
              child: Column(
                children: maintenance
                    .map<Widget>(
                      (m) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.warning.withOpacity(0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: AppTheme.warning,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m["vehicle_number"] as String? ?? "",
                                    style: const TextStyle(
                                      color: AppTheme.warning,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    m["message"] as String? ?? "",
                                    style: AppTheme.bodyMedium.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(label, style: AppTheme.labelSmall.copyWith(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _docCoverage(String type, int count, int total) {
    final pct = total > 0 ? count / total : 0.0;
    final color = pct >= 1.0
        ? AppTheme.success
        : pct > 0
        ? AppTheme.warning
        : AppTheme.danger;

    return Expanded(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: pct,
                  backgroundColor: AppTheme.border,
                  valueColor: AlwaysStoppedAnimation(color),
                  strokeWidth: 5,
                ),
              ),
              Text(
                "$count/$total",
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(type, style: AppTheme.labelSmall.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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

  String _monthShort(String monthNum) {
    const months = [
      "",
      "JAN",
      "FEB",
      "MAR",
      "APR",
      "MAY",
      "JUN",
      "JUL",
      "AUG",
      "SEP",
      "OCT",
      "NOV",
      "DEC",
    ];
    final idx = int.tryParse(monthNum) ?? 0;
    return idx > 0 && idx <= 12 ? months[idx] : "";
  }
}
