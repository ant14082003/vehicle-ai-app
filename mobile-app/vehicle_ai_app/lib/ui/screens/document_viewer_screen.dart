import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/app_theme.dart';

class DocumentViewerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? uploadedAt;

  const DocumentViewerScreen({
    super.key,
    required this.url,
    required this.title,
    this.uploadedAt,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isPdf = false;
  String? _localPdfPath;
  bool _pdfLoading = true;
  int _pdfPages = 0;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _isPdf =
        widget.url.toLowerCase().contains('.pdf') ||
        widget.url.toLowerCase().contains('application/pdf');
    if (_isPdf) _loadPdf();
  }

  // ── Load PDF into local temp file for flutter_pdfview ─────────────────────
  Future<void> _loadPdf() async {
    setState(() => _pdfLoading = true);
    try {
      final dir = await getTemporaryDirectory();
      final filePath =
          "${dir.path}/doc_${DateTime.now().millisecondsSinceEpoch}.pdf";
      await Dio().download(widget.url, filePath);
      setState(() {
        _localPdfPath = filePath;
        _pdfLoading = false;
      });
    } catch (e) {
      setState(() => _pdfLoading = false);
      _snack("Could not load PDF: $e");
    }
  }

  // ── Download to device ─────────────────────────────────────────────────────
  Future<void> _download() async {
    // Request storage permission
    PermissionStatus status;
    if (Platform.isAndroid && (await Permission.storage.status).isDenied) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        _snack("Storage permission denied. Cannot download.");
        return;
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      // Get downloads directory
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!dir.existsSync()) {
          dir = await getExternalStorageDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final ext = _isPdf ? "pdf" : "jpg";
      final filename =
          "${widget.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.$ext";
      final filePath = "${dir!.path}/$filename";

      await Dio().download(
        widget.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      setState(() {
        _isDownloading = false;
        _downloadProgress = 0;
      });
      _snack("Saved to Downloads/$filename");
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0;
      });
      _snack("Download failed: $e");
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── PDF viewer ─────────────────────────────────────────────────────────────
  Widget _buildPdfViewer() {
    if (_pdfLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
            const SizedBox(height: 16),
            Text("Loading PDF...", style: AppTheme.bodyMedium),
          ],
        ),
      );
    }
    if (_localPdfPath == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppTheme.danger,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text("Could not load PDF", style: AppTheme.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadPdf,
              style: AppTheme.primaryButton,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        PDFView(
          filePath: _localPdfPath!,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          defaultPage: 0,
          fitPolicy: FitPolicy.BOTH,
          backgroundColor: AppTheme.bg,
          onRender: (pages) => setState(() => _pdfPages = pages ?? 0),
          onPageChanged: (page, total) =>
              setState(() => _currentPage = (page ?? 0) + 1),
          onError: (e) => _snack("PDF error: $e"),
        ),

        // Page indicator
        if (_pdfPages > 0)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.bg.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  "Page $_currentPage of $_pdfPages",
                  style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Image viewer ───────────────────────────────────────────────────────────
  Widget _buildImageViewer() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: CachedNetworkImage(
          imageUrl: widget.url,
          fit: BoxFit.contain,
          placeholder: (_, __) => Center(
            child: CircularProgressIndicator(
              color: AppTheme.accent,
              strokeWidth: 2,
            ),
          ),
          errorWidget: (_, __, ___) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.broken_image_rounded,
                  color: AppTheme.textMuted,
                  size: 64,
                ),
                const SizedBox(height: 12),
                Text("Could not load image", style: AppTheme.bodyMedium),
              ],
            ),
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
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: AppTheme.titleMedium.copyWith(fontSize: 15),
            ),
            if (widget.uploadedAt != null)
              Text("Uploaded ${widget.uploadedAt}", style: AppTheme.labelSmall),
          ],
        ),
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        actions: [
          // Download button
          GestureDetector(
            onTap: _isDownloading ? null : _download,
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: _isDownloading ? null : AppTheme.accentGradient,
                color: _isDownloading ? AppTheme.border : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _isDownloading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: AppTheme.accent,
                            strokeWidth: 2,
                            value: _downloadProgress > 0
                                ? _downloadProgress
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _downloadProgress > 0
                              ? "${(_downloadProgress * 100).toInt()}%"
                              : "...",
                          style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          color: AppTheme.bg,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          "Download",
                          style: TextStyle(
                            color: AppTheme.bg,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
      body: _isPdf ? _buildPdfViewer() : _buildImageViewer(),
    );
  }
}

// ─────────────────────────────────────────────
//  Multi-page document viewer
//  Shows multiple images (e.g. Insurance front + back)
// ─────────────────────────────────────────────
class MultiPageDocumentViewer extends StatefulWidget {
  final List<String> urls;
  final String title;
  final String? uploadedAt;

  const MultiPageDocumentViewer({
    super.key,
    required this.urls,
    required this.title,
    this.uploadedAt,
  });

  @override
  State<MultiPageDocumentViewer> createState() =>
      _MultiPageDocumentViewerState();
}

class _MultiPageDocumentViewerState extends State<MultiPageDocumentViewer> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _downloadAll() async {
    PermissionStatus status;
    if (Platform.isAndroid && (await Permission.storage.status).isDenied) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        _snack("Storage permission denied.");
        return;
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!dir.existsSync()) dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      for (int i = 0; i < widget.urls.length; i++) {
        final url = widget.urls[i];
        final isPdf = url.toLowerCase().contains('.pdf');
        final ext = isPdf ? "pdf" : "jpg";
        final filename =
            "${widget.title.replaceAll(' ', '_')}_page${i + 1}_${DateTime.now().millisecondsSinceEpoch}.$ext";
        final filePath = "${dir!.path}/$filename";

        await Dio().download(
          url,
          filePath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              setState(
                () => _downloadProgress =
                    (i + received / total) / widget.urls.length,
              );
            }
          },
        );
      }

      setState(() {
        _isDownloading = false;
        _downloadProgress = 0;
      });
      _snack("${widget.urls.length} file(s) saved to Downloads");
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0;
      });
      _snack("Download failed: $e");
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: AppTheme.titleMedium.copyWith(fontSize: 15),
            ),
            Text(
              "Page ${_currentPage + 1} of ${widget.urls.length}"
              "${widget.uploadedAt != null ? ' · Uploaded ${widget.uploadedAt}' : ''}",
              style: AppTheme.labelSmall,
            ),
          ],
        ),
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        actions: [
          GestureDetector(
            onTap: _isDownloading ? null : _downloadAll,
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: _isDownloading ? null : AppTheme.accentGradient,
                color: _isDownloading ? AppTheme.border : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _isDownloading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: AppTheme.accent,
                            strokeWidth: 2,
                            value: _downloadProgress > 0
                                ? _downloadProgress
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "${(_downloadProgress * 100).toInt()}%",
                          style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          color: AppTheme.bg,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.urls.length > 1 ? "Download All" : "Download",
                          style: const TextStyle(
                            color: AppTheme.bg,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Page viewer
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) {
                final url = widget.urls[i];
                final isPdf = url.toLowerCase().contains('.pdf');

                if (isPdf) {
                  // Navigate to single PDF viewer for PDF pages
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DocumentViewerScreen(
                          url: url,
                          title: "${widget.title} — Page ${i + 1}",
                          uploadedAt: widget.uploadedAt,
                        ),
                      ),
                    ),
                    child: Container(
                      color: AppTheme.surface2,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: AppTheme.danger,
                              size: 64,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "PDF Page ${i + 1}",
                              style: AppTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Tap to open PDF viewer",
                              style: AppTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // Image page
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.accent,
                        strokeWidth: 2,
                      ),
                    ),
                    errorWidget: (_, __, ___) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.broken_image_rounded,
                            color: AppTheme.textMuted,
                            size: 64,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Could not load page ${i + 1}",
                            style: AppTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Page indicator dots (if multiple pages)
          if (widget.urls.length > 1) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: AppTheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Prev button
                  GestureDetector(
                    onTap: _currentPage > 0
                        ? () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          )
                        : null,
                    child: Icon(
                      Icons.chevron_left_rounded,
                      color: _currentPage > 0
                          ? AppTheme.accent
                          : AppTheme.textMuted,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Dots
                  Row(
                    children: List.generate(
                      widget.urls.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _currentPage ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? AppTheme.accent
                              : AppTheme.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Next button
                  GestureDetector(
                    onTap: _currentPage < widget.urls.length - 1
                        ? () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          )
                        : null,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: _currentPage < widget.urls.length - 1
                          ? AppTheme.accent
                          : AppTheme.textMuted,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
