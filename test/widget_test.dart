// Smoke test dasar. Test penuh app (dengan Provider + DB lokal) menyusul
// setelah lapisan data di-mock. Untuk sekarang cukup pastikan widget dasar render.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke: judul app render', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Ruang Senyawa POS'))),
      ),
    );
    expect(find.text('Ruang Senyawa POS'), findsOneWidget);
  });
}
