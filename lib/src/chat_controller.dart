import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_gateway_service.dart';
import 'api_key_store.dart';

/// โมเดลข้อมูลข้อความแชต
class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.model,
    this.timestamp,
    this.thinkingDurationSeconds,
    this.reasoningText,
    this.id,
    this.conversationId,
    this.turnId,
    this.sequence,
    this.status = 'completed',
    this.errorMessage,
  });

  final String text;
  final bool isUser;
  final bool isError;
  final String? model;
  final DateTime? timestamp;
  final int? thinkingDurationSeconds;
  final String? reasoningText;
  final String? id;
  final String? conversationId;
  final String? turnId;
  final int? sequence;
  final String status;
  final String? errorMessage;
}

/// Controller จัดการ State และ Business Logic ทั้งหมดของระบบแชต
class ChatController extends ChangeNotifier {
  ChatController({
    AiGatewayService? gatewayService,
    SharedPreferences? preferences,
    this.apiKeyStore = const ApiKeyStore(),
    this.migrateLegacyKey = true,
  }) : _service = gatewayService ?? AiGatewayService(),
       _prefs = preferences {
    if (_prefs != null) {
      _loadFromPreferences();
    }
  }

  static const String keyBackendUrl = 'blueai_backend_url';
  static const String keyApiKey = 'blueai_api_key';
  static const String keySelectedModel = 'blueai_selected_model';
  static const String keyAvailableModels = 'blueai_available_models';
  static const String keyThemeMode = 'blueai_theme_mode';

  static const List<String> defaultModels = <String>[
    'openai/gpt-5.6-luna',
    'deepseek/deepseek-v4-flash-0731',
    'PSU-LLM/psu-gemma',
  ];

  final AiGatewayService _service;
  final ApiKeyStore apiKeyStore;
  final bool migrateLegacyKey;
  Future<void>? _initialization;
  String? _initializationError;
  String? get initializationError => _initializationError;
  SharedPreferences? _prefs;

  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _isLoading = false;
  late final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(
    _isLoading,
  );
  ThemeMode _themeMode = ThemeMode.system;
  late final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier<ThemeMode>(_themeMode);
  Timer? _thinkingTimer;
  Timer? _streamThrottleTimer;
  bool _hasPendingStreamUpdate = false;
  int _currentThinkingSeconds = 0;

  /// ตัวนับรอบการ request — เพิ่มทุกครั้งที่ส่งข้อความใหม่ / กด Stop / ล้างแชต
  /// ใช้กรอง callback ของ request เก่าที่ยังค้าง ไม่ให้ไปแตะ state รอบใหม่
  int _generation = 0;
  bool _disposed = false;

  String _selectedModel = defaultModels.first;
  late final ValueNotifier<String> _selectedModelNotifier =
      ValueNotifier<String>(_selectedModel);
  List<String> _availableModels = List<String>.from(defaultModels);

  // Getters
  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  ValueNotifier<bool> get isLoadingNotifier => _isLoadingNotifier;
  ThemeMode get themeMode => _themeMode;
  ValueNotifier<ThemeMode> get themeModeNotifier => _themeModeNotifier;
  int get currentThinkingSeconds => _currentThinkingSeconds;
  String get selectedModel => _selectedModel;
  ValueNotifier<String> get selectedModelNotifier => _selectedModelNotifier;
  List<String> get availableModels =>
      List<String>.unmodifiable(_availableModels);
  String get backendUrl => _service.backendUrl;
  String get apiKey => _service.apiKey;
  AiGatewayService get gatewayService => _service;

  /// โหลดการตั้งค่าจาก SharedPreferences
  Future<void> init() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      if (_disposed) return;
      _loadFromPreferences();
      String? stored = await apiKeyStore.read();
      final String? legacy = migrateLegacyKey
          ? _prefs?.getString(keyApiKey)
          : null;
      if (stored == null && legacy != null) {
        await apiKeyStore.write(legacy.trim());
        stored = legacy.trim();
      }
      // Remove the old copy only after secure storage succeeds.
      if (legacy != null && !await _prefs!.remove(keyApiKey)) {
        throw StateError('ไม่สามารถลบข้อมูลรับรองเดิมได้');
      }
      if (_disposed) return;
      if (stored != null) _service.apiKey = stored;
      _initializationError = null;
    } catch (_) {
      if (_disposed) return;
      _service.apiKey = '';
      _initializationError =
          'ไม่สามารถเข้าถึงที่จัดเก็บ API Key ได้ โปรดบันทึก API Key อีกครั้ง';
    }
    if (!_disposed) notifyListeners();
  }

  void _loadFromPreferences() {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;

    final String? savedUrl = prefs.getString(keyBackendUrl);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _service.backendUrl = savedUrl;
    }

    final List<String>? savedModels = prefs.getStringList(keyAvailableModels);
    if (savedModels != null && savedModels.isNotEmpty) {
      _availableModels = List<String>.from(savedModels);
    }

    final String? savedSelectedModel = prefs.getString(keySelectedModel);
    if (savedSelectedModel != null && savedSelectedModel.isNotEmpty) {
      if (!_availableModels.contains(savedSelectedModel)) {
        _availableModels.add(savedSelectedModel);
      }
      _setModel(savedSelectedModel);
    } else if (!_availableModels.contains(_selectedModel)) {
      _setModel(_availableModels.first);
    }

    final String? savedTheme = prefs.getString(keyThemeMode);
    if (savedTheme != null && savedTheme.isNotEmpty) {
      _themeMode = ThemeMode.values.firstWhere(
        (ThemeMode m) => m.name == savedTheme,
        orElse: () => ThemeMode.system,
      );
      _themeModeNotifier.value = _themeMode;
    }

    notifyListeners();
  }

  /// เปลี่ยนโหมดธีมของแอป (System, Light, Dark)
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _themeModeNotifier.value = mode;
    await _prefs?.setString(keyThemeMode, mode.name);
    notifyListeners();
  }

  /// สลับโหมดธีมแบบวนรอบ (System -> Light -> Dark -> System)
  Future<void> toggleThemeMode() async {
    final ThemeMode nextMode = switch (_themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setThemeMode(nextMode);
  }

  /// ส่งการแจ้งเตือนสตรีมมิ่งแบบ Throttle (ประมาณ 11-12 FPS ทุกๆ 85ms) เพื่อลดภาระ CPU
  /// และทำให้ตัวหนังสือไหลออกมาอย่างนุ่มนวลเป็นธรรมชาติ ไม่กระตุกเครื่อง
  void _requestThrottledStreamUpdate() {
    if (_disposed) return;
    _hasPendingStreamUpdate = true;
    if (_streamThrottleTimer == null || !_streamThrottleTimer!.isActive) {
      _hasPendingStreamUpdate = false;
      notifyListeners();
      _streamThrottleTimer = Timer(const Duration(milliseconds: 85), () {
        if (_hasPendingStreamUpdate) {
          _hasPendingStreamUpdate = false;
          notifyListeners();
        }
      });
    }
  }

  /// บังคับ Flush การอัปเดตสตรีมมิ่งทันที (เมื่อจบหรือเกิดข้อผิดพลาด)
  void _flushStreamThrottle() {
    _streamThrottleTimer?.cancel();
    _streamThrottleTimer = null;
    if (_hasPendingStreamUpdate) {
      _hasPendingStreamUpdate = false;
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    _isLoadingNotifier.value = value;
  }

  void _setModel(String model) {
    if (_selectedModel == model) return;
    _selectedModel = model;
    _selectedModelNotifier.value = model;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _service.cancelActiveRequest();
    _thinkingTimer?.cancel();
    _streamThrottleTimer?.cancel();
    _themeModeNotifier.dispose();
    _isLoadingNotifier.dispose();
    _selectedModelNotifier.dispose();
    super.dispose();
  }

  /// ล้างประวัติการสนทนาในหน้าจอ
  void clearChat() {
    _generation++;
    _service.cancelActiveRequest();
    _thinkingTimer?.cancel();
    _flushStreamThrottle();
    _currentThinkingSeconds = 0;
    _setLoading(false);
    _messages.clear();
    _service.clearHistory();
    notifyListeners();
  }

  /// หยุดการคิดหรือการสตรีมคำตอบของ AI อย่างสมบูรณ์:
  /// ปิด connection ที่กำลังรับ stream อยู่และบล็อก callback ของรอบนั้นทั้งหมด
  /// ข้อความบางส่วนที่รับมาแล้วจะค้างอยู่บนหน้าจอเหมือนก่อนหน้า
  void stopGeneration() {
    if (!_isLoading) return;
    _generation++;
    _service.cancelActiveRequest();
    _thinkingTimer?.cancel();
    _flushStreamThrottle();
    _setLoading(false);
    notifyListeners();
  }

  /// เปลี่ยนโมเดลที่เลือกใช้งาน
  Future<void> setSelectedModel(String model) async {
    final String trimmed = model.trim();
    if (trimmed.isEmpty || trimmed == _selectedModel) return;

    if (!_availableModels.contains(trimmed)) {
      _availableModels.add(trimmed);
      await _prefs?.setStringList(keyAvailableModels, _availableModels);
    }

    _setModel(trimmed);
    await _prefs?.setString(keySelectedModel, _selectedModel);
    notifyListeners();
  }

  /// เพิ่มโมเดลใหม่ในรายการ
  Future<void> addModel(String model) async {
    final String trimmed = model.trim();
    if (trimmed.isEmpty || _availableModels.contains(trimmed)) return;

    _availableModels.add(trimmed);
    await _prefs?.setStringList(keyAvailableModels, _availableModels);
    notifyListeners();
  }

  /// ลบโมเดลออกจากรายการ
  Future<void> removeModel(String model) async {
    if (_availableModels.length <= 1) return; // ต้องมีโมเดลอย่างน้อย 1 ตัว

    _availableModels.remove(model);
    if (_selectedModel == model) {
      _setModel(_availableModels.first);
      await _prefs?.setString(keySelectedModel, _selectedModel);
    }
    await _prefs?.setStringList(keyAvailableModels, _availableModels);
    notifyListeners();
  }

  /// ตั้งค่าและบันทึก Backend URL
  Future<void> setBackendUrl(String url) async {
    final String trimmed = AiGatewayService.normalizeBackendUrl(url);
    final String effectiveUrl = trimmed.isNotEmpty
        ? trimmed
        : AiGatewayService.defaultBackendUrl;
    _service.backendUrl = effectiveUrl;
    await _prefs?.setString(keyBackendUrl, effectiveUrl);
    notifyListeners();
  }

  /// ตั้งค่าและบันทึก API Key สำหรับ AI Gateway
  Future<void> setApiKey(String key) async {
    await init();
    final String trimmed = key.trim();
    await apiKeyStore.write(trimmed);
    _prefs ??= await SharedPreferences.getInstance();
    if (migrateLegacyKey &&
        _prefs!.containsKey(keyApiKey) &&
        !await _prefs!.remove(keyApiKey)) {
      throw StateError('ไม่สามารถลบ API Key เดิมได้');
    }
    if (_disposed) return;
    _service.apiKey = trimmed;
    _initializationError = null;
    notifyListeners();
  }

  /// ส่งข้อความไปยัง AI
  Future<void> sendMessage(String text) async {
    final String prompt = text.trim();
    if (prompt.isEmpty || _isLoading) return;

    final int generation = ++_generation;
    final DateTime now = DateTime.now();
    _messages.add(ChatMessage(text: prompt, isUser: true, timestamp: now));
    _setLoading(true);
    _currentThinkingSeconds = 0;
    _thinkingTimer?.cancel();
    _thinkingTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      _currentThinkingSeconds++;
      notifyListeners();
    });
    notifyListeners();

    // รวบรวมข้อความที่จะส่งไปยัง AI
    final List<Map<String, String>> historyToSend = <Map<String, String>>[];

    // ส่งประวัติเฉพาะข้อความที่ไม่ใช่ error
    for (final ChatMessage msg in _messages) {
      if (!msg.isError) {
        historyToSend.add(<String, String>{
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.text,
        });
      }
    }

    bool hasAddedAiPlaceholder = false;
    int? lockedThinkingDuration;

    try {
      if (_initialization != null) await _initialization;
      if (_disposed || generation != _generation) return;
      if (_initializationError != null) throw StateError(_initializationError!);
      final String currentModel = _selectedModel;
      final String finalReply = await _service.sendMessage(
        messages: historyToSend,
        model: currentModel,
        onReasoningChunk: (String accumulatedText, String? accumulatedReasoning) {
          // ข้าม chunk ของรอบเก่าหลังกด Stop / ล้างแชต / ปิดแอป
          if (_disposed || generation != _generation) return;

          // หากเริ่มมีข้อความคำตอบหลักเข้ามา ให้หยุดนับเวลาคิดและล็อกเวลาไว้
          if (accumulatedText.isNotEmpty && lockedThinkingDuration == null) {
            _thinkingTimer?.cancel();
            lockedThinkingDuration = _currentThinkingSeconds > 0
                ? _currentThinkingSeconds
                : 1;
          }

          final int elapsed =
              lockedThinkingDuration ??
              (_currentThinkingSeconds > 0 ? _currentThinkingSeconds : 1);

          if (!hasAddedAiPlaceholder) {
            _messages.add(
              ChatMessage(
                text: accumulatedText,
                reasoningText: accumulatedReasoning,
                isUser: false,
                model: currentModel,
                timestamp: DateTime.now(),
                thinkingDurationSeconds: elapsed,
              ),
            );
            hasAddedAiPlaceholder = true;
          } else {
            final ChatMessage last = _messages.last;
            _messages[_messages.length - 1] = ChatMessage(
              text: accumulatedText,
              reasoningText: accumulatedReasoning ?? last.reasoningText,
              isUser: false,
              model: currentModel,
              timestamp: last.timestamp ?? DateTime.now(),
              thinkingDurationSeconds:
                  lockedThinkingDuration ??
                  last.thinkingDurationSeconds ??
                  elapsed,
            );
          }
          _requestThrottledStreamUpdate();
        },
      );

      // Request ถูกยกเลิก (Stop / clearChat / dispose) ระหว่างรอ — หยุดเงียบ ๆ
      // เพื่อไม่ให้ทับข้อความบางส่วนที่ผู้ใช้เพิ่งกดหยุดไว้
      if (_disposed || generation != _generation) return;

      _thinkingTimer?.cancel();
      _flushStreamThrottle();
      final int finalElapsed =
          lockedThinkingDuration ??
          (_currentThinkingSeconds > 0 ? _currentThinkingSeconds : 1);
      _setLoading(false);
      if (!hasAddedAiPlaceholder) {
        _messages.add(
          ChatMessage(
            text: finalReply,
            isUser: false,
            model: currentModel,
            timestamp: DateTime.now(),
            thinkingDurationSeconds: finalElapsed,
          ),
        );
      } else {
        final ChatMessage last = _messages.last;
        _messages[_messages.length - 1] = ChatMessage(
          text: finalReply,
          reasoningText: last.reasoningText,
          isUser: false,
          model: currentModel,
          timestamp: last.timestamp ?? DateTime.now(),
          thinkingDurationSeconds:
              lockedThinkingDuration ??
              last.thinkingDurationSeconds ??
              finalElapsed,
        );
      }
      notifyListeners();
    } catch (error) {
      // Error จากการ abort โดยผู้ใช้ (Stop / clearChat / dispose) ไม่ใช่ความผิดพลาดจริง
      if (_disposed || generation != _generation) return;

      _thinkingTimer?.cancel();
      _flushStreamThrottle();
      _setLoading(false);

      final String errStr = error.toString();
      String hint = '';
      if (errStr.contains('127.0.0.1') || errStr.contains('localhost')) {
        hint =
            '\n\n**แนวทางแก้ไข**: แอปกำลังทำงานบนอุปกรณ์เคลื่อนที่จริง ดังนั้น `127.0.0.1` หมายถึงอุปกรณ์เคลื่อนที่ ไม่ใช่คอมพิวเตอร์\n'
            '- เปิด Terminal แล้วเรียกใช้คำสั่ง `npx wrangler dev --ip 0.0.0.0`\n'
            '- เปลี่ยน URL ในหน้าการตั้งค่าเป็น IP ของคอมพิวเตอร์ เช่น `http://172.24.135.243:8787` หรือ `http://192.168.137.1:8787`';
      } else if (errStr.contains('Failed host lookup') &&
          errStr.contains('blueai-backend.workers.dev')) {
        hint =
            '\n\n**แนวทางแก้ไข**: โดเมนนี้ยังไม่ได้เผยแพร่เพื่อใช้งานจริงบน Cloudflare\n'
            '- เรียกใช้คำสั่ง `npx wrangler deploy` เพื่อรับ URL สำหรับใช้งานจริง\n'
            '- หรือทดสอบการเชื่อมต่อบนคอมพิวเตอร์โดยใช้ IP';
      } else if (errStr.contains('API Key') ||
          errStr.contains('AI_API_KEY') ||
          errStr.contains('401')) {
        hint =
            '\n\n**แนวทางแก้ไข**: ยังไม่ได้ระบุ API Key หรือ API Key ไม่ถูกต้อง\n'
            '- เปิดหน้าการตั้งค่าโดยเลือกปุ่มการตั้งค่าบริเวณมุมขวาบน แล้วระบุ API Key';
      }

      final String errorDetails =
          'รายละเอียดข้อผิดพลาด: `$error`'
          '$hint\n\n'
          '*โมเดลที่เลือก: `$_selectedModel`*';

      if (hasAddedAiPlaceholder &&
          _messages.isNotEmpty &&
          !_messages.last.isUser) {
        final ChatMessage partial = _messages.last;
        _messages[_messages.length - 1] = ChatMessage(
          text:
              '${partial.text}\n\n---\n\n'
              '**การตอบกลับสิ้นสุดลงก่อนดำเนินการเสร็จสมบูรณ์**\n\n$errorDetails',
          isUser: false,
          isError: true,
          model: partial.model,
          timestamp: partial.timestamp,
          thinkingDurationSeconds: partial.thinkingDurationSeconds,
          reasoningText: partial.reasoningText,
        );
      } else {
        _messages.add(
          ChatMessage(
            text: '**ไม่สามารถเชื่อมต่อกับ Backend ได้**\n\n$errorDetails',
            isUser: false,
            isError: true,
          ),
        );
      }
      notifyListeners();
    }
  }
}
