Feature: Cloud Sync Write Guard and Local Isolation
  As an offline-first user
  I want guaranteed isolation between device-only data and cloud infrastructure
  So that offline data is never dispatched to Firestore until explicit upgrade

  Scenario: Offline transactions mark local unsynced changes but strictly block cloud synchronization
    Given an offline wallet with 5000 minor units
    When I add a 1200 expense for "Fuel"
    Then the local ledger has unsynced changes recorded
    And the cloud sync phase is disabled
    And the cloud sync write guard disallows remote writes with reason "offline mode"
    And zero network requests reach Cloud Firestore

  Scenario: Deleting an account in offline mode stays strictly local
    Given an offline account "Temporary Cash" with 1000 minor units in "USD"
    When I retire or delete the account "Temporary Cash"
    Then the account "Temporary Cash" is not active in the local ledger
    And zero network requests reach Cloud Firestore
