import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overline/services/agent/agent_provider.dart';
import 'package:overline/services/agent/cloud_agent_provider.dart';
import 'package:overline/services/billing_service.dart';
import 'package:overline/widgets/paywall_sheet.dart';

void main() {
  group('BillingService', () {
    test('initializes with default freeCore tier', () {
      final billing = BillingService(
        backendUrl: 'https://gateway.example.com',
        getAuthToken: () async => 'test_token',
      );

      expect(billing.isSubscriber, isFalse);
      expect(billing.currentTier, SubscriptionTier.freeCore);
      expect(BillingService.monthlySku, 'overline_pro_monthly');
      expect(BillingService.annualSku, 'overline_pro_annual');
    });

    test('dev toggle updates subscriber state and notifies listeners', () {
      final billing = BillingService(
        backendUrl: 'https://gateway.example.com',
        getAuthToken: () async => 'test_token',
      );

      var notified = false;
      billing.addListener(() => notified = true);

      billing.setDevSubscriberStatus(true);
      expect(billing.isSubscriber, isTrue);
      expect(billing.currentTier, SubscriptionTier.proMonthly);
      expect(notified, isTrue);
    });
  });

  group('CloudAgentProvider', () {
    test('reports correct metadata and checks readiness', () {
      final provider = CloudAgentProvider(
        backendUrl: 'https://gateway.example.com',
        getAuthToken: () async => 'valid_token',
        isSubscriber: true,
      );

      expect(provider.providerId, 'cloud_gemini_pro');
      expect(provider.isLocal, isFalse);
      expect(provider.isReady, isTrue);
      expect(provider.displayName, contains('Gemini 1.5 Pro'));
    });

    test('yields error event when auth token is null', () async {
      final provider = CloudAgentProvider(
        backendUrl: 'https://gateway.example.com',
        getAuthToken: () async => null,
      );

      const ctx = DocumentContext(pageCount: 3, currentPageIndex: 1);
      final events = await provider.runPrompt(
        prompt: 'Summarize document',
        context: ctx,
        tools: [],
      ).toList();

      expect(events.length, 1);
      expect(events.first.type, AgentStepType.error);
      expect(events.first.text, contains('Authentication required'));
    });
  });

  group('PaywallSheet Widget', () {
    testWidgets('renders Overline Pro features and buttons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaywallSheet(),
          ),
        ),
      );

      expect(find.text('Unlock Overline Pro'), findsOneWidget);
      expect(find.text('Always Free On-Device Core'), findsOneWidget);
      expect(find.text('Gemini 1.5 Pro & Claude Intelligence'), findsOneWidget);
      expect(find.text('Start 7-Day Free Trial'), findsOneWidget);
      expect(find.text('Restore Purchases'), findsOneWidget);
    });

    testWidgets('triggers onSubscribeMonthly', (tester) async {
      var monthlyTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaywallSheet(
              onSubscribeMonthly: () => monthlyTapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start 7-Day Free Trial'));
      expect(monthlyTapped, isTrue);
    });

    testWidgets('triggers onRestorePurchases', (tester) async {
      var restoreTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaywallSheet(
              onRestorePurchases: () => restoreTapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Restore Purchases'));
      expect(restoreTapped, isTrue);
    });
  });
}

