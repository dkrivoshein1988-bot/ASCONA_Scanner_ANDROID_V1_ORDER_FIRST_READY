import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/return_record.dart';

class ReturnStorage {
  static const _recordsKey = 'return_records';
  static const _settingsKey = 'return_settings';

  Future<List<ReturnRecord>> loadRecords() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_recordsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((item) => ReturnRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveRecords(List<ReturnRecord> records) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _recordsKey,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
  }

  Future<Map<String, dynamic>> loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_settingsKey, jsonEncode(settings));
  }
}
