import 'package:flutter/material.dart';

import 'cloud_chat_controller.dart';
import 'cloud_repository.dart';

class CloudDrawer extends StatelessWidget {
  const CloudDrawer({
    required this.controller,
    required this.onSettings,
    this.email,
    this.onSignOut,
    super.key,
  });
  final CloudChatController controller;
  final VoidCallback onSettings;
  final String? email;
  final Future<void> Function()? onSignOut;

  Future<void> _rename(BuildContext context, Conversation room) async {
    final field = TextEditingController(text: room.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เปลี่ยนชื่อห้อง'),
        content: TextField(controller: field, maxLength: 40, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    // The dialog's exit animation may still reference its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    field.dispose();
    if (title != null && title.isNotEmpty) {
      await controller.editRoom(room, title: title);
    }
  }

  Future<void> _delete(BuildContext context, Conversation room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบห้องสนทนา?'),
        content: Text('“${room.title}” จะถูกลบจากรายการทุกอุปกรณ์'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบห้อง'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteRoom(room.id);
  }

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => NotificationListener<ScrollNotification>(
          onNotification: (event) {
            if (event.metrics.extentAfter < 160 &&
                controller.hasMoreRooms &&
                !controller.refreshing) {
              controller.moreRooms();
            }
            return false;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('BlueAI', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: controller.transitioning
                    ? null
                    : () {
                        Navigator.pop(context);
                        controller.openRoom(null);
                      },
                icon: const Icon(Icons.add),
                label: const Text('เริ่มการสนทนาใหม่'),
              ),
              const SizedBox(height: 16),
              if (controller.rooms.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('ยังไม่มีบทสนทนา'),
                ),
              ...controller.rooms.map(
                (room) => ListTile(
                  selected: room.id == controller.activeRoomId,
                  leading: Icon(
                    room.pinned
                        ? Icons.push_pin_outlined
                        : Icons.chat_bubble_outline,
                    size: 19,
                  ),
                  title: Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: controller.transitioning
                      ? null
                      : () {
                          Navigator.pop(context);
                          controller.openRoom(room.id);
                        },
                  trailing: PopupMenuButton<String>(
                    enabled: controller.online,
                    onSelected: (action) {
                      if (action == 'rename') _rename(context, room);
                      if (action == 'pin') {
                        controller.editRoom(room, pinned: !room.pinned);
                      }
                      if (action == 'delete') _delete(context, room);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('เปลี่ยนชื่อ'),
                      ),
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(room.pinned ? 'เลิกปักหมุด' : 'ปักหมุด'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('ลบห้อง'),
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.hasMoreRooms)
                TextButton(
                  onPressed: controller.refreshing
                      ? null
                      : controller.moreRooms,
                  child: const Text('โหลดห้องเพิ่มเติม'),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('โหมดหน้าจอ'),
                onTap: controller.toggleThemeMode,
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('การตั้งค่าระบบและโมเดล'),
                onTap: () {
                  Navigator.pop(context);
                  onSettings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('ออกจากระบบ'),
                onTap: () {
                  Navigator.pop(context);
                  onSignOut?.call();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
