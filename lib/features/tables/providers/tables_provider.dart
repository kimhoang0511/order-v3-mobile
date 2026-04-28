import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/storage/secure_storage.dart';
import '../models/table_item.dart';

// Primary provider — AsyncNotifier with SSE
final tablesNotifierProvider =
    AsyncNotifierProvider.family<TablesNotifier, List<TableItem>, String>(
  TablesNotifier.new,
);

class TablesNotifier extends FamilyAsyncNotifier<List<TableItem>, String> {
  HttpClient? _httpClient;
  bool _disposed = false;
  String _sseBuffer = '';

  @override
  Future<List<TableItem>> build(String arg) async {
    ref.onDispose(_dispose);

    if (arg.isEmpty) {
      throw Exception('Chưa có thông tin nhà hàng. Vui lòng đăng nhập lại.');
    }

    final tables = await _fetch(arg);
    _startSse(arg); // fire-and-forget background SSE loop
    return tables;
  }

  // ── Fetch ────────────────────────────────────────────────────────────────

  Future<List<TableItem>> _fetch(String slug) async {
    final api = ref.read(apiClientProvider);
    final response = await api.get('/api/restaurants/$slug/tables');
    final list = (response.data as List)
        .map((e) => TableItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return sortTables(list);
  }

  // ── SSE ──────────────────────────────────────────────────────────────────

  Future<void> _startSse(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final token = await AppSecureStorage.read(AppConstants.authTokenKey);
    final baseUrl =
        prefs.getString(AppConstants.apiBasePathKey) ?? AppConstants.defaultApiUrl;
    final uri = Uri.parse(
        '$baseUrl/api/sse/restaurant/${Uri.encodeComponent(slug)}');

    while (!_disposed) {
      _httpClient = HttpClient();
      try {
        final request = await _httpClient!.getUrl(uri);
        request.headers.set('Accept', 'text/event-stream');
        request.headers.set('Cache-Control', 'no-cache');
        if (token != null) {
          request.headers.set('Authorization', 'Bearer $token');
        }

        final response = await request.close();
        if (response.statusCode != 200) {
          _httpClient?.close(force: true);
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }

        await for (final chunk in response.transform(utf8.decoder)) {
          if (_disposed) break;
          _parseChunk(chunk);
        }
      } catch (_) {
        // connection lost or disposed — will retry
      }

      _httpClient?.close(force: true);
      _httpClient = null;
      if (!_disposed) await Future.delayed(const Duration(seconds: 3));
    }
  }

  void _parseChunk(String chunk) {
    _sseBuffer += chunk;
    final lines = _sseBuffer.split('\n');
    _sseBuffer = lines.last; // keep any incomplete trailing line

    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('data:')) continue;
      final jsonStr = line.substring(5).trim();
      try {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        _handleEvent(data);
      } catch (_) {}
    }
  }

  // ── Event handling ────────────────────────────────────────────────────────

  void _handleEvent(Map<String, dynamic> data) {
    if (data['type'] != 'table_redirect_changed') return;

    final fromTable = data['from_table'] as String?;
    final toTable = data['to_table'] as String?;
    final action = data['action'] as String?;

    if (fromTable == null) return;

    _patchState(
      fromTable: fromTable,
      toTable: action == 'merge' ? toTable : null,
    );
  }

  void _patchState({required String fromTable, required String? toTable}) {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncData(current.map((t) {
      if (t.tableNumber == fromTable) {
        return toTable != null
            ? t.copyWith(redirectTo: toTable)
            : t.copyWith(clearRedirect: true);
      }
      // Re-point cascaded merges (web logic: if t was already merged into
      // fromTable, move it to the new destination)
      if (toTable != null && t.redirectTo == fromTable) {
        return t.copyWith(redirectTo: toTable);
      }
      return t;
    }).toList());
  }

  // ── Public methods ────────────────────────────────────────────────────────

  /// Optimistic local update after merge/split — SSE will confirm asynchronously.
  void applyOptimisticChange(String fromTableNumber, String? toTableNumber) {
    _patchState(fromTable: fromTableNumber, toTable: toTableNumber);
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  void _dispose() {
    _disposed = true;
    _httpClient?.close(force: true);
    _httpClient = null;
  }
}
