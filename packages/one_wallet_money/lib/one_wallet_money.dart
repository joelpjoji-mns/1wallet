import 'package:meta/meta.dart';

@immutable
class Money implements Comparable<Money> {
  const Money({required this.amountMinor, required this.currency});

  /// Factory creating Money from integer major units (e.g. 100 USD -> 10000 minor units).
  factory Money.fromMajor(
    int majorUnits, {
    required String currency,
    int decimals = 2,
  }) {
    var multiplier = 1;
    for (var i = 0; i < decimals; i++) {
      multiplier *= 10;
    }
    return Money(amountMinor: majorUnits * multiplier, currency: currency);
  }

  /// Zero money in given currency.
  factory Money.zero(String currency) =>
      Money(amountMinor: 0, currency: currency);

  final int amountMinor;
  final String currency;

  bool get isZero => amountMinor == 0;
  bool get isPositive => amountMinor > 0;
  bool get isNegative => amountMinor < 0;

  Money add(Money other) {
    _assertSameCurrency(other);
    return Money(
      amountMinor: amountMinor + other.amountMinor,
      currency: currency,
    );
  }

  Money subtract(Money other) {
    _assertSameCurrency(other);
    return Money(
      amountMinor: amountMinor - other.amountMinor,
      currency: currency,
    );
  }

  Money negate() => Money(amountMinor: -amountMinor, currency: currency);

  Money copyWith({int? amountMinor, String? currency}) {
    return Money(
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
    );
  }

  void _assertSameCurrency(Money other) {
    if (currency.toUpperCase() != other.currency.toUpperCase()) {
      throw ArgumentError(
        'Currency mismatch: cannot operate on $currency and ${other.currency}',
      );
    }
  }

  /// Formats the minor units into a standard decimal string without using floating point arithmetic.
  String toDecimalString({int decimals = 2}) {
    final sign = amountMinor < 0 ? '-' : '';
    final absMinor = amountMinor.abs();

    var factor = 1;
    for (var i = 0; i < decimals; i++) {
      factor *= 10;
    }

    final major = absMinor ~/ factor;
    final minorPart = absMinor % factor;
    final minorStr = minorPart.toString().padLeft(decimals, '0');

    return '$sign$major.$minorStr';
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return amountMinor.compareTo(other.amountMinor);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          runtimeType == other.runtimeType &&
          amountMinor == other.amountMinor &&
          currency.toUpperCase() == other.currency.toUpperCase();

  @override
  int get hashCode => amountMinor.hashCode ^ currency.toUpperCase().hashCode;

  @override
  String toString() => '$currency ${toDecimalString()}';
}
