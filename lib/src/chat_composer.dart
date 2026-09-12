import 'package:flutter/material.dart';

/// Plain message composer with model selection and send/stop controls.
class Composer extends StatefulWidget {
  const Composer({
    required this.controller,
    required this.focusNode,
    required this.selectedModel,
    required this.onActionSelected,
    required this.onModelTap,
    required this.onMicrophoneTap,
    required this.onSend,
    this.onStop,
    this.isLoading = false,
    this.sendEnabled = true,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String selectedModel;
  final void Function(String action) onActionSelected;
  final VoidCallback onModelTap;
  final VoidCallback onMicrophoneTap;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final bool isLoading;
  final bool sendEnabled;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.focusNode.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.focusNode.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasText = widget.controller.text.trim().isNotEmpty;
    final bool isFocused = widget.focusNode.hasFocus;

    final Color containerBg = isDark ? const Color(0xFF18181B) : Colors.white;
    final Border border = isDark
        ? Border.all(
            color: isFocused
                ? const Color(0xFF3F3F46)
                : const Color(0xFF27272A),
            width: 1,
          )
        : Border.all(
            color: Colors.black.withValues(alpha: isFocused ? 0.08 : 0.05),
            width: 1,
          );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        decoration: BoxDecoration(
          color: containerBg,
          border: border,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                cursorColor: isDark
                    ? const Color(0xFFF4F4F5)
                    : const Color(0xFF18181B),
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFFF4F4F5)
                      : const Color(0xFF18181B),
                  fontSize: 15.5,
                  height: 1.38,
                ),
                decoration: InputDecoration(
                  hintText: 'ถามอะไรก็ได้',
                  hintStyle: TextStyle(
                    color: isDark
                        ? const Color(0xFF71717A)
                        : const Color(0xFFA1A1AA),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // 1. ปุ่มเครื่องหมายบวก (+) สำหรับแนบไฟล์หรือรูปภาพ
                _buildAttachButton(context, isDark),
                const SizedBox(width: 8),

                // 2. ป้ายแคปซูลเลือกโมเดล AI (เช่น Sonnet 5 High)
                Flexible(
                  child: ModelSelectorButton(
                    model: widget.selectedModel,
                    onPressed: widget.onModelTap,
                  ),
                ),

                const Spacer(),

                // 3. ปุ่มไมโครโฟนสำหรับใช้เสียงพูด
                _buildMicButton(context, isDark),
                const SizedBox(width: 8),

                // 4. ปุ่มหยุด / ส่ง / สนทนาด้วยเสียง
                if (widget.isLoading)
                  StopGenerationButton(onPressed: widget.onStop ?? () {})
                else if (hasText)
                  IgnorePointer(
                    ignoring: !widget.sendEnabled,
                    child: Opacity(
                      opacity: widget.sendEnabled ? 1 : .4,
                      child: SendButton(onPressed: widget.onSend),
                    ),
                  )
                else
                  VoicePillButton(onPressed: widget.onMicrophoneTap),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachButton(BuildContext context, bool isDark) {
    final Color bg = isDark ? const Color(0xFF27272A) : const Color(0xFFF0EFED);
    final Color fg = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B);

    return Semantics(
      button: true,
      label: 'เพิ่มไฟล์หรือรูปภาพ',
      child: Tooltip(
        message: 'เพิ่มไฟล์หรือรูปภาพ',
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: PopupMenuButton<String>(
            tooltip: '',
            onSelected: widget.onActionSelected,
            position: PopupMenuPosition.over,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 180),
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
                  PopupMenuItem(value: 'รูปภาพ', child: Text('รูปภาพ')),
                  PopupMenuItem(value: 'ไฟล์', child: Text('ไฟล์')),
                ],
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Icon(Icons.add_rounded, size: 20, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicButton(BuildContext context, bool isDark) {
    final Color bg = isDark ? const Color(0xFF27272A) : const Color(0xFFF0EFED);
    final Color fg = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B);

    return Semantics(
      button: true,
      label: 'ใช้เสียงพูด',
      child: Tooltip(
        message: 'ใช้เสียงพูด',
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onMicrophoneTap,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Icon(Icons.mic_none_rounded, size: 19, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ComposerCircleButton extends StatelessWidget {
  const ComposerCircleButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark
        ? const Color(0xFF27272A)
        : const Color(0xFFF0EFED);
    final Color iconColor = isDark
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF18181B);

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: bgColor,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(child: Icon(icon, size: 19, color: iconColor)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Readable model selector capsule pill aligned with the buttons row.
class ModelSelectorButton extends StatelessWidget {
  const ModelSelectorButton({
    required this.model,
    required this.onPressed,
    super.key,
  });
  final String model;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String displayName = model.split('/').last;
    final Color bg = isDark ? const Color(0xFF27272A) : const Color(0xFFF0EFED);
    final Color fg = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B);

    return Semantics(
      button: true,
      label: 'โหมดโมเดล AI $model',
      child: Tooltip(
        message: 'เลือกโมเดล: $displayName',
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onPressed,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ปุ่มหยุดการคิด / การสร้างคำตอบ — วงกลมสีดำตัดไอคอนหยุด
class StopGenerationButton extends StatelessWidget {
  const StopGenerationButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF111111);
    final Color iconColor = isDark ? const Color(0xFF18181B) : Colors.white;

    return Semantics(
      button: true,
      label: 'หยุดการทำงาน',
      child: Tooltip(
        message: 'หยุดการทำงาน',
        child: Material(
          color: bgColor,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ปุ่มไอคอนคลื่นเสียง [ ılı ] ทรงกลมสีดำเรียบหรู
class VoicePillButton extends StatelessWidget {
  const VoicePillButton({required this.onPressed, super.key});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF111111);
    final Color iconColor = isDark ? const Color(0xFF18181B) : Colors.white;

    return Semantics(
      button: true,
      label: 'สนทนาด้วยเสียง',
      child: Tooltip(
        message: 'สนทนาด้วยเสียง',
        child: Material(
          color: bgColor,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(child: SpeechWaveIcon(color: iconColor)),
            ),
          ),
        ),
      ),
    );
  }
}

/// ไอคอนคลื่นเสียง 5 แท่ง สไตล์มินิมอลตามแบบอ้างอิง
class SpeechWaveIcon extends StatelessWidget {
  const SpeechWaveIcon({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _buildBar(4.5),
          _buildBar(8.5),
          _buildBar(13.5),
          _buildBar(8.5),
          _buildBar(4.5),
        ],
      ),
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 1.8,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Primary send action, neutral when the input is empty.
class SendButton extends StatelessWidget {
  const SendButton({
    required this.onPressed,
    this.isLoading = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = onPressed == null
        ? (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8))
        : (isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111111));
    final Color iconColor = isDark && onPressed != null
        ? const Color(0xFF18181B)
        : Colors.white;

    return Semantics(
      button: true,
      label: 'ส่งข้อความ',
      child: Tooltip(
        message: 'ส่งข้อความ',
        child: Material(
          color: bgColor,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: iconColor,
                  size: 19,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// แสดง BottomSheet เลือกโมเดล AI สไตล์ทันสมัย
void showModelPickerSheet({
  required BuildContext context,
  required String currentModel,
  required List<String> availableModels,
  required ValueChanged<String> onModelSelected,
  VoidCallback? onOpenSettings,
}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'เลือกโมเดล AI',
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFFAFAFA)
                            : const Color(0xFF18181B),
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onOpenSettings != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onOpenSettings();
                      },
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('จัดการโมเดล'),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark
                            ? const Color(0xFFD4D4D8)
                            : const Color(0xFF27272A),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ...availableModels.map((String model) {
                final bool isSelected = model == currentModel;

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                              ? const Color(0xFF27272A)
                              : const Color(0xFFF4F4F5))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected
                          ? (isDark
                                ? const Color(0xFFF4F4F5)
                                : const Color(0xFF18181B))
                          : (isDark
                                ? const Color(0xFF71717A)
                                : const Color(0xFFA1A1AA)),
                    ),
                    title: Text(
                      model,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontSize: 14.5,
                        color: isSelected
                            ? (isDark
                                  ? const Color(0xFFF4F4F5)
                                  : const Color(0xFF18181B))
                            : (isDark
                                  ? const Color(0xFFD4D4D8)
                                  : const Color(0xFF27272A)),
                      ),
                    ),
                    onTap: () {
                      onModelSelected(model);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}
