import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'ai_gateway_service.dart';
import 'api_key_store.dart';
import 'chat_controller.dart';
import 'cloud_repository.dart';

class CloudChatController extends ChatController {
  CloudChatController({
    required this.repository,
    required this.tokenProvider,
    required ApiKeyStore keyStore,
    super.gatewayService,
    this.monitorConnectivity = true,
    this.onAuthExpired,
  }) : super(apiKeyStore: keyStore, migrateLegacyKey: false);
  final ChatRepository repository;
  final Future<String> Function() tokenProvider;
  final bool monitorConnectivity;
  final void Function()? onAuthExpired;
  final _loading = ValueNotifier<bool>(false);
  final List<ChatMessage> _stored = [];
  final Map<String, List<ChatMessage>> _roomMemory = {};
  List<Conversation> rooms = [];
  String? activeRoomId;
  String? cloudError;
  bool online = true, refreshing = false, transitioning = false;
  bool hasMoreRooms = false, hasMoreMessages = false;
  int _roomLimit = 30, _messageLimit = 50, _view = 0;
  bool _dead = false, _refreshAgain = false, _networkAvailable = true;
  Future<void>? _initFuture, _stopFuture, _refreshFuture;
  Timer? _debounce, _clock, _tokenUpdate;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  String? _requestId;
  Map<String, String>? _retry;
  ChatMessage? _user, _answer;
  int _thinking = 0;
  @override
  List<ChatMessage> get messages => List.unmodifiable([
    ..._stored.where((m) => _requestId == null || m.turnId != _requestId),
    ?_user,
    ?_answer,
  ]);
  @override
  bool get isLoading => _loading.value;
  @override
  ValueNotifier<bool> get isLoadingNotifier => _loading;
  @override
  int get currentThinkingSeconds => _thinking;
  bool get canSend =>
      online && !isLoading && !transitioning && !refreshing && !remoteRunning;
  bool get canRetry => _retry != null && canSend;
  bool get remoteRunning => _stored.any((m) => m.status == 'streaming');
  void _notify() {
    if (!_dead) notifyListeners();
  }

  @override
  Future<void> init() => _initFuture ??= _initializeCloud();
  Future<void> _initializeCloud() async {
    await super.init();
    if (_dead) return;
    if (monitorConnectivity) {
      void update(List<ConnectivityResult> values) {
        if (_dead) return;
        _networkAvailable = !values.contains(ConnectivityResult.none);
        if (!_networkAvailable) {
          online = false;
          _notify();
        } else {
          unawaited(refresh());
        }
      }

      _connectivity = Connectivity().onConnectivityChanged.listen(update);
      update(await Connectivity().checkConnectivity());
    }
    if (_dead) return;
    _watch();
    await refresh();
  }

  void _watch() {
    repository.watch(
      activeRoomId,
      () {
        _debounce?.cancel();
        _debounce = Timer(
          const Duration(milliseconds: 250),
          () => unawaited(refresh()),
        );
      },
      (connected) {
        if (!_dead && connected) unawaited(refresh());
      },
    );
  }

  Future<void> refresh() {
    if (_refreshFuture != null) {
      _refreshAgain = true;
      return _refreshFuture!;
    }
    return _refreshFuture = _drainRefresh().whenComplete(
      () => _refreshFuture = null,
    );
  }

  Future<void> _drainRefresh() async {
    do {
      _refreshAgain = false;
      await _refresh();
    } while (_refreshAgain && !_dead);
  }

  Future<void> _refresh() async {
    if (_dead || !_networkAvailable) return;
    refreshing = true;
    final view = _view, room = activeRoomId;
    try {
      final latest = await repository.rooms(_roomLimit);
      Conversation? current;
      List<ChatMessage>? history;
      if (room != null) {
        current = await repository.room(room);
        if (current != null) {
          await repository.recover(room);
          history = await repository.messages(room, _messageLimit);
        }
      }
      if (_dead || view != _view) return;
      rooms = latest;
      hasMoreRooms = latest.length == _roomLimit;
      online = true;
      if (cloudError == 'ซิงก์ไม่สำเร็จ ตรวจการเชื่อมต่อแล้วลองใหม่') {
        cloudError = null;
      }
      if (room != null && current == null) {
        _roomMemory.remove(room);
        gatewayService.cancelActiveRequest();
        _clock?.cancel();
        _loading.value = false;
        activeRoomId = null;
        _requestId = null;
        _user = null;
        _answer = null;
        _stored.clear();
        _retry = null;
        _view++;
        _watch();
      } else if (history != null) {
        _roomMemory[room!] = List.of(history);
        _stored
          ..clear()
          ..addAll(history);
        hasMoreMessages = history.length == _messageLimit;
        if (!isLoading &&
            history.any(
              (m) =>
                  m.turnId == _requestId &&
                  !m.isUser &&
                  m.status != 'streaming',
            )) {
          _requestId = null;
          _user = null;
          _answer = null;
        }
        if (!isLoading) await super.setSelectedModel(current!.model);
      }
    } catch (_) {
      if (!_dead && view == _view) {
        online = false;
        cloudError = 'ซิงก์ไม่สำเร็จ ตรวจการเชื่อมต่อแล้วลองใหม่';
      }
    } finally {
      refreshing = false;
      _notify();
    }
  }

  Future<void> moreRooms() async {
    _roomLimit += 30;
    await refresh();
  }

  Future<void> moreMessages() async {
    _messageLimit += 50;
    await refresh();
  }

  Future<void> openRoom(String? id) async {
    if (transitioning || id == activeRoomId && id != null) return;
    transitioning = true;
    _notify();
    await stopAndSave();
    if (_dead) return;
    _view++;
    activeRoomId = id;
    _messageLimit = 50;
    _stored
      ..clear()
      ..addAll(_roomMemory[id] ?? []);
    _user = null;
    _answer = null;
    _requestId = null;
    _retry = null;
    cloudError = null;
    _watch();
    transitioning = false;
    _notify();
    await refresh();
  }

  @override
  void clearChat() {
    unawaited(openRoom(null));
  }

  Future<void> editRoom(
    Conversation room, {
    String? title,
    bool? pinned,
  }) async {
    if (!online) return;
    try {
      await repository.edit(room.id, title: title, pinned: pinned);
      await refresh();
    } catch (_) {
      cloudError = 'บันทึกการแก้ไขห้องไม่สำเร็จ';
      _notify();
    }
  }

  Future<void> deleteRoom(String id) async {
    if (!online) return;
    if (id == activeRoomId) await stopAndSave();
    try {
      await repository.delete(id);
      _roomMemory.remove(id);
      if (id == activeRoomId) {
        await openRoom(null);
      } else {
        await refresh();
      }
    } catch (_) {
      cloudError = 'ลบห้องไม่สำเร็จ กรุณาลองใหม่';
      _notify();
    }
  }

  @override
  Future<void> setSelectedModel(String model) async {
    if (!online || isLoading) return;
    final room = activeRoomId;
    if (room != null) {
      try {
        await repository.edit(room, model: model);
      } catch (_) {
        cloudError = 'บันทึกโมเดลไม่สำเร็จ';
        _notify();
        return;
      }
    }
    await super.setSelectedModel(model);
  }

  @override
  Future<void> sendMessage(String text) async {
    if (!canSend || text.trim().isEmpty) return;
    await _send(text.trim());
  }

  Future<void> retryLastRequest() async {
    final payload = _retry;
    if (payload == null || !canRetry) return;
    await _send(payload['prompt']!, retry: payload);
  }

  Future<void> _send(String prompt, {Map<String, String>? retry}) async {
    _loading.value = true;
    cloudError = null;
    _thinking = 0;
    _notify();
    final view = ++_view;
    String? requestId;
    try {
      await init();
      if (_dead || view != _view) return;
      if (initializationError != null) throw StateError(initializationError!);
      if (apiKey.isEmpty) {
        throw const GatewayException(
          'AI_KEY_REQUIRED',
          'โปรดใส่ API Key ในหน้าตั้งค่า',
        );
      }
      final token = await tokenProvider();
      if (_dead || view != _view) return;
      if (activeRoomId == null) {
        final id = const Uuid().v4();
        await repository.create(
          id,
          String.fromCharCodes(prompt.runes.take(40)),
          selectedModel,
        );
        if (_dead || view != _view) return;
        activeRoomId = id;
        _watch();
      }
      final payload =
          retry ??
          {
            'conversationId': activeRoomId!,
            'requestId': const Uuid().v4(),
            'messageId': const Uuid().v4(),
            'prompt': prompt,
            'model': selectedModel,
          };
      _retry = payload;
      requestId = payload['requestId'];
      _requestId = requestId;
      _user = ChatMessage(
        id: payload['messageId'],
        conversationId: activeRoomId,
        turnId: requestId,
        text: prompt,
        isUser: true,
        timestamp: DateTime.now(),
      );
      _answer = null;
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        _thinking++;
        _notify();
      });
      _notify();
      await gatewayService.sendMessage(
        cloudRequest: payload,
        accessToken: token,
        onReasoningChunk: (text, reasoning) {
          if (_dead ||
              view != _view ||
              requestId != _requestId ||
              _stopFuture != null) {
            return;
          }
          if (text.isNotEmpty) _clock?.cancel();
          _answer = ChatMessage(
            id: 'pending_$requestId',
            conversationId: activeRoomId,
            turnId: requestId,
            text: text,
            isUser: false,
            reasoningText: reasoning,
            model: payload['model'],
            status: 'streaming',
            timestamp: _answer?.timestamp ?? DateTime.now(),
            thinkingDurationSeconds: _thinking,
          );
          _tokenUpdate ??= Timer(const Duration(milliseconds: 85), () {
            _tokenUpdate = null;
            _notify();
          });
        },
      );
      _retry = null;
    } catch (error) {
      if (_dead || view != _view) return;
      if (error is GatewayException && error.code == 'AUTH_EXPIRED') {
        onAuthExpired?.call();
      }
      if (error is GatewayException && error.code == 'REQUEST_EXISTS') {
        _retry = null;
        cloudError = 'คำขอนี้ถูกบันทึกแล้ว กำลังโหลดสถานะล่าสุด';
      } else if (requestId == _requestId || requestId == null) {
        cloudError = error.toString();
      }
    } finally {
      if (!_dead && view == _view) {
        _clock?.cancel();
        _loading.value = false;
        // Keep partial content visible if confirmation cannot be fetched.
        final localUser = _user, localAnswer = _answer;
        await refresh();
        if (!_dead && view == _view) {
          if (online && _stored.any((m) => m.turnId == requestId)) {
            _requestId = null;
            _user = null;
            _answer = null;
          } else {
            _user = localUser;
            _answer = localAnswer;
          }
          _notify();
        }
      }
    }
  }

  @override
  void stopGeneration() {
    unawaited(stopAndSave());
  }

  Future<void> stopAndSave() =>
      _stopFuture ??= _stop().whenComplete(() => _stopFuture = null);
  Future<void> _stop() async {
    final id = _requestId;
    if (id == null) {
      if (isLoading) {
        _view++;
        _loading.value = false;
      }
      return;
    }
    _clock?.cancel();
    final partial = _answer;
    // Persist the visible partial before aborting, avoiding a stop/save race.
    try {
      await gatewayService.stopCloudRequest(
        id,
        await tokenProvider(),
        partial?.text ?? '',
        partial?.reasoningText,
      );
    } catch (_) {
      if (!_dead) {
        cloudError =
            'ยังยืนยันการบันทึกคำตอบที่หยุดไม่ได้ ตรวจสถานะเมื่อออนไลน์';
      }
    }
    gatewayService.cancelActiveRequest();
    if (!_dead) {
      _loading.value = false;
      _retry = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _dead = true;
    _view++;
    gatewayService.apiKey = '';
    _clock?.cancel();
    _debounce?.cancel();
    _tokenUpdate?.cancel();
    unawaited(_connectivity?.cancel());
    unawaited(repository.dispose());
    _stored.clear();
    _roomMemory.clear();
    _user = null;
    _answer = null;
    rooms = [];
    _loading.dispose();
    super.dispose();
  }
}
