import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'blue_ai_theme.dart';
import 'chat_composer.dart';
import 'chat_controller.dart';
import 'chat_widgets.dart';
import 'markdown_latex_view.dart';
import 'settings_dialog.dart';
import 'cloud_chat_controller.dart';
import 'cloud_drawer.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    this.controller,
    this.accountEmail,
    this.onSignOut,
    super.key,
  });

  final ChatController? controller;
  final String? accountEmail;
  final Future<void> Function()? onSignOut;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  late final ChatController _controller;
  bool _ownsController = false;
  final ValueNotifier<bool> _showScrollToBottomNotifier = ValueNotifier<bool>(
    false,
  );
  bool _isUserTouching = false;
  bool _isUserDragging = false;
  bool _isUserScrollingUp = false;
  final Map<String, Widget> _messageWidgetCache = <String, Widget>{};
  bool? _lastConversationIsDark;
  String? _lastRoom;
  bool _loadingEarlier = false;
  CloudChatController? get _cloud =>
      _controller is CloudChatController ? _controller : null;

  Future<void> _loadEarlier() async {
    final cloud = _cloud;
    if (cloud == null ||
        !cloud.hasMoreMessages ||
        cloud.refreshing ||
        _loadingEarlier ||
        !_scrollController.hasClients) {
      return;
    }
    _loadingEarlier = true;
    _isUserScrollingUp = true;
    final room = cloud.activeRoomId,
        extent = _scrollController.position.maxScrollExtent,
        offset = _scrollController.offset;
    await cloud.moreMessages();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          room == cloud.activeRoomId &&
          _scrollController.hasClients) {
        _scrollController.jumpTo(
          (offset + _scrollController.position.maxScrollExtent - extent).clamp(
            0,
            _scrollController.position.maxScrollExtent,
          ),
        );
      }
      _loadingEarlier = false;
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = ChatController();
      _ownsController = true;
      _controller.init();
    }
    _controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    if (_ownsController) {
      _controller.dispose();
    }
    _showScrollToBottomNotifier.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (_lastRoom != _cloud?.activeRoomId) {
      _lastRoom = _cloud?.activeRoomId;
      _messageWidgetCache.clear();
      _messageController.clear();
      _isUserScrollingUp = false;
    }
    _handleStreamingAutoScroll();
  }

  /// การเลื่อนตำแหน่งหน้าจอแบบ Real-time ตอนสตรีมมิ่งข้อความ
  /// - จะไม่เลื่อนเด็ดขาดถ้านิ้วผู้ใช้กำลังแตะหน้าจออยู่ (_isUserTouching) หรือกำลังลาก (_isUserDragging)
  /// - จะไม่กระชากกลับลงล่างถ้าผู้ใช้เลื่อนขึ้นไปอ่านข้อความเก่าก่อนหน้า (_isUserScrollingUp)
  /// - ใช้ jumpTo แทน animateTo เพื่อไม่ให้มี AnimationController ค้างไปแย่ง scroll physics กับนิ้วผู้ใช้
  void _handleStreamingAutoScroll() {
    if (_isUserTouching || _isUserDragging || _isUserScrollingUp) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_isUserTouching || _isUserDragging || _isUserScrollingUp) return;

      final double max = _scrollController.position.maxScrollExtent;
      final double offset = _scrollController.offset;

      if (max - offset > 1.0) {
        _scrollController.jumpTo(max);
      }
    });
  }

  /// เลื่อนลงมาล่างสุดแบบนุ่มนวล (สำหรับตอนส่งข้อความ หรือแตะปุ่มเลื่อนลงล่างสุด)
  void _scrollToBottomAnimated() {
    _isUserScrollingUp = false;
    _isUserDragging = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });

    // เลื่อนตามซ้ำอีกครั้งหลังจากแอนิเมชันคีย์บอร์ดหุบลงเสร็จสมบูรณ์ (280ms) เพื่อให้เห็นแชตเต็มจอ
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (mounted &&
          _scrollController.hasClients &&
          !_isUserScrollingUp &&
          !_isUserDragging &&
          !_isUserTouching) {
        final double max = _scrollController.position.maxScrollExtent;
        if ((max - _scrollController.offset).abs() > 2.0) {
          _scrollController.animateTo(
            max,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  void _sendMessage() {
    if (_cloud != null && !_cloud!.canSend) return;
    final String text = _messageController.text.trim();
    if (text.isEmpty || _controller.isLoading) {
      _messageFocusNode.requestFocus();
      return;
    }

    // ซ่อนคีย์บอร์ดทันที เพื่อเปิดพื้นที่หน้าจอให้ข้อความเลื่อนสตรีมได้อย่างเต็มที่
    _messageFocusNode.unfocus();
    _isUserScrollingUp = false;
    _isUserDragging = false;

    _messageController.clear();
    _controller.sendMessage(text);
    _scrollToBottomAnimated();
  }

  void _sendMessageWithText(String text) {
    if (_cloud != null && !_cloud!.canSend) return;
    if (text.trim().isEmpty || _controller.isLoading) return;

    _messageFocusNode.unfocus();
    _isUserScrollingUp = false;
    _isUserDragging = false;

    _messageController.clear();
    _controller.sendMessage(text.trim());
    _scrollToBottomAnimated();
  }

  Future<void> _openSettings() async {
    await _controller.init();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return SettingsDialog(controller: _controller);
      },
    );
  }

  void _showModelPicker() {
    showModelPickerSheet(
      context: context,
      currentModel: _controller.selectedModel,
      availableModels: _controller.availableModels,
      onModelSelected: (String model) {
        _controller.setSelectedModel(model);
      },
      onOpenSettings: _openSettings,
    );
  }

  void _onAttachmentActionSelected(String action) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ฟีเจอร์ $action (เตรียมพร้อมสำหรับเวอร์ชันถัดไป)'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showMicrophoneMessage() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: <Widget>[
            Icon(Icons.mic_none_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'แตะค้างเพื่อพูดกับ BlueAI (เตรียมพร้อมสำหรับเวอร์ชันถัดไป)',
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _startNewChat() {
    _controller.clearChat();
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: isDark
            ? BlueAIPalette.darkBackground
            : Colors.white,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: isDark ? BlueAIPalette.darkBackground : Colors.white,
        drawer: _cloud != null
            ? CloudDrawer(
                controller: _cloud!,
                email: widget.accountEmail,
                onSignOut: widget.onSignOut,
                onSettings: _openSettings,
              )
            : ChatDrawer(
                controller: _controller,
                onNewChat: () {
                  Navigator.of(context).pop();
                  _startNewChat();
                },
                onShowSettings: () {
                  Navigator.of(context).pop();
                  _openSettings();
                },
              ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    // 1. หน้าต่างบทสนทนา (แสดงรายการข้อความพร้อมขอบเลือนรางทั้งบนและล่างก่อนหาย)
                    Positioned.fill(
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) {
                          const double topFadeStart = 20.0;
                          const double topFadeEnd = 68.0;
                          const double bottomFadeLength = 28.0;

                          if (bounds.height <= 0) {
                            return const LinearGradient(
                              colors: <Color>[Colors.white, Colors.white],
                            ).createShader(bounds);
                          }
                          final double topStartStop =
                              (topFadeStart / bounds.height).clamp(0.0, 1.0);
                          final double topEndStop = (topFadeEnd / bounds.height)
                              .clamp(0.0, 1.0);
                          final double bottomStartStop =
                              ((bounds.height - bottomFadeLength) /
                                      bounds.height)
                                  .clamp(topEndStop, 1.0);

                          return LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: const <Color>[
                              Colors.transparent,
                              Colors.transparent,
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: <double>[
                              0.0,
                              topStartStop,
                              topEndStop,
                              bottomStartStop,
                              1.0,
                            ],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.dstIn,
                        child: ListenableBuilder(
                          listenable: _controller,
                          builder: (BuildContext context, Widget? child) {
                            return _controller.messages.isEmpty &&
                                    !_controller.isLoading
                                ? WelcomeView(
                                    onPromptSelected: _sendMessageWithText,
                                  )
                                : _buildConversation(isDark);
                          },
                        ),
                      ),
                    ),

                    // 2. แถบเครื่องมือด้านบนแบบลอยตัว (Top Bar)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildTopBar(isDark),
                    ),

                    // 3. ปุ่มเลื่อนลงล่างสุด ลอยอยู่เหนือ Composer
                    Positioned(
                      right: 20,
                      bottom: 12,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _showScrollToBottomNotifier,
                        builder:
                            (BuildContext context, bool show, Widget? child) {
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder:
                                    (
                                      Widget child,
                                      Animation<double> animation,
                                    ) {
                                      return ScaleTransition(
                                        scale: animation,
                                        child: FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        ),
                                      );
                                    },
                                child: show
                                    ? ScrollToBottomButton(
                                        key: const ValueKey<String>(
                                          'scroll_btn',
                                        ),
                                        onPressed: _scrollToBottomAnimated,
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey<String>('empty'),
                                      ),
                              );
                            },
                      ),
                    ),
                  ],
                ),
              ),

              if (_cloud != null)
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    final cloud = _cloud!;
                    final message =
                        cloud.cloudError ??
                        (!cloud.online
                            ? 'ออฟไลน์ — พิมพ์ร่างได้ ส่งเมื่อเชื่อมต่อแล้ว'
                            : cloud.remoteRunning && !cloud.isLoading
                            ? 'ห้องนี้กำลังตอบบนอีกอุปกรณ์'
                            : null);
                    if (message == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (cloud.canRetry)
                            TextButton(
                              onPressed: cloud.retryLastRequest,
                              child: const Text('ตรวจ/ลองใหม่'),
                            ),
                          IconButton(
                            onPressed: cloud.refreshing ? null : cloud.refresh,
                            tooltip: 'รีเฟรช',
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              // 4. Composer ด้านล่าง พื้นหลังทึบเรียบหรู ไม่ซึมล้น
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListenableBuilder(
                      listenable: Listenable.merge(<Listenable>[
                        _controller.isLoadingNotifier,
                        _controller.selectedModelNotifier,
                        if (_cloud != null) _controller,
                      ]),
                      builder: (BuildContext context, Widget? child) {
                        return ChatComposer(
                          controller: _messageController,
                          focusNode: _messageFocusNode,
                          selectedModel: _controller.selectedModel,
                          isLoading: _controller.isLoading,
                          sendEnabled: _cloud?.canSend ?? true,
                          onActionSelected: _onAttachmentActionSelected,
                          onModelTap: _showModelPicker,
                          onMicrophoneTap: _showMicrophoneMessage,
                          onSend: _sendMessage,
                          onStop: _controller.stopGeneration,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    final Color iconColor = BlueAIPalette.text(isDark);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: <Widget>[
          // ปุ่มเมนู 3 ขีด ตามแบบอ้างอิง (2 ขีดบนยาว ขีดล่างสั้นชิดซ้าย)
          Semantics(
            label: 'เปิดเมนู',
            button: true,
            child: IconButton(
              tooltip: 'เปิดเมนู',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: SizedBox(
                width: 22,
                height: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Container(
                      height: 2,
                      width: 22,
                      decoration: BoxDecoration(
                        color: iconColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    Container(
                      height: 2,
                      width: 22,
                      decoration: BoxDecoration(
                        color: iconColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    Container(
                      height: 2,
                      width: 12,
                      decoration: BoxDecoration(
                        color: iconColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // ปุ่มแชตใหม่ ไอคอนกล่องข้อความพร้อมเครื่องหมายบวกตามแบบอ้างอิง
          Semantics(
            label: 'แชตใหม่',
            button: true,
            child: IconButton(
              tooltip: 'แชตใหม่',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: _startNewChat,
              icon: Icon(Icons.add_comment_rounded, size: 22, color: iconColor),
            ),
          ),
          // ปุ่ม 3 จุด (ตัวเลือกเพิ่มเติม) ตามแบบอ้างอิง
          PopupMenuButton<String>(
            tooltip: 'ตัวเลือกเพิ่มเติม',
            icon: Icon(Icons.more_vert_rounded, size: 22, color: iconColor),
            constraints: const BoxConstraints(minWidth: 180),
            onSelected: (String value) {
              if (value == 'new_chat') {
                _startNewChat();
              } else if (value == 'settings') {
                _openSettings();
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'new_chat',
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.add_comment_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('เริ่มการสนทนาใหม่'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.tune_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('การตั้งค่าระบบและโมเดล'),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
    );
  }

  Widget _buildConversation(bool isDark) {
    final List<ChatMessage> messages = _controller.messages;
    final bool isLoading = _controller.isLoading;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    // isLoading คงอยู่ตลอดช่วงสตรีม แถว "กำลังคิด" จึงแสดงเฉพาะก่อนข้อความ AI ชิ้นแรกจะมาถึง
    final bool showThinkingRow =
        isLoading && messages.isNotEmpty && messages.last.isUser;
    final int itemCount = messages.length + (showThinkingRow ? 1 : 0);

    if (_lastConversationIsDark != isDark || messages.isEmpty) {
      _messageWidgetCache.clear();
      _lastConversationIsDark = isDark;
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Listener(
          onPointerDown: (_) {
            _isUserTouching = true;
          },
          onPointerUp: (_) {
            _isUserTouching = false;
          },
          onPointerCancel: (_) {
            _isUserTouching = false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              if (notification is ScrollUpdateNotification &&
                  notification.metrics.pixels < 100) {
                _loadEarlier();
              }
              if (notification is ScrollStartNotification) {
                if (notification.dragDetails != null) {
                  _isUserDragging = true;
                }
              } else if (notification is UserScrollNotification) {
                if (notification.direction == ScrollDirection.reverse) {
                  // ผู้ใช้กำลังลากเลื่อนลงมาด้านล่าง
                  if (_scrollController.hasClients) {
                    final double max =
                        _scrollController.position.maxScrollExtent;
                    final double offset = _scrollController.offset;
                    if (max - offset <= 70) {
                      _isUserScrollingUp = false;
                    }
                  }
                } else if (notification.direction == ScrollDirection.forward) {
                  // ผู้ใช้กำลังลากเลื่อนขึ้นไปอ่านข้อความเก่า
                  _isUserScrollingUp = true;
                }
              } else if (notification is ScrollEndNotification) {
                _isUserDragging = false;
                if (_scrollController.hasClients) {
                  final double max = _scrollController.position.maxScrollExtent;
                  final double offset = _scrollController.offset;
                  if (max - offset <= 70) {
                    _isUserScrollingUp = false;
                  }
                }
              } else if (notification is ScrollUpdateNotification) {
                if (_scrollController.hasClients) {
                  final double max = _scrollController.position.maxScrollExtent;
                  final double offset = _scrollController.offset;
                  final bool show = (max - offset) > 120;
                  if (show != _showScrollToBottomNotifier.value) {
                    _showScrollToBottomNotifier.value = show;
                  }
                  if (max - offset <= 70 &&
                      !_isUserDragging &&
                      !_isUserTouching) {
                    _isUserScrollingUp = false;
                  }
                }
              }
              return false;
            },
            child: ListView.separated(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              addAutomaticKeepAlives: true,
              addRepaintBoundaries: true,
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 36),
              itemCount: itemCount,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 20),
              itemBuilder: (BuildContext context, int index) {
                // เมื่อกำลังคิดหรือสตรีมคำตอบ (Image 1: กำลังคิดเป็นเวลา Xs)
                if (index == messages.length && showThinkingRow) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: ThinkingIndicator(
                      isThinking: true,
                      thinkingSeconds: _controller.currentThinkingSeconds,
                    ),
                  );
                }

                final ChatMessage message = messages[index];
                final bool isLast = (index == messages.length - 1);
                final bool isStreamingLast =
                    message.status == 'streaming' || isLast && isLoading;

                final String cacheKey =
                    'msg_${message.id}_${message.status}_${message.errorMessage}_${index}_${message.timestamp?.millisecondsSinceEpoch}_${message.text.hashCode}_${message.reasoningText.hashCode}_$isDark';

                if (!isStreamingLast) {
                  final Widget? cached = _messageWidgetCache[cacheKey];
                  if (cached != null) {
                    return cached;
                  }
                }

                Widget content;

                // 1. ข้อความฝั่งผู้ใช้ - ใช้สีและขอบแบบเดียวกับ Code Box
                if (message.isUser) {
                  final Color userBubbleBg = BlueAIPalette.codeBackground(
                    isDark,
                  );
                  final Color userTextColor = BlueAIPalette.text(isDark);

                  content = Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: screenWidth > 640 ? 540 : screenWidth * 0.82,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: userBubbleBg,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(6),
                        ),
                      ),
                      child: SelectionArea(
                        child: Text(
                          message.text,
                          style: TextStyle(
                            color: userTextColor,
                            fontSize: 16.5,
                            height: 1.4,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                } else if (message.isError) {
                  // 2. ข้อความแจ้งเตือนข้อผิดพลาด (Error Message)
                  content = Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0x337F1D1D)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0x4DEF4444),
                        width: 1,
                      ),
                    ),
                    child: MarkdownLatexView(
                      data: [
                        message.text,
                        if (message.errorMessage != null) message.errorMessage!,
                      ].where((s) => s.isNotEmpty).join('\n\n'),
                      textStyle: TextStyle(
                        color: isDark
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFF991B1B),
                        fontSize: 15.5,
                      ),
                    ),
                  );
                } else {
                  // 3. ข้อความฝั่ง AI (Assistant) - ชิดซ้าย พร้อม Thinking Indicator
                  final bool isThinkingPhase =
                      isStreamingLast && message.text.isEmpty;

                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // แถบสถานะคิด (ขณะคิดสด หรือเมื่อคิดเสร็จแล้ว)
                      if (isThinkingPhase)
                        ThinkingIndicator(
                          isThinking: true,
                          thinkingSeconds:
                              _controller.currentThinkingSeconds > 0
                              ? _controller.currentThinkingSeconds
                              : (message.thinkingDurationSeconds ?? 1),
                          reasoningText: message.reasoningText,
                        )
                      else if (message.reasoningText != null &&
                          message.reasoningText!.trim().isNotEmpty)
                        ThinkingIndicator(
                          isThinking: false,
                          thinkingSeconds: message.thinkingDurationSeconds,
                          reasoningText: message.reasoningText,
                        ),

                      // Markdown + LaTeX + Code Box + Table (แสดงเมื่อเริ่มมีข้อความ)
                      if (message.text.isNotEmpty)
                        MarkdownLatexView(
                          data: message.text,
                          textStyle: TextStyle(
                            color: BlueAIPalette.text(isDark),
                            fontSize: 16.5,
                            height: 1.55,
                          ),
                        ),

                      if (message.status == 'stopped')
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('หยุดการตอบแล้ว'),
                        ),
                      if (!isStreamingLast) ...<Widget>[
                        const SizedBox(height: 4),
                        MessageActionToolbar(
                          messageText: message.text,
                          modelName: message.model ?? _controller.selectedModel,
                        ),
                      ],
                    ],
                  );
                }

                final Widget item = _KeepAliveMessageItem(
                  key: ValueKey<Object>(message.id ?? index),
                  child: content,
                );

                if (!isStreamingLast) {
                  _messageWidgetCache[cacheKey] = item;
                }

                return item;
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// วิดเจ็ตห่อหุ้มข้อความแชต เพื่อรักษา State และแคช RenderObject ในหน่วยความจำตอนเลื่อนจอ
class _KeepAliveMessageItem extends StatefulWidget {
  const _KeepAliveMessageItem({required this.child, super.key});

  final Widget child;

  @override
  State<_KeepAliveMessageItem> createState() => _KeepAliveMessageItemState();
}

class _KeepAliveMessageItemState extends State<_KeepAliveMessageItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}
