# Wireframes

<!-- markdownlint-disable MD040 -->

Low-fidelity ASCII wireframes for the core screens. These are layout intent, not pixel design. Use them to guide implementation order, navigation, and information density.

Conventions:

- `[ ]` = button or chip
- `(.)` = selected
- `( )` = unselected
- `===` = section separator
- `...` = list continues
- `*` = highlighted

---

## 1. Onboarding

### 1.1 Welcome

```
+----------------------------------------+
|                                        |
|              1wallet                   |
|     Personal finance, on your terms    |
|                                        |
|   [ Continue with Google ]             |
|   [ Continue with Apple  ]             |
|   [ Continue with Email  ]             |
|                                        |
|   Already have a backup? Restore       |
+----------------------------------------+
```

### 1.2 Country and currency

```
+----------------------------------------+
| < Setup                          1/4   |
|========================================|
| Country         [ India             v] |
| Base currency   [ INR  Rupee        v] |
| Start of month  [ 1                 v] |
| Start of week   [ Monday            v] |
|                                        |
|                                        |
| [ Next ]                               |
+----------------------------------------+
```

### 1.3 Add accounts

```
+----------------------------------------+
| < Setup                          2/4   |
|========================================|
| Add your accounts                      |
|                                        |
| [+ Cash]   [+ Bank]   [+ Card]         |
| [+ Wallet] [+ Loan]   [+ Custom]       |
|                                        |
| Added:                                 |
|  - HDFC Savings        INR  45,200     |
|  - HDFC Credit Card    INR  -8,400     |
|  - Cash                INR   2,300     |
|                                        |
| [ Next ]                               |
+----------------------------------------+
```

### 1.4 Pick category pack

```
+----------------------------------------+
| < Setup                          3/4   |
|========================================|
| Choose a category pack                 |
|                                        |
| (.) India everyday                     |
| ( ) Minimal                            |
| ( ) Freelancer                         |
| ( ) Student                            |
| ( ) Family                             |
| ( ) Start from scratch                 |
|                                        |
| [ Next ]                               |
+----------------------------------------+
```

### 1.5 Optional setup

```
+----------------------------------------+
| < Setup                          4/4   |
|========================================|
| Optional                                |
|                                        |
| [ Add first budget ]                    |
| [ Add a savings goal ]                  |
| [ Add a credit card cycle ]             |
| [ Add a loan / EMI ]                    |
| [ Enable Android notification capture ] |
|                                        |
| [ Finish ]                              |
+----------------------------------------+
```

---

## 2. Home dashboard (mobile)

```
+----------------------------------------+
| Hi Joel              [search] [bell]   |
|========================================|
|  NET WORTH                             |
|  INR 1,42,300       ^ +3.2% this month |
|----------------------------------------|
|  CASHFLOW   Income 62,000              |
|             Expense 38,400             |
|             Net    +23,600             |
|----------------------------------------|
|  BUDGET BURN                           |
|  Food          [#########  ]  82%      |
|  Transport     [####       ]  41%      |
|  Shopping      [############] 110% *   |
|----------------------------------------|
|  UPCOMING DUES                         |
|  HDFC card  due in 3d   INR 8,400      |
|  Home EMI   due in 7d   INR 24,000     |
|  Netflix    due in 9d   INR    649     |
|----------------------------------------|
|  GOALS                                 |
|  Emergency   [######    ]  62%         |
|  Laptop      [###       ]  28%         |
|----------------------------------------|
|  REVIEW QUEUE                          |
|  3 captures waiting     [ Review > ]   |
+----------------------------------------+
| [Home] [Txns] [ + ] [Plan] [Accounts]  |
+----------------------------------------+
```

---

## 3. Quick add (transaction sheet)

```
+----------------------------------------+
|  Add transaction                    X  |
|========================================|
| (.) Expense  ( ) Income  ( ) Transfer  |
|----------------------------------------|
|                                        |
|        GBP  50.00                      |
|        INR  ₹5,250.00                  |
|        [ 7 8 9 ]                       |
|        [ 4 5 6 ]                       |
|        [ 1 2 3 ]                       |
|        [ . 0 < ]                       |
|                                        |
| Account     [ HDFC Card           v ]  |
| Category    [ Food > Restaurants  v ]  |
| Date        [ Today               v ]  |
|                                        |
| [ More options v ]                     |
|                                        |
| [   Save   ]   [ Save + add another ]  |
+----------------------------------------+
```

### Quick add expanded

```
| Merchant    [ Domino's                ] |
| Payment     [ UPI                   v ] |
| Tags        [ dining out ] [ +tag ]     |
| Notes       [                          ]|
| Attach      [ camera ] [ file ]         |
| Location    [ Use current location ]    |
| Currency    [ INR                  v ]  |
| FX rate     auto                        |
| Reimburse?  [ ] tax-deductible?  [ ]    |
| Project     [ none                 v ]  |
| Person      [ none                 v ]  |
| Recurring   [ Off                  v ]  |
| Exclude from reports  [ ]               |
```

---

## 4. Transactions list

```
+----------------------------------------+
| Transactions       [filter] [search]   |
|========================================|
| [ All ] [ Unreviewed ] [ This month ]  |
|                                        |
| Sat 24 May                             |
|  Domino's       Food         -1,250    |
|  Uber           Transport      -340    |
|  Salary         Income      +62,000    |
|                                        |
| Fri 23 May                             |
|  Netflix        Subscription   -649    |
|  Card payment   Transfer    -8,400     |
|                                        |
| Thu 22 May                             |
|  Amazon         Shopping    -2,150 *   |
|   (auto from notification, review)     |
|  ...                                   |
+----------------------------------------+
| [Home] [Txns] [ + ] [Plan] [Accounts]  |
+----------------------------------------+
```

### Transaction detail

```
+----------------------------------------+
| < Transaction                  [edit]  |
|========================================|
|  - INR 1,250.00                        |
|  Food > Restaurants                    |
|  HDFC Credit Card                      |
|  Domino's     UPI                      |
|  Sat 24 May 2026, 8:42 PM              |
|                                        |
|  Tags: dining out, weekend             |
|  Notes: ordered with Sam               |
|  Location: BTM Layout, Bangalore       |
|  Source: notification (95%)            |
|                                        |
|  [ Receipt.jpg ]                       |
|                                        |
| Actions                                |
|  [ Split ]   [ Duplicate ]             |
|  [ Refund ]  [ Exclude from reports ]  |
|  [ Convert to transfer ]               |
|  [ Delete ]                            |
+----------------------------------------+
```

---

## 5. Accounts

### Account list

```
+----------------------------------------+
| Accounts                       [ + ]   |
|========================================|
| Net worth        INR 1,42,300          |
|                                        |
| BANK                                   |
|  HDFC Savings        INR  45,200       |
|  ICICI Savings       INR  18,900       |
|                                        |
| CARDS                                  |
|  HDFC Credit         INR  -8,400       |
|   due in 3d      [ Pay now ]           |
|                                        |
| CASH                                   |
|  Cash                INR   2,300       |
|                                        |
| LOANS                                  |
|  Home loan        INR -18,40,000       |
|                                        |
| EXCLUDED                               |
|  Office reimburse    INR   4,100       |
+----------------------------------------+
```

### Account detail

```
+----------------------------------------+
| < HDFC Savings              [edit]     |
|========================================|
| Balance  INR 45,200    currency INR    |
| Include in totals     [x]              |
| Include in reports    [x]              |
| Include in net worth  [x]              |
|                                        |
| [ Reconcile ] [ Statement ] [ Export ] |
|                                        |
| Balance trend (6 months)               |
|  ___/\___/\____                        |
|                                        |
| Transactions (this month)              |
|  ...                                   |
+----------------------------------------+
```

---

## 6. Planner

```
+----------------------------------------+
| Planner                                |
|========================================|
| [ Budgets ] [ Goals ] [ Cards ]        |
| [ Loans ]   [ Bills ] [ Subs ]         |
|----------------------------------------|
| BUDGETS - May 2026                     |
|  Food         82%   1,640 left         |
|  Transport    41%   2,360 left         |
|  Shopping    110%   -450 over *        |
|  [ + Add budget ]                      |
|----------------------------------------|
| GOALS                                  |
|  Emergency  62%  needs 4,200 / mo      |
|  Laptop     28%  needs 6,800 / mo      |
|  [ + Add goal ]                        |
|----------------------------------------|
| CARDS                                  |
|  HDFC due 27 May  INR 8,400            |
|  Axis due 04 Jun  INR 2,150            |
|----------------------------------------|
| LOANS                                  |
|  Home EMI 24,000 / mo                  |
|  Closes Mar 2034   [ Simulate prepay ] |
+----------------------------------------+
```

### Budget detail

```
+----------------------------------------+
| < Budget: Food            May 2026     |
|========================================|
| Limit       INR  9,000                 |
| Spent       INR  7,360                 |
| Remaining   INR  1,640                 |
| Daily safe to spend  INR  234          |
|                                        |
| [###############     ]  82%            |
|                                        |
| Pace: on track to spend 8,900          |
|                                        |
| Subcategory split                      |
|  Restaurants  3,400                    |
|  Groceries    2,800                    |
|  Snacks       1,160                    |
|                                        |
| Rollover unused [x]    Pause budget [ ]|
+----------------------------------------+
```

### Goal detail

```
+----------------------------------------+
| < Goal: Laptop                         |
|========================================|
| Target   INR 80,000  by  Dec 2026      |
| Saved    INR 22,400 (28%)              |
| Needed   INR 6,800 / month             |
| Priority [ High                v ]     |
|                                        |
| Funding accounts                       |
|  HDFC Savings  [x]                     |
|  ICICI Savings [ ]                     |
|                                        |
| Linked category   [ none           v ] |
|                                        |
| Contributions                          |
|  May    +5,000                         |
|  Apr    +5,400                         |
|  Mar    +6,000                         |
|                                        |
| [ Add contribution ] [ Pause ] [ Done ]|
+----------------------------------------+
```

### Loan detail

```
+----------------------------------------+
| < Home loan                            |
|========================================|
| Principal     INR 25,00,000            |
| Outstanding   INR 18,40,000            |
| Rate          8.6%                     |
| EMI           INR 24,000               |
| Tenure left   94 months                |
| Closes        Mar 2034                 |
|                                        |
| Schedule (next 6 EMIs)                 |
|  Jun 26  Principal 5,200  Interest 18,800
|  Jul 26  ...                           |
|                                        |
| Simulate prepayment                    |
|  One-time   [ 1,00,000 ]               |
|  Extra/mo   [ 5,000     ]              |
|  New closure: Aug 2031  (save 3.4 L)   |
+----------------------------------------+
```

---

## 7. Review queue

```
+----------------------------------------+
| Review queue (3)             [ Rules ] |
|========================================|
| Amazon                INR 2,150        |
|  Suggested: Shopping > Online          |
|  Account:   HDFC Credit                |
|  Source:    Notification (78%)         |
|  [ Approve ] [ Edit ] [ Reject ]       |
|----------------------------------------|
| Swiggy                INR   420        |
|  Suggested: Food > Delivery            |
|  Account:   HDFC Credit                |
|  Source:    SMS (62%)                  |
|  [ Approve ] [ Edit ] [ Reject ]       |
|----------------------------------------|
| Unknown                INR  9,999      |
|  Suggested: Uncategorized              |
|  Account:   ?                          |
|  Source:    SMS (31%)                  |
|  [ Edit ] [ Reject ] [ Ignore sender ] |
+----------------------------------------+
```

---

## 8. Reports

```
+----------------------------------------+
| Reports                                |
|========================================|
| Period [ May 2026 v ] Accounts [ All v]|
|                                        |
| Income      62,000                     |
| Expense     38,400                     |
| Net        +23,600                     |
|                                        |
| Donut: category breakdown              |
|  Food 24%  Transport 11%  ...          |
|                                        |
| Line: net worth trend                  |
|                                        |
| Stacked bar: category trend (6 mo)     |
|                                        |
| Sankey: where money flows              |
|                                        |
| [ Export CSV ] [ PDF ] [ Custom report]|
+----------------------------------------+
```

---

## 9. Search and filters

```
+----------------------------------------+
| Search                          X      |
|========================================|
| [ amount: >1000 category:Food         ]|
|                                        |
| Filters                                |
|  Date     [ Last 30 days   v ]         |
|  Account  [ All            v ]         |
|  Category [ Food + 2 more  v ]         |
|  Tags     [ +              ]           |
|  Source   [ All            v ]         |
|  Status   [ All            v ]         |
|                                        |
| [ Save as smart list ]                 |
|                                        |
| Results: 18 txns, total INR 8,420      |
|  ...                                   |
+----------------------------------------+
```

---

## 10. Settings

```
+----------------------------------------+
| Settings                               |
|========================================|
| PROFILE                                |
|  Name, email, sign-in methods          |
|                                        |
| PREFERENCES                            |
|  Base currency, date format,           |
|  start of week, start of month         |
|                                        |
| APPEARANCE                             |
|  Theme, accent, density                |
|                                        |
| AUTOMATION                             |
|  Notification capture                  |
|  SMS capture (Android only)            |
|  Rules                                 |
|  Trusted senders                       |
|                                        |
| BACKUP & DATA                          |
|  Cloud sync, export, import,           |
|  delete account                        |
|                                        |
| SECURITY                               |
|  App lock, biometric, 2FA, devices     |
|                                        |
| NOTIFICATIONS                          |
|  Native alerts permission/status       |
|  Bill due, budget, large txn, recap    |
|                                        |
| ABOUT                                  |
+----------------------------------------+
```

---

## 11. Home-screen widgets (OS-level)

### Small (2x2)

```
+-------------------+
| Today             |
| INR  1,840 spent  |
|                   |
| [ + Add ]         |
+-------------------+
```

### Medium (4x2)

```
+--------------------------------+
| May 2026                       |
| Spent  38,400 / Budget 45,000  |
| [############     ] 85%        |
|                                |
| Next: HDFC Card  3d  8,400     |
+--------------------------------+
```

### Large (4x4)

```
+--------------------------------+
| Net worth   1,42,300  ^ +3.2%  |
| Cashflow    +23,600 this month |
|                                |
| Top categories                 |
|  Food         9,200            |
|  Transport    4,400            |
|  Shopping    11,300            |
|                                |
| Upcoming                       |
|  HDFC card   3d   8,400        |
|  Home EMI    7d  24,000        |
|                                |
| [ + Add transaction ]          |
+--------------------------------+
```

---

## 12. Web app layout

```
+--------------------------------------------------+
| 1wallet   [ Search.................. ]   user  v |
|--------------------------------------------------|
| [ Home ]                                         |
| [ Txns ]    | DASHBOARD                          |
| [ Plan ]    |  +------+ +------+ +------+        |
| [ Acct ]    |  | NW   | | CF   | | Goals|        |
| [ Repo ]    |  +------+ +------+ +------+        |
| [ Imp  ]    |                                    |
| [ Rules]    |  +-------------------------+       |
| [ Set  ]    |  | Budgets                 |       |
|             |  +-------------------------+       |
|             |  | Upcoming dues           |       |
|             |  +-------------------------+       |
|             |  | Reports / charts        |       |
+--------------------------------------------------+
```

Use the web app for: bulk edits, import center, rules editor, deep reports, settings, multi-month planning, reconciliation.

---

## Screen build order

1. Onboarding (sign in, currency, accounts, categories)
2. Home dashboard
3. Quick add sheet
4. Transactions list and detail
5. Accounts list and detail
6. Planner (budgets, goals first)
7. Cards, loans, bills inside planner
8. Review queue
9. Reports
10. Settings
11. OS-level home-screen widgets
12. Web app dashboard and import center
