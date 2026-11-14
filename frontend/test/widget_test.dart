import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/shared/widgets/main_navigation.dart';

void main() {
  testWidgets('Ana navigasyon yüklenir', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigation()));

    expect(find.text('Ana Sayfa'), findsWidgets);
    expect(find.text('Oturum'), findsOneWidget);
    expect(find.text('Geçmiş'), findsOneWidget);
    expect(find.text('Analitik'), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
  });
}
