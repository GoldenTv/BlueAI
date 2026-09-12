import 'package:flutter/material.dart';

import 'ai_gateway_service.dart';
import 'chat_controller.dart';
import 'blueai_theme.dart';

/// ไดอะล็อกสำหรับการตั้งค่าระบบ BlueAI (Backend URL และรายการโมเดล AI)
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({required this.controller, super.key});

  final ChatController controller;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _apiKeyController;
  final TextEditingController _newModelController = TextEditingController();
  bool _obscureApiKey = true;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.controller.backendUrl);
    _apiKeyController = TextEditingController(text: widget.controller.apiKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    _newModelController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings({bool close = false}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final String url = AiGatewayService.normalizeBackendUrl(
        _urlController.text,
      );
      _urlController.text = url;
      await widget.controller.setApiKey(_apiKeyController.text.trim());
      await widget.controller.setBackendUrl(url);
      if (mounted && close) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saveError = 'ไม่สามารถบันทึก API Key ได้ โปรดลองอีกครั้ง';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _addNewModel() {
    final String model = _newModelController.text.trim();
    if (model.isEmpty) return;

    widget.controller.addModel(model);
    _newModelController.clear();
    setState(() {});
  }

  void _removeModel(String model) {
    widget.controller.removeModel(model);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Header
                Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: BlueAIPalette.tint(isDark),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.tune_rounded,
                          color: BlueAIPalette.textSecondary(isDark),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'ตั้งค่า BlueAI',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFFFAFAFA)
                                  : const Color(0xFF18181B),
                            ),
                          ),
                          Text(
                            'การเชื่อมต่อ Backend และจัดการโมเดล AI',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? const Color(0xFFA1A1AA)
                                  : const Color(0xFF71717A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Backend URL section
                Text(
                  'Backend URL (Gateway Endpoint)',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFE4E4E7)
                        : const Color(0xFF27272A),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark
                        ? const Color(0xFFF4F4F5)
                        : const Color(0xFF18181B),
                  ),
                  decoration: InputDecoration(
                    hintText: 'https://blueai.example.com',
                    hintStyle: TextStyle(
                      color: isDark
                          ? const Color(0xFF71717A)
                          : const Color(0xFFA1A1AA),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFF4F4F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _saveSettings(),
                ),
                const SizedBox(height: 6),
                Text(
                  'URL ที่ไม่ระบุโปรโตคอลจะใช้ HTTPS; HTTP สำหรับการพัฒนาเท่านั้น',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? const Color(0xFF71717A)
                        : const Color(0xFFA1A1AA),
                  ),
                ),
                const SizedBox(height: 20),

                // API Key section
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(
                      'API Key (AI Gateway)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFE4E4E7)
                            : const Color(0xFF27272A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: BlueAIPalette.tint(isDark),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'จำเป็น',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: BlueAIPalette.textSecondary(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark
                        ? const Color(0xFFF4F4F5)
                        : const Color(0xFF18181B),
                  ),
                  decoration: InputDecoration(
                    hintText: 'sk-user-...',
                    hintStyle: TextStyle(
                      color: isDark
                          ? const Color(0xFF71717A)
                          : const Color(0xFFA1A1AA),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFF4F4F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: isDark
                            ? const Color(0xFFA1A1AA)
                            : const Color(0xFF71717A),
                      ),
                      tooltip: _obscureApiKey ? 'แสดง API Key' : 'ซ่อน API Key',
                      onPressed: () {
                        setState(() {
                          _obscureApiKey = !_obscureApiKey;
                        });
                      },
                    ),
                  ),
                  onSubmitted: (_) => _saveSettings(),
                ),
                const SizedBox(height: 6),
                Text(
                  'คีย์จะถูกบันทึกไว้ในเครื่องของคุณเท่านั้น และส่งผ่าน HTTPS ไปยัง Backend',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? const Color(0xFF71717A)
                        : const Color(0xFFA1A1AA),
                  ),
                ),
                const SizedBox(height: 20),

                Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF27272A)
                      : const Color(0xFFE4E4E7),
                ),
                const SizedBox(height: 16),

                // Model Management section
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(
                      'รายการโมเดล AI',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFE4E4E7)
                            : const Color(0xFF27272A),
                      ),
                    ),
                    Text(
                      'แตะเพื่อเลือกโมเดลหลัก',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFF71717A)
                            : const Color(0xFFA1A1AA),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Model list
                ...widget.controller.availableModels.map((String model) {
                  final bool isSelected =
                      model == widget.controller.selectedModel;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark
                                ? const Color(0x591E3A8A)
                                : const Color(0xFFEFF6FF))
                          : (isDark
                                ? const Color(0xFF27272A)
                                : const Color(0xFFFAFAFA)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF2563EB)
                            : (isDark
                                  ? const Color(0xFF3F3F46)
                                  : const Color(0xFFE4E4E7)),
                        width: isSelected ? 1.2 : 0.8,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isSelected
                              ? const Color(0xFF2563EB)
                              : (isDark
                                    ? const Color(0xFF71717A)
                                    : const Color(0xFFA1A1AA)),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              widget.controller.setSelectedModel(model);
                              setState(() {});
                            },
                            child: Text(
                              model,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? const Color(0xFF2563EB)
                                    : (isDark
                                          ? const Color(0xFFF4F4F5)
                                          : const Color(0xFF27272A)),
                              ),
                            ),
                          ),
                        ),
                        if (widget.controller.availableModels.length > 1)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            color: isDark
                                ? const Color(0xFFA1A1AA)
                                : const Color(0xFF71717A),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            splashRadius: 16,
                            tooltip: 'ลบโมเดล',
                            onPressed: () => _removeModel(model),
                          ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 8),

                // Add new model row
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _newModelController,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFFF4F4F5)
                              : const Color(0xFF18181B),
                        ),
                        decoration: InputDecoration(
                          hintText: 'เพิ่มโมเดล เช่น claude-3-7-sonnet',
                          hintStyle: TextStyle(
                            color: isDark
                                ? const Color(0xFF71717A)
                                : const Color(0xFFA1A1AA),
                            fontSize: 12.5,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF27272A)
                              : const Color(0xFFF4F4F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addNewModel(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _addNewModel,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('เพิ่ม'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Action Buttons
                if (_saveError != null ||
                    widget.controller.initializationError != null)
                  Text(
                    _saveError ?? widget.controller.initializationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: _saving
                          ? null
                          : () => _saveSettings(close: true),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      child: const Text('บันทึกและปิด'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
