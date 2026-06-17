import 'package:flutter/material.dart';
import '../data/ledger_models.dart';
import '../ledger/ledger_selectors.dart';
import '../features/common/full_screen_picker.dart';

const commonCurrencies = [
  'USD', 'EUR', 'GBP', 'INR', 'JPY', 'CAD', 'AUD', 'SGD', 'CHF', 'CNY', 'NZD', 
  'ZAR', 'HKD', 'AED', 'SAR', 'MYR', 'THB', 'IDR', 'PHP', 'VND', 'KRW', 'BRL', 
  'RUB', 'TRY', 'MXN', 'PLN', 'SEK', 'NOK', 'DKK', 'ILS', 'EGP', 'NGN', 'KES', 
  'PKR', 'BDT', 'LKR', 'KWD', 'BHD', 'OMR', 'JOD', 'QAR', 'HUF', 'CZK', 'RON',
  'BGN', 'HRK', 'ISK', 'CLP', 'COP', 'PEN', 'ARS', 'UAH', 'KZT', 'GEL', 'AMD'
];

Future<String?> showCurrencyPicker({
  required BuildContext context,
  required LedgerState state,
  String? selectedValue,
}) async {
  final currencies = {
    state.preferences.baseCurrency,
    ...state.preferences.enabledCurrencies,
  }.toList()..sort();

  return showFullScreenPicker<String>(
    context: context,
    title: 'Choose currency',
    searchHint: 'Search currency code',
    selectedValue: selectedValue,
    options: [
      for (final currency in currencies)
        PickerOption(
          value: currency,
          title: currency,
          icon: Icons.currency_exchange_outlined,
        ),
    ],
  );
}
