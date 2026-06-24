import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ledger_models.dart';
import 'ledger_providers.dart';

final exchangeRateServiceProvider = Provider((ref) => ExchangeRateService(ref));

class ExchangeRateService {
  final Ref _ref;
  final Dio _client = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 10)),
  );

  ExchangeRateService(this._ref);

  Future<void> refreshRatesIfStale() async {
    final state = _ref.read(ledgerProvider);
    bool isStale = false;

    // Check if any API-provided rate is older than 5 minutes
    for (final rate in state.exchangeRates) {
      if (rate.provider != null &&
          DateTime.now().difference(rate.updatedAt ?? rate.asOfDate) >
              const Duration(minutes: 5)) {
        isStale = true;
        break;
      }
    }

    // Also stale if any enabled currency is missing a rate
    final base = state.preferences.baseCurrency.toUpperCase();
    for (final c in state.preferences.enabledCurrencies) {
      if (c.toUpperCase() == base) continue;
      final hasRate = state.exchangeRates.any(
        (r) =>
            r.base.toUpperCase() == c.toUpperCase() &&
            r.quote.toUpperCase() == base,
      );
      if (!hasRate) {
        isStale = true;
        break;
      }
    }

    if (isStale) {
      try {
        await refreshRates();
      } catch (e) {
        debugPrint('Auto-refresh failed silently: $e');
      }
    }
  }

  Future<void> refreshRates() async {
    final state = _ref.read(ledgerProvider);
    final base = state.preferences.baseCurrency.toLowerCase();

    // We only need to fetch the rates against the base currency
    final url =
        'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/$base.json';

    try {
      final response = await _client.get<String>(url);

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch rates: ${response.statusCode}');
      }

      final responseBody = response.data ?? '{}';
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (!data.containsKey(base)) {
        throw Exception('Base currency not found in response');
      }

      final rates = data[base] as Map<String, dynamic>;
      final updatedRecords = <ExchangeRateRecord>[...state.exchangeRates];
      bool changed = false;

      // Update explicit rates for all enabled currencies
      for (final currency in state.preferences.enabledCurrencies) {
        if (currency.toUpperCase() ==
            state.preferences.baseCurrency.toUpperCase())
          continue;

        final lower = currency.toLowerCase();
        if (rates.containsKey(lower)) {
          // API returns how much of 'currency' equals 1 'baseCurrency'
          // E.g., if baseCurrency is USD, rates['inr'] = 82.90 means 1 USD = 82.90 INR.
          // For base: INR, quote: USD, the rate is 1 / 82.90.
          final apiValue = (rates[lower] as num).toDouble();
          final rateValue = 1.0 / apiValue;

          final existingIndex = updatedRecords.indexWhere(
            (r) =>
                r.base.toUpperCase() == currency.toUpperCase() &&
                r.quote.toUpperCase() ==
                    state.preferences.baseCurrency.toUpperCase(),
          );

          if (existingIndex >= 0 &&
              updatedRecords[existingIndex].provider == null) {
            continue; // Skip overwriting user-provided manual rates
          }

          final newRecord = ExchangeRateRecord(
            base: currency.toUpperCase(),
            quote: state.preferences.baseCurrency.toUpperCase(),
            rate: rateValue,
            asOfDate: DateTime.now(),
            provider: 'fawazahmed0',
          );

          if (existingIndex >= 0) {
            updatedRecords[existingIndex] = newRecord;
          } else {
            updatedRecords.add(newRecord);
          }
          changed = true;
        }
      }

      // Add inverses automatically for completeness
      for (final currency in state.preferences.enabledCurrencies) {
        if (currency.toUpperCase() ==
            state.preferences.baseCurrency.toUpperCase())
          continue;

        final lower = currency.toLowerCase();
        if (rates.containsKey(lower)) {
          // The API returns exactly this: 1 baseCurrency = apiValue currency
          final apiValue = (rates[lower] as num).toDouble();
          final rateValue = apiValue;

          final existingIndex = updatedRecords.indexWhere(
            (r) =>
                r.base.toUpperCase() ==
                    state.preferences.baseCurrency.toUpperCase() &&
                r.quote.toUpperCase() == currency.toUpperCase(),
          );

          if (existingIndex >= 0 &&
              updatedRecords[existingIndex].provider == null) {
            continue; // Skip overwriting user-provided manual rates
          }

          final newRecord = ExchangeRateRecord(
            base: state.preferences.baseCurrency.toUpperCase(),
            quote: currency.toUpperCase(),
            rate: rateValue,
            asOfDate: DateTime.now(),
            provider: 'fawazahmed0',
          );

          if (existingIndex >= 0) {
            updatedRecords[existingIndex] = newRecord;
          } else {
            updatedRecords.add(newRecord);
          }
          changed = true;
        }
      }

      if (changed) {
        await _ref
            .read(ledgerProvider.notifier)
            .setExchangeRatesDirectly(updatedRecords);
      }
    } catch (e) {
      debugPrint('Failed to refresh exchange rates: $e');
      rethrow;
    }
  }
}
