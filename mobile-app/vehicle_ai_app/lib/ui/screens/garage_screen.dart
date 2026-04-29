import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';

import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import 'add_vehicle_screen.dart';
import 'vehicle_detail_screen.dart';
import 'dashboard_screen.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen>
    with SingleTickerProviderStateMixin {
  static const String baseUrl = "http://127.0.0.1:8000";

  List<dynamic> vehicles = [];
  List<dynamic> expiryAlerts = [];
  bool isLoading = true;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadAll();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    await Future.wait([fetchVehicles(), fetchExpiryStatus()]);
    setState(() => isLoading = false);
    _animController.forward(from: 0);
  }

  Future<void> fetchVehicles() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/vehicles"));
      final data = jsonDecode(res.body);
      if (mounted) setState(() => vehicles = data is List ? data : []);
    } catch (e) {
      debugPrint("fetchVehicles: $e");
    }
  }

  Future<void> fetchExpiryStatus() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/expiry-status"));
      final List<dynamic> data = jsonDecode(res.body);
      for (final item in data) {
        final expiry = item["expiry_date"] as String?;
        if (expiry != null && expiry.isNotEmpty) {
          await NotificationService.instance.scheduleDocumentReminders(
            vehicleNumber: item["vehicle_number"],
            docType: item["doc_type"],
            expiryDateStr: expiry,
          );
        }
      }
      if (mounted) {
        setState(() {
          expiryAlerts = data
              .where(
                (i) =>
                    i["status"] == "expired" || i["status"] == "expiring_soon",
              )
              .toList();
        });
      }
    } catch (e) {
      debugPrint("fetchExpiryStatus: $e");
    }
  }

  // ── Alert strip ────────────────────────────────────────────────────────────
  Widget _buildAlertStrip() {
    if (expiryAlerts.isEmpty) return const SizedBox.shrink();
    final isExpired = expiryAlerts.any((a) => a["status"] == "expired");
    final color = isExpired ? AppTheme.danger : AppTheme.warning;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${expiryAlerts.length} document${expiryAlerts.length > 1 ? 's' : ''} need attention",
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  expiryAlerts
                      .map((a) => "${a['doc_type']} · ${a['vehicle_number']}")
                      .take(2)
                      .join("  •  "),
                  style: AppTheme.bodyMedium.copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Vehicle card ───────────────────────────────────────────────────────────
  Widget _buildVehicleCard(Map vehicle, int index) {
    final imageUrl = vehicle["image_url"] as String?;
    final docs = (vehicle["documents"] as List?) ?? [];
    final types = docs.map((d) => d["type"] as String).toSet();
    final hasAlert = expiryAlerts.any(
      (a) => a["vehicle_number"] == vehicle["vehicle_number"],
    );

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final delay = (index * 0.15).clamp(0.0, 0.6);
        final anim = CurvedAnimation(
          parent: _animController,
          curve: Interval(
            delay,
            (delay + 0.5).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
        );
        return Transform.translate(
          offset: Offset(0, 40 * (1 - anim.value)),
          child: Opacity(opacity: anim.value, child: child),
        );
      },
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, a, __) =>
                  VehicleDetailScreen(vehicleNumber: vehicle["vehicle_number"]),
              transitionsBuilder: (_, anim, __, child) => SlideTransition(
                position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                    .animate(
                      CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                    ),
                child: child,
              ),
              transitionDuration: const Duration(milliseconds: 350),
            ),
          );
          _loadAll();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: hasAlert
              ? AppTheme.accentCardDecoration.copyWith(
                  border: Border.all(
                    color: AppTheme.warning.withOpacity(0.4),
                    width: 1.5,
                  ),
                )
              : AppTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image ───────────────────────────────────────────────────────
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: Stack(
                  children: [
                    // White/light background for clean product shot look
                    Container(
                      height: 200,
                      width: double.infinity,
                      color: const Color(
                        0xFFF0F2F5,
                      ), // very light grey — like the reference app
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.contain, // show full vehicle
                              alignment: Alignment.center,
                              placeholder: (_, __) => Container(
                                color: const Color(0xFFF0F2F5),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppTheme.accent.withOpacity(0.5),
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                    // Subtle bottom gradient to blend into card
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              AppTheme.surface.withOpacity(0.8),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Number plate badge — top right
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.accent.withOpacity(0.6),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Text(
                          vehicle["vehicle_number"] ?? "",
                          style: const TextStyle(
                            color: Color(0xFF1A1A2E),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                    ),
                    // Model name at bottom
                    Positioned(
                      bottom: 8,
                      left: 16,
                      right: 80,
                      child: Text(
                        vehicle["model"] ?? "",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          shadows: [
                            Shadow(blurRadius: 8, color: Colors.black87),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Info row ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  children: [
                    // Owner + fuel
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 12,
                                color: AppTheme.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                vehicle["owner"] ?? "Unknown",
                                style: AppTheme.bodyMedium.copyWith(
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.local_gas_station_rounded,
                                size: 12,
                                color: AppTheme.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                vehicle["fuel_type"] ?? "—",
                                style: AppTheme.bodyMedium.copyWith(
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Doc chips
                    Row(
                      children: ["RC", "Ins", "PUC"].map((label) {
                        final fullType = label == "Ins" ? "Insurance" : label;
                        final uploaded = types.contains(fullType);
                        return Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: uploaded
                                ? AppTheme.success.withOpacity(0.12)
                                : AppTheme.border,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: uploaded
                                  ? AppTheme.success.withOpacity(0.4)
                                  : AppTheme.borderHigh,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: uploaded
                                  ? AppTheme.success
                                  : AppTheme.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: AppTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTheme.surface2, AppTheme.surface],
      ),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.two_wheeler_rounded,
            size: 72,
            color: AppTheme.accent.withOpacity(0.25),
          ),
          const SizedBox(height: 8),
          Text(
            "No image available",
            style: AppTheme.labelSmall.copyWith(fontSize: 10),
          ),
        ],
      ),
    ),
  );

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.border, width: 2),
          ),
          child: Icon(
            Icons.garage_rounded,
            size: 48,
            color: AppTheme.accent.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 24),
        Text("Your garage is empty", style: AppTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          "Add your first vehicle to get started",
          style: AppTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddVehicleScreen()),
            );
            _loadAll();
          },
          style: AppTheme.primaryButton,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text("Add Vehicle"),
        ),
      ],
    ),
  );

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: AppTheme.bg,
            expandedHeight: 120,
            pinned: true,
            elevation: 0,
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
                        "AUTO VAULT",
                        style: AppTheme.accentLabel.copyWith(fontSize: 10),
                      ),
                      Text(
                        "My Garage",
                        style: AppTheme.displayMedium.copyWith(fontSize: 20),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (vehicles.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        "${vehicles.length} vehicle${vehicles.length > 1 ? 's' : ''}",
                        style: AppTheme.accentLabel,
                      ),
                    ),
                ],
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppTheme.surface.withOpacity(0.3), AppTheme.bg],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.dashboard_rounded),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DashboardScreen()),
                  );
                },
                color: AppTheme.textSecondary,
              ),

              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadAll,
                color: AppTheme.textSecondary,
              ),
            ],
          ),

          // ── Content ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: isLoading
                ? SizedBox(
                    height: 400,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              color: AppTheme.accent,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Loading your garage...",
                            style: AppTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  )
                : vehicles.isEmpty
                ? SizedBox(height: 500, child: _buildEmptyState())
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Column(
                      children: [
                        _buildAlertStrip(),
                        ...vehicles.asMap().entries.map(
                          (e) => _buildVehicleCard(e.value, e.key),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
          ),
        ],
      ),

      // ── FAB ───────────────────────────────────────────────────────────────
      floatingActionButton: vehicles.isEmpty
          ? null
          : Container(
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
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddVehicleScreen()),
                  );
                  _loadAll();
                },
                backgroundColor: Colors.transparent,
                elevation: 0,
                icon: const Icon(
                  Icons.add_rounded,
                  color: AppTheme.bg,
                  size: 22,
                ),
                label: const Text(
                  "Add Vehicle",
                  style: TextStyle(
                    color: AppTheme.bg,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
    );
  }
}
