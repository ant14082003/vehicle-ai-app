import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  final String vehicleNumber;
  final String vehicleModel;
  const ChatScreen({
    super.key,
    required this.vehicleNumber,
    required this.vehicleModel,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const String baseUrl = "http://127.0.0.1:8000";
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  final List<Map<String, String>> _messages = [];
  bool _isThinking = false;
  bool _isUploading = false;
  bool _manualLoaded = false;
  bool _billsLoaded = false;

  @override
  void initState() {
    super.initState();
    _addSystemMessage(
      "Hello! I'm your vehicle assistant for ${widget.vehicleModel}. "
      "Ask me anything about maintenance, repairs, service history, "
      "or general vehicle questions.",
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addSystemMessage(String text) =>
      setState(() => _messages.add({"role": "system", "text": text}));

  void _addMessage(String role, String text) {
    setState(() => _messages.add({"role": role, "text": text}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final question = _inputController.text.trim();
    if (question.isEmpty) return;
    _inputController.clear();
    _addMessage("user", question);
    setState(() => _isThinking = true);
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "vehicleNumber": widget.vehicleNumber,
          "question": question,
        }),
      );
      final data = jsonDecode(res.body);
      final answer = data["answer"] as String? ?? "Sorry, I could not respond.";
      setState(() {
        _manualLoaded = data["manual_loaded"] == true;
        _billsLoaded = data["bills_loaded"] == true;
      });
      _addMessage("assistant", answer);
    } catch (e) {
      _addMessage("assistant", "Connection error: $e");
    } finally {
      setState(() => _isThinking = false);
    }
  }

  Future<void> _uploadServiceBill({required bool fromCamera}) async {
    Uint8List? bytes;
    String ext = "jpg";
    if (fromCamera) {
      final picked = await _picker.pickImage(source: ImageSource.camera);
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

    setState(() => _isUploading = true);
    _addSystemMessage("Uploading service bill...");

    try {
      final ref = FirebaseStorage.instance.ref().child(
        "service_bills/${DateTime.now().millisecondsSinceEpoch}.$ext",
      );
      await ref.putData(bytes!);
      final url = await ref.getDownloadURL();

      final res = await http.post(
        Uri.parse("$baseUrl/upload-service-bill"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "imageUrl": url,
          "vehicleNumber": widget.vehicleNumber,
        }),
      );
      final data = jsonDecode(res.body);
      final explanation = data["explanation"] as String? ?? "";
      _addSystemMessage(
        "✅ Service bill uploaded.\n\n"
        "${explanation.isNotEmpty ? explanation : 'Ask me about your service history.'}",
      );
      setState(() => _billsLoaded = true);
    } catch (e) {
      _addSystemMessage("❌ Failed to upload: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _showBillUploadSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.borderHigh,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text("Upload Service Bill", style: AppTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              "Upload a service bill to track work done on your vehicle.",
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _uploadServiceBill(fromCamera: true);
              },
              style: AppTheme.primaryButton,
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text("Take Photo"),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _uploadServiceBill(fromCamera: false);
              },
              style: AppTheme.outlineButton,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text("Choose from Device"),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          "Clear History",
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          "Clear all conversation history?",
          style: AppTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              "Cancel",
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Clear",
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await http.delete(
      Uri.parse("$baseUrl/chat/history/${widget.vehicleNumber}"),
    );
    setState(() {
      _messages.clear();
      _addSystemMessage("Chat history cleared. How can I help you?");
    });
  }

  // ── Suggestion chips ──────────────────────────────────────────────────────
  final List<String> _suggestions = [
    "Oil change interval?",
    "Tyre pressure?",
    "Last service?",
    "Coolant type?",
    "Brake fluid?",
  ];

  Widget _buildSuggestions() {
    if (_messages.length > 2) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {
            _inputController.text = _suggestions[i];
            _sendMessage();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
            ),
            child: Text(
              _suggestions[i],
              style: AppTheme.accentLabel.copyWith(fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }

  // ── Message bubble ────────────────────────────────────────────────────────
  Widget _buildBubble(Map<String, String> msg) {
    final role = msg["role"]!;
    final text = msg["text"]!;

    if (role == "system") {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          text,
          style: AppTheme.bodyMedium.copyWith(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }

    final isUser = role == "user";
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isUser ? 60 : 16,
          right: isUser ? 16 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.accent : AppTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? AppTheme.bg : AppTheme.textPrimary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Vehicle Assistant"),
            Text(
              widget.vehicleNumber,
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
          // Status indicators
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: 14,
                  color: _manualLoaded ? AppTheme.success : AppTheme.textMuted,
                ),
                Icon(
                  Icons.receipt_rounded,
                  size: 14,
                  color: _billsLoaded ? AppTheme.success : AppTheme.textMuted,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            tooltip: "Upload Service Bill",
            onPressed: _isUploading ? null : _showBillUploadSheet,
          ),
          PopupMenuButton<String>(
            color: AppTheme.surface,
            onSelected: (v) {
              if (v == "clear") _clearHistory();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: "clear",
                child: Text(
                  "Clear history",
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Manual not loaded banner
          if (!_manualLoaded)
            Container(
              width: double.infinity,
              color: AppTheme.warning.withOpacity(0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Loading owner manual... answers will improve shortly.",
                      style: TextStyle(fontSize: 11, color: AppTheme.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _buildBubble(_messages[i]),
            ),
          ),

          // Thinking indicator
          if (_isThinking)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: AppTheme.accent,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Thinking...",
                        style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Suggestions
          _buildSuggestions(),
          const SizedBox(height: 4),

          // Input bar
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: "Ask about your ${widget.vehicleModel}...",
                      hintStyle: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppTheme.bg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: AppTheme.bg,
                      size: 18,
                    ),
                    onPressed: _isThinking ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
