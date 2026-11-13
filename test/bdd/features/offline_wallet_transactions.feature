Feature: Offline Wallet Transaction Management and Balance Integrity
  As a privacy-focused user
  I want to track expenses and transfers in an offline wallet
  So that my balance is updated accurately in integer minor units without any data leaving my device

  Scenario: Add expense in offline mode updates balance and triggers no cloud writes
    Given an offline wallet with 1000 minor units
    When I add a 250 expense for "Groceries"
    Then balance shows 750 minor units
    And no cloud write occurs
    And the local ledger contains 1 transactions

  Scenario: Atomic transfer between accounts preserves minor unit balance
    Given an offline account "Checking" with 5000 minor units in "USD"
    And an offline account "Savings" with 2000 minor units in "USD"
    When I transfer 1500 minor units from "Checking" to "Savings"
    Then balance shows 3500 minor units for account "Checking"
    And balance shows 3500 minor units for account "Savings"
    And no cloud write occurs
    And the local ledger contains 1 transactions

  Scenario: Sequential transactions accumulate deterministically without floating-point error
    Given an offline wallet with 10000 minor units
    When I add a 1999 expense for "Dinner"
    And I add a 3450 expense for "Electronics"
    And I add a 551 expense for "Coffee"
    Then balance shows 4000 minor units
    And no cloud write occurs
    And the local ledger contains 3 transactions
