import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfcraft_mobile/services/signature_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pdfcraft.pdfcraft_mobile/paths');
  late Directory dir;

  Future<void> mockChannel() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getSupportDir') return dir.path;
          return null;
        });
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sigstore');
    await mockChannel();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('typed name round-trips trimmed; missing store reads null', () async {
    final store = SignatureStore();
    expect(await store.loadTypedName(), isNull);
    await store.saveTypedName('   ');
    expect(await store.loadTypedName(), isNull);
    await store.saveTypedName('  Ada Lovelace  ');
    expect(await store.loadTypedName(), 'Ada Lovelace');
  });

  test('drawn png round-trips; empty bytes never persist', () async {
    final store = SignatureStore();
    expect(await store.loadDrawn(), isNull);
    await store.saveDrawn(Uint8List(0));
    expect(await store.loadDrawn(), isNull);
    final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
    await store.saveDrawn(png);
    expect(await store.loadDrawn(), png);
  });
}
