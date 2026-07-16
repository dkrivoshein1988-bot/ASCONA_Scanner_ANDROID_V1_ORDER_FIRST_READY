import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog asset contains the prepared product directory', () async {
    final raw = await rootBundle.loadString('assets/product_catalog.json');
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final items = payload['items'] as List<dynamic>;

    expect(payload['version'], isNotEmpty);
    expect(items.length, 11049);

    final naturalBalance = items
        .cast<Map<String, dynamic>>()
        .where((item) => item['code'] == '4680381351623')
        .toList();
    expect(naturalBalance, hasLength(1));
    expect(
      naturalBalance.single['name'],
      'Простынь Natural Balance 180*200*27 Оливково-серый',
    );

    final ambiguous = items
        .cast<Map<String, dynamic>>()
        .where((item) => item['code'] == '8001000000196000')
        .toList();
    expect(ambiguous, hasLength(2));
  });
}
