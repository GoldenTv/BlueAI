import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_controller.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.model,
    this.pinned = false,
  });
  final String id, title, model;
  final bool pinned;
  factory Conversation.fromJson(Map<String, dynamic> row) => Conversation(
    id: row['id'] as String,
    title: row['title'] as String,
    model: row['model'] as String,
    pinned: row['is_pinned'] as bool,
  );
}

abstract class ChatRepository {
  String get userId;
  Future<List<Conversation>> rooms(int limit);
  Future<Conversation?> room(String id);
  Future<List<ChatMessage>> messages(String id, int limit);
  Future<void> create(String id, String title, String model);
  Future<void> edit(String id, {String? title, String? model, bool? pinned});
  Future<void> delete(String id);
  Future<void> recover(String id);
  Future<Map<String, dynamic>?> run(String id);
  void watch(
    String? room,
    void Function() changed,
    void Function(bool) connected,
  );
  Future<void> dispose();
}

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this.client, this.userId);
  final SupabaseClient client;
  @override
  final String userId;
  RealtimeChannel? _channel;
  int _watchVersion = 0;

  @override
  Future<List<Conversation>> rooms(int limit) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; offset < limit; offset += 30) {
      final size = (limit - offset).clamp(0, 30);
      final page = await client
          .from('conversations')
          .select()
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('is_pinned', ascending: false)
          .order('updated_at', ascending: false)
          .order('id')
          .range(offset, offset + size - 1);
      rows.addAll(page);
      if (page.length < size) break;
    }
    return rows.map(Conversation.fromJson).toList();
  }

  @override
  Future<Conversation?> room(String id) async {
    final row = await client
        .from('conversations')
        .select()
        .eq('id', id)
        .isFilter('deleted_at', null)
        .maybeSingle();
    return row == null ? null : Conversation.fromJson(row);
  }

  @override
  Future<List<ChatMessage>> messages(String id, int limit) async {
    final rows = <Map<String, dynamic>>[];
    int? before;
    while (rows.length < limit) {
      final size = (limit - rows.length).clamp(0, 50);
      var query = client.from('messages').select().eq('conversation_id', id);
      if (before != null) query = query.lt('sequence', before);
      final page = await query.order('sequence', ascending: false).limit(size);
      rows.addAll(page);
      if (page.length < size) break;
      before = page.last['sequence'] as int;
    }
    return rows.reversed
        .map(
          (row) => ChatMessage(
            id: row['id'] as String,
            conversationId: id,
            turnId: row['turn_id'] as String,
            sequence: row['sequence'] as int,
            text: row['content'] as String,
            isUser: row['role'] == 'user',
            status: row['status'] as String,
            isError: ['error', 'interrupted'].contains(row['status']),
            errorMessage: row['error_message'] as String?,
            reasoningText: row['reasoning'] as String?,
            model: row['model'] as String,
            timestamp: DateTime.parse(row['created_at'] as String),
            thinkingDurationSeconds: row['thinking_seconds'] as int?,
          ),
        )
        .toList();
  }

  @override
  Future<void> create(String id, String title, String model) async {
    await client.from('conversations').insert({
      'id': id,
      'user_id': userId,
      'title': title,
      'model': model,
    });
  }

  @override
  Future<void> edit(
    String id, {
    String? title,
    String? model,
    bool? pinned,
  }) async {
    await client
        .from('conversations')
        .update({'title': ?title, 'model': ?model, 'is_pinned': ?pinned})
        .eq('id', id);
  }

  @override
  Future<void> delete(String id) async {
    await client.rpc('delete_conversation', params: {'p_conversation_id': id});
  }

  @override
  Future<void> recover(String id) async {
    await client.rpc('recover_chat', params: {'p_conversation_id': id});
  }

  @override
  Future<Map<String, dynamic>?> run(String id) =>
      client.from('chat_runs').select().eq('id', id).maybeSingle();
  @override
  void watch(
    String? room,
    void Function() changed,
    void Function(bool) connected,
  ) {
    final generation = ++_watchVersion;
    final old = _channel;
    if (old != null) unawaited(client.removeChannel(old));
    final channel = client.channel('blueai:$userId:$generation');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'conversations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (_) {
        if (generation == _watchVersion) changed();
      },
    );
    if (room != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: room,
        ),
        callback: (_) {
          if (generation == _watchVersion) changed();
        },
      );
    }
    channel.subscribe((status, error) {
      if (generation == _watchVersion) {
        connected(status == RealtimeSubscribeStatus.subscribed);
      }
    });
    _channel = channel;
  }

  @override
  Future<void> dispose() async {
    ++_watchVersion;
    final channel = _channel;
    _channel = null;
    if (channel != null) await client.removeChannel(channel);
  }
}
