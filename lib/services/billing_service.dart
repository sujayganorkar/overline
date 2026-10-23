import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_diagnostics.dart';

enum SubscriptionTier { freeCore, proMonthly, proAnnual }

/// Manages subscription entitlements, remote receipt validation with the Overline backend,
/// and client paywall triggers.
class BillingService extends ChangeNotifier {
  BillingService({
    required this.backendUrl,
    required this.getAuthToken,
    this._isSubscriber = false,
  });

  final String backendUrl;
  final Future<String?> Function() getAuthToken;

  static const String monthlySku = 'overline_pro_monthly';
  static const String annualSku = 'overline_pro_annual';

  bool _isSubscriber;
  bool _isLoading = false;
  SubscriptionTier _currentTier = SubscriptionTier.freeCore;

  bool get isSubscriber => _isSubscriber;
  bool get isLoading => _isLoading;
  SubscriptionTier get currentTier => _currentTier;

  /// Queries the Overline backend to check the authenticated user's subscription entitlement.
  Future<void> checkSubscriptionStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await getAuthToken();
      if (token == null || token.isEmpty) {
        _isSubscriber = false;
        _currentTier = SubscriptionTier.freeCore;
        return;
      }

      final response = await http.get(
        Uri.parse('$backendUrl/v1/user/usage'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _isSubscriber = data['is_subscriber'] == true;
        _currentTier = _isSubscriber ? SubscriptionTier.proMonthly : SubscriptionTier.freeCore;
      }
    } catch (e) {
      debugPrint('Failed to query remote subscription status: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sends a purchase token to the private Overline backend for verification
  /// via the Google Play Developer API v3.
  Future<bool> verifyPurchase({
    required String purchaseToken,
    required String productId,
    String packageName = 'app.overline.pdf',
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await getAuthToken();
      final response = await http.post(
        Uri.parse('$backendUrl/v1/billing/verify-subscription'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'purchase_token': purchaseToken,
          'product_id': productId,
          'package_name': packageName,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final active = data['is_active'] == true;
        if (active) {
          _isSubscriber = true;
          _currentTier = productId == annualSku
              ? SubscriptionTier.proAnnual
              : SubscriptionTier.proMonthly;
          AppDiagnostics.instance.record(
            category: 'billing',
            message: 'Subscription successfully verified with backend: $productId',
          );
          return true;
        }
      }
    } catch (e) {
      AppDiagnostics.instance.record(
        category: 'billing',
        message: 'Subscription verification error: $e',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  /// For dev/testing environments: toggle subscriber status directly.
  void setDevSubscriberStatus(bool active) {
    _isSubscriber = active;
    _currentTier = active ? SubscriptionTier.proMonthly : SubscriptionTier.freeCore;
    notifyListeners();
  }
}

