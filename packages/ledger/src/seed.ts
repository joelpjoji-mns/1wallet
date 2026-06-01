import type { Category, CategoryKind } from '@1wallet/domain/types';
import { createCategory, updateCategory } from './services/index';
import type { LedgerState } from './store/types';

type CategoryTemplate = {
  key: string;
  name: string;
  kind: CategoryKind;
  parentKey?: string;
  icon: string;
  color: string;
  aliases?: string[];
};

export const DEFAULT_CATEGORY_TAXONOMY: CategoryTemplate[] = [
  {
    key: 'expense-food',
    name: 'Food & dining',
    kind: 'expense',
    icon: 'food-fork-drink',
    color: '#E56B4A',
    aliases: ['Food', 'Food & Drinks', 'Food and drinks'],
  },
  {
    key: 'expense-food-groceries',
    parentKey: 'expense-food',
    name: 'Groceries',
    kind: 'expense',
    icon: 'cart-outline',
    color: '#43A047',
    aliases: ['Supermarket', 'BigBasket', 'Dmart', 'DMart', 'Tesco', 'Sainsbury'],
  },
  {
    key: 'expense-food-breakfast',
    parentKey: 'expense-food',
    name: 'Breakfast',
    kind: 'expense',
    icon: 'coffee-outline',
    color: '#A15C38',
    aliases: ['BreakFast'],
  },
  {
    key: 'expense-food-lunch',
    parentKey: 'expense-food',
    name: 'Lunch',
    kind: 'expense',
    icon: 'silverware-fork-knife',
    color: '#F59E0B',
    aliases: ['Office Lunch'],
  },
  {
    key: 'expense-food-dining',
    parentKey: 'expense-food',
    name: 'Dining out',
    kind: 'expense',
    icon: 'food-takeout-box-outline',
    color: '#EF4444',
    aliases: ['Dinner', 'Restaurant', 'Restaurants'],
  },
  {
    key: 'expense-food-delivery',
    parentKey: 'expense-food',
    name: 'Food delivery',
    kind: 'expense',
    icon: 'truck-delivery-outline',
    color: '#FB7185',
    aliases: ['Fast-food', 'Fast food', 'Takeaway', 'Swiggy', 'Zomato'],
  },
  {
    key: 'expense-food-coffee-snacks',
    parentKey: 'expense-food',
    name: 'Coffee & snacks',
    kind: 'expense',
    icon: 'cupcake',
    color: '#B45309',
    aliases: ['Cafe', 'Tea', 'Snacks'],
  },

  {
    key: 'expense-transport',
    name: 'Transport',
    kind: 'expense',
    icon: 'bus',
    color: '#2563EB',
    aliases: ['Transportation', 'Transit'],
  },
  {
    key: 'expense-transport-public',
    parentKey: 'expense-transport',
    name: 'Public transport',
    kind: 'expense',
    icon: 'train-car',
    color: '#0EA5E9',
    aliases: ['Bus', 'Metro', 'Train'],
  },
  {
    key: 'expense-transport-taxi',
    parentKey: 'expense-transport',
    name: 'Taxi & rides',
    kind: 'expense',
    icon: 'taxi',
    color: '#FACC15',
    aliases: ['Taxi and rides', 'Uber', 'Ola', 'Cab', 'Ride share'],
  },
  {
    key: 'expense-transport-parking',
    parentKey: 'expense-transport',
    name: 'Parking & tolls',
    kind: 'expense',
    icon: 'parking',
    color: '#64748B',
    aliases: ['Parking and tolls', 'Parking', 'Tolls'],
  },
  {
    key: 'expense-transport-fuel',
    parentKey: 'expense-transport',
    name: 'Fuel',
    kind: 'expense',
    icon: 'gas-station-outline',
    color: '#F97316',
  },

  {
    key: 'expense-vehicle',
    name: 'Vehicle',
    kind: 'expense',
    icon: 'car-outline',
    color: '#334155',
  },
  {
    key: 'expense-vehicle-maintenance',
    parentKey: 'expense-vehicle',
    name: 'Vehicle maintenance',
    kind: 'expense',
    icon: 'wrench-outline',
    color: '#F59E0B',
    aliases: ['Service', 'Repairs'],
  },
  {
    key: 'expense-vehicle-insurance',
    parentKey: 'expense-vehicle',
    name: 'Vehicle insurance',
    kind: 'expense',
    icon: 'shield-car',
    color: '#14B8A6',
  },
  {
    key: 'expense-vehicle-lease',
    parentKey: 'expense-vehicle',
    name: 'Lease & rentals',
    kind: 'expense',
    icon: 'file-document-outline',
    color: '#94A3B8',
    aliases: ['Leasing', 'Rentals'],
  },
  {
    key: 'expense-vehicle-wash',
    parentKey: 'expense-vehicle',
    name: 'Car wash',
    kind: 'expense',
    icon: 'car-wash',
    color: '#38BDF8',
  },

  {
    key: 'expense-shopping',
    name: 'Shopping',
    kind: 'expense',
    icon: 'shopping-outline',
    color: '#C026D3',
  },
  {
    key: 'expense-shopping-clothes',
    parentKey: 'expense-shopping',
    name: 'Clothes',
    kind: 'expense',
    icon: 'tshirt-crew-outline',
    color: '#DB2777',
    aliases: ['Clothes & Footwear', 'Clothes and Footwear', 'Footwear'],
  },
  {
    key: 'expense-shopping-online',
    parentKey: 'expense-shopping',
    name: 'Online shopping',
    kind: 'expense',
    icon: 'package-variant-closed',
    color: '#8B5CF6',
    aliases: ['Amazon', 'Flipkart'],
  },
  {
    key: 'expense-shopping-electronics',
    parentKey: 'expense-shopping',
    name: 'Electronics',
    kind: 'expense',
    icon: 'laptop',
    color: '#0891B2',
    aliases: ['Electronics, accessories', 'Electronics and accessories'],
  },
  {
    key: 'expense-shopping-jewellery',
    parentKey: 'expense-shopping',
    name: 'Jewellery & accessories',
    kind: 'expense',
    icon: 'diamond-stone',
    color: '#A855F7',
    aliases: [
      'Jewels, accessories',
      'Jewels and accessories',
      'Jewelry & accessories',
      'Jewelry, accessories',
      'Accessories',
    ],
  },
  {
    key: 'expense-shopping-home-goods',
    parentKey: 'expense-shopping',
    name: 'Home goods',
    kind: 'expense',
    icon: 'home-variant-outline',
    color: '#A16207',
    aliases: ['Household shopping'],
  },

  {
    key: 'expense-bills',
    name: 'Bills & utilities',
    kind: 'expense',
    icon: 'receipt',
    color: '#7C3AED',
    aliases: ['Bills', 'Utilities'],
  },
  {
    key: 'expense-bills-electricity',
    parentKey: 'expense-bills',
    name: 'Electricity',
    kind: 'expense',
    icon: 'flash-outline',
    color: '#FBBF24',
    aliases: ['Power bill', 'Energy', 'BESCOM', 'TNEB', 'Electric bill'],
  },
  {
    key: 'expense-bills-internet',
    parentKey: 'expense-bills',
    name: 'Internet & phone',
    kind: 'expense',
    icon: 'wifi',
    color: '#2563EB',
    aliases: [
      'Internet',
      'Internet and phone',
      'Broadband',
      'Phone bill',
      'Mobile bill',
      'Airtel',
      'Jio',
      'Vodafone',
      'Broadband and phone',
      'Phone',
      'Fibre',
      'Fiber',
      'Wi-Fi',
      'Wifi',
    ],
  },
  {
    key: 'expense-bills-mobile',
    parentKey: 'expense-bills',
    name: 'Mobile recharge',
    kind: 'expense',
    icon: 'cellphone-charging',
    color: '#0F766E',
    aliases: ['Recharge', 'Prepaid recharge', 'Mobile top-up', 'Top up'],
  },
  {
    key: 'expense-bills-water',
    parentKey: 'expense-bills',
    name: 'Water',
    kind: 'expense',
    icon: 'water-outline',
    color: '#0891B2',
  },
  {
    key: 'expense-bills-gas',
    parentKey: 'expense-bills',
    name: 'Gas',
    kind: 'expense',
    icon: 'fire',
    color: '#EA580C',
  },
  {
    key: 'expense-bills-subscriptions',
    parentKey: 'expense-bills',
    name: 'Subscriptions',
    kind: 'expense',
    icon: 'calendar-sync-outline',
    color: '#8B5CF6',
    aliases: ['Subscription', 'SaaS', 'Netflix', 'Spotify', 'Prime', 'Amazon Prime'],
  },
  {
    key: 'expense-bills-dth',
    parentKey: 'expense-bills',
    name: 'TV & streaming',
    kind: 'expense',
    icon: 'television-classic',
    color: '#7C3AED',
    aliases: ['DTH', 'DTH and streaming', 'TV recharge', 'Streaming', 'OTT'],
  },
  {
    key: 'expense-bills-insurance',
    parentKey: 'expense-bills',
    name: 'Insurance',
    kind: 'expense',
    icon: 'shield-check-outline',
    color: '#059669',
    aliases: ['Premium', 'Insurance premium', 'Life insurance', 'Health insurance', 'Insurances'],
  },
  {
    key: 'expense-bills-council-tax',
    parentKey: 'expense-bills',
    name: 'Council tax',
    kind: 'expense',
    icon: 'home-city-outline',
    color: '#475569',
    aliases: ['Council bill', 'Local tax'],
  },

  {
    key: 'expense-housing',
    name: 'Housing',
    kind: 'expense',
    icon: 'home-outline',
    color: '#B45309',
    aliases: ['Home'],
  },
  {
    key: 'expense-housing-rent',
    parentKey: 'expense-housing',
    name: 'Rent',
    kind: 'expense',
    icon: 'home-city-outline',
    color: '#92400E',
    aliases: ['House rent', 'Flat rent', 'Landlord', 'Letting'],
  },
  {
    key: 'expense-housing-home-loan',
    parentKey: 'expense-housing',
    name: 'Home loan EMI',
    kind: 'expense',
    icon: 'home-clock-outline',
    color: '#7C2D12',
    aliases: ['Mortgage', 'Home loan'],
  },
  {
    key: 'expense-housing-maintenance',
    parentKey: 'expense-housing',
    name: 'Maintenance',
    kind: 'expense',
    icon: 'tools',
    color: '#78716C',
  },
  {
    key: 'expense-housing-furniture',
    parentKey: 'expense-housing',
    name: 'Furniture',
    kind: 'expense',
    icon: 'sofa-outline',
    color: '#A16207',
  },
  {
    key: 'expense-housing-supplies',
    parentKey: 'expense-housing',
    name: 'Household supplies',
    kind: 'expense',
    icon: 'spray-bottle',
    color: '#CA8A04',
  },

  {
    key: 'expense-health',
    name: 'Health & wellness',
    kind: 'expense',
    icon: 'heart-pulse',
    color: '#DC2626',
    aliases: ['Health', 'Health and beauty', 'Wellness, beauty'],
  },
  {
    key: 'expense-health-doctor',
    parentKey: 'expense-health',
    name: 'Doctor',
    kind: 'expense',
    icon: 'doctor',
    color: '#EF4444',
  },
  {
    key: 'expense-health-medicine',
    parentKey: 'expense-health',
    name: 'Medicine',
    kind: 'expense',
    icon: 'pill',
    color: '#10B981',
    aliases: ['Pharmacy'],
  },
  {
    key: 'expense-health-fitness',
    parentKey: 'expense-health',
    name: 'Fitness',
    kind: 'expense',
    icon: 'dumbbell',
    color: '#F97316',
    aliases: ['Gym', 'Sports'],
  },
  {
    key: 'expense-health-dental',
    parentKey: 'expense-health',
    name: 'Dental',
    kind: 'expense',
    icon: 'tooth-outline',
    color: '#0EA5E9',
  },

  {
    key: 'expense-entertainment',
    name: 'Entertainment',
    kind: 'expense',
    icon: 'movie-open-outline',
    color: '#9333EA',
    aliases: ['Life & Entertainment', 'Life and entertainment', 'Leisure time'],
  },
  {
    key: 'expense-entertainment-movies',
    parentKey: 'expense-entertainment',
    name: 'Movies & shows',
    kind: 'expense',
    icon: 'movie-outline',
    color: '#7E22CE',
    aliases: ['Movies and shows', 'Movies, Theatre', 'Movies, Theater', 'Theatre', 'Theater'],
  },
  {
    key: 'expense-entertainment-games',
    parentKey: 'expense-entertainment',
    name: 'Games',
    kind: 'expense',
    icon: 'controller-classic-outline',
    color: '#4F46E5',
  },
  {
    key: 'expense-entertainment-events',
    parentKey: 'expense-entertainment',
    name: 'Events',
    kind: 'expense',
    icon: 'ticket-outline',
    color: '#DB2777',
    aliases: ['Concerts', 'Shows', 'Life events', 'Culture, sport events'],
  },
  {
    key: 'expense-entertainment-books-music',
    parentKey: 'expense-entertainment',
    name: 'Books & music',
    kind: 'expense',
    icon: 'book-music-outline',
    color: '#6366F1',
  },

  { key: 'expense-travel', name: 'Travel', kind: 'expense', icon: 'airplane', color: '#0284C7' },
  {
    key: 'expense-travel-flights',
    parentKey: 'expense-travel',
    name: 'Flights',
    kind: 'expense',
    icon: 'airplane-takeoff',
    color: '#0EA5E9',
  },
  {
    key: 'expense-travel-hotel',
    parentKey: 'expense-travel',
    name: 'Hotels',
    kind: 'expense',
    icon: 'bed-outline',
    color: '#0369A1',
    aliases: ['Hotel'],
  },
  {
    key: 'expense-travel-local',
    parentKey: 'expense-travel',
    name: 'Local travel',
    kind: 'expense',
    icon: 'map-marker-path',
    color: '#22C55E',
  },
  {
    key: 'expense-travel-long-distance',
    parentKey: 'expense-travel',
    name: 'Long-distance travel',
    kind: 'expense',
    icon: 'map-marker-distance',
    color: '#38BDF8',
    aliases: ['Long distance', 'Long-distance', 'Intercity travel'],
  },
  {
    key: 'expense-travel-documents',
    parentKey: 'expense-travel',
    name: 'Visa & documents',
    kind: 'expense',
    icon: 'passport',
    color: '#0F766E',
  },

  {
    key: 'expense-education',
    name: 'Education',
    kind: 'expense',
    icon: 'school-outline',
    color: '#0F766E',
  },
  {
    key: 'expense-education-courses',
    parentKey: 'expense-education',
    name: 'Courses',
    kind: 'expense',
    icon: 'certificate-outline',
    color: '#059669',
  },
  {
    key: 'expense-education-books',
    parentKey: 'expense-education',
    name: 'Books & supplies',
    kind: 'expense',
    icon: 'book-open-page-variant-outline',
    color: '#047857',
  },
  {
    key: 'expense-education-tuition',
    parentKey: 'expense-education',
    name: 'Tuition',
    kind: 'expense',
    icon: 'notebook-outline',
    color: '#0E7490',
  },

  {
    key: 'expense-personal',
    name: 'Personal & care',
    kind: 'expense',
    icon: 'account-heart-outline',
    color: '#BE185D',
  },
  {
    key: 'expense-personal-care',
    parentKey: 'expense-personal',
    name: 'Personal care',
    kind: 'expense',
    icon: 'content-cut',
    color: '#DB2777',
    aliases: ['Salon', 'Grooming'],
  },
  {
    key: 'expense-personal-family',
    parentKey: 'expense-personal',
    name: 'Family support',
    kind: 'expense',
    icon: 'account-group-outline',
    color: '#E11D48',
    aliases: ['Family', 'Allowance'],
  },
  {
    key: 'expense-personal-childcare',
    parentKey: 'expense-personal',
    name: 'Childcare',
    kind: 'expense',
    icon: 'human-child',
    color: '#F43F5E',
    aliases: ['Kids', 'Children'],
  },
  {
    key: 'expense-personal-pets',
    parentKey: 'expense-personal',
    name: 'Pets',
    kind: 'expense',
    icon: 'paw-outline',
    color: '#A16207',
    aliases: ['Pets, animals', 'Pets and animals'],
  },
  {
    key: 'expense-personal-misc',
    parentKey: 'expense-personal',
    name: 'Miscellaneous',
    kind: 'expense',
    icon: 'dots-horizontal-circle-outline',
    color: '#6B7280',
    aliases: ['Other', 'Others', 'Custom'],
  },
  {
    key: 'expense-personal-uncategorized',
    parentKey: 'expense-personal',
    name: 'Uncategorized imports',
    kind: 'expense',
    icon: 'help-circle-outline',
    color: '#9CA3AF',
    aliases: ['Unknown Expense', 'Unknown expense', 'Uncategorized', 'Missing'],
  },

  {
    key: 'expense-giving',
    name: 'Gifts & giving',
    kind: 'expense',
    icon: 'gift-outline',
    color: '#BE123C',
    aliases: ['Gifts', 'Gift', 'Gifts, joy'],
  },
  {
    key: 'expense-giving-gifts',
    parentKey: 'expense-giving',
    name: 'Gifts',
    kind: 'expense',
    icon: 'gift-open-outline',
    color: '#DB2777',
    aliases: ['Gift', 'Gifts, joy'],
  },
  {
    key: 'expense-giving-donations',
    parentKey: 'expense-giving',
    name: 'Donations',
    kind: 'expense',
    icon: 'hand-heart-outline',
    color: '#16A34A',
    aliases: ['Charity'],
  },

  {
    key: 'expense-work-business',
    name: 'Work & business',
    kind: 'expense',
    icon: 'briefcase-outline',
    color: '#0F766E',
  },
  {
    key: 'expense-work-business-office',
    parentKey: 'expense-work-business',
    name: 'Office supplies',
    kind: 'expense',
    icon: 'briefcase-outline',
    color: '#0D9488',
    aliases: ['Stationery, tools', 'Stationery and tools'],
  },
  {
    key: 'expense-work-business-software',
    parentKey: 'expense-work-business',
    name: 'Software',
    kind: 'expense',
    icon: 'laptop-account',
    color: '#0891B2',
    aliases: ['Software, apps, games', 'Software apps games'],
  },
  {
    key: 'expense-work-business-services',
    parentKey: 'expense-work-business',
    name: 'Professional services',
    kind: 'expense',
    icon: 'account-tie-outline',
    color: '#0F766E',
    aliases: ['Services', 'Advisory', 'Consulting'],
  },
  {
    key: 'expense-work-business-travel',
    parentKey: 'expense-work-business',
    name: 'Business travel',
    kind: 'expense',
    icon: 'briefcase-clock-outline',
    color: '#0284C7',
    aliases: ['Business trips', 'Business trip'],
  },

  {
    key: 'expense-finance',
    name: 'Finance & loans',
    kind: 'expense',
    icon: 'bank-outline',
    color: '#475569',
    aliases: ['Finance', 'Financial expenses', 'Loans'],
  },
  {
    key: 'expense-finance-fees',
    parentKey: 'expense-finance',
    name: 'Charges & fees',
    kind: 'expense',
    icon: 'receipt',
    color: '#64748B',
    aliases: ['Charges, Fees', 'Charges and fees', 'Fees'],
  },
  {
    key: 'expense-finance-card-bill',
    parentKey: 'expense-finance',
    name: 'Credit card bill',
    kind: 'expense',
    icon: 'credit-card-check-outline',
    color: '#991B1B',
    aliases: ['Card payment', 'Credit card payment', 'Statement payment', 'Minimum due'],
  },
  {
    key: 'expense-finance-emi',
    parentKey: 'expense-finance',
    name: 'EMI',
    kind: 'expense',
    icon: 'calendar-clock-outline',
    color: '#B91C1C',
    aliases: [
      'Loan EMI',
      'Installment',
      'Instalment',
      'Educational Loan',
      'KudumbaSree Loan',
      'Kudumbashree Loan',
    ],
  },
  {
    key: 'expense-finance-fines',
    parentKey: 'expense-finance',
    name: 'Fines & penalties',
    kind: 'expense',
    icon: 'alert-circle-outline',
    color: '#B45309',
    aliases: ['Fines', 'Penalty', 'Penalties'],
  },
  {
    key: 'expense-finance-debt',
    parentKey: 'expense-finance',
    name: 'Debt payments',
    kind: 'expense',
    icon: 'credit-card-clock-outline',
    color: '#7F1D1D',
  },
  {
    key: 'expense-finance-interest',
    parentKey: 'expense-finance',
    name: 'Interest paid',
    kind: 'expense',
    icon: 'bank-minus',
    color: '#BE123C',
    aliases: ['Loan interest', 'Card interest', 'Finance charge'],
  },
  {
    key: 'expense-finance-tax',
    parentKey: 'expense-finance',
    name: 'Tax',
    kind: 'expense',
    icon: 'file-document-outline',
    color: '#334155',
    aliases: ['Income tax', 'Self assessment', 'HMRC', 'TDS'],
  },
  {
    key: 'expense-finance-investments',
    parentKey: 'expense-finance',
    name: 'Investments',
    kind: 'expense',
    icon: 'chart-line',
    color: '#059669',
    aliases: ['Investment buy', 'Stocks', 'Mutual funds'],
  },
  {
    key: 'expense-finance-investment-fees',
    parentKey: 'expense-finance',
    name: 'Investment fees',
    kind: 'expense',
    icon: 'chart-line-variant',
    color: '#0F766E',
    aliases: ['Brokerage', 'Demat charges', 'Platform fee'],
  },
  {
    key: 'expense-finance-shared-expenses',
    parentKey: 'expense-finance',
    name: 'Shared expenses',
    kind: 'expense',
    icon: 'account-multiple-outline',
    color: '#7C3AED',
    aliases: ['Splitwise', 'Split wise', 'Shared bills'],
  },
  {
    key: 'expense-finance-lending',
    parentKey: 'expense-finance',
    name: 'Lending',
    kind: 'expense',
    icon: 'hand-coin-outline',
    color: '#A16207',
  },

  { key: 'income-work', name: 'Work', kind: 'income', icon: 'briefcase-outline', color: '#16A34A' },
  {
    key: 'income-work-salary',
    parentKey: 'income-work',
    name: 'Salary',
    kind: 'income',
    icon: 'cash-multiple',
    color: '#15803D',
    aliases: ['Payroll', 'Wages', 'Payslip'],
  },
  {
    key: 'income-work-bonus',
    parentKey: 'income-work',
    name: 'Bonus',
    kind: 'income',
    icon: 'star-circle-outline',
    color: '#65A30D',
  },
  {
    key: 'income-work-reimbursements',
    parentKey: 'income-work',
    name: 'Reimbursements',
    kind: 'income',
    icon: 'receipt-text-check-outline',
    color: '#22C55E',
    aliases: ['Reimbursement', 'Expense claim'],
  },
  {
    key: 'income-business',
    name: 'Business income',
    kind: 'income',
    icon: 'store-outline',
    color: '#0891B2',
  },
  {
    key: 'income-business-freelance',
    parentKey: 'income-business',
    name: 'Freelance',
    kind: 'income',
    icon: 'account-cash-outline',
    color: '#0E7490',
    aliases: ['Advisory', 'Consulting'],
  },
  {
    key: 'income-business-sales',
    parentKey: 'income-business',
    name: 'Sales',
    kind: 'income',
    icon: 'storefront-outline',
    color: '#0284C7',
  },
  {
    key: 'income-investments',
    name: 'Investments income',
    kind: 'income',
    icon: 'chart-line',
    color: '#0D9488',
    aliases: ['Passive income'],
  },
  {
    key: 'income-investments-interest',
    parentKey: 'income-investments',
    name: 'Interest',
    kind: 'income',
    icon: 'bank-plus',
    color: '#0F766E',
  },
  {
    key: 'income-investments-dividend',
    parentKey: 'income-investments',
    name: 'Dividend',
    kind: 'income',
    icon: 'chart-areaspline',
    color: '#047857',
    aliases: ['Dividends', 'Mutual fund payout'],
  },
  {
    key: 'income-investments-capital-gains',
    parentKey: 'income-investments',
    name: 'Capital gains',
    kind: 'income',
    icon: 'trending-up',
    color: '#059669',
  },
  {
    key: 'income-money-back',
    name: 'Money back',
    kind: 'income',
    icon: 'cash-refund',
    color: '#4D7C0F',
  },
  {
    key: 'income-money-back-refund',
    parentKey: 'income-money-back',
    name: 'Refund',
    kind: 'income',
    icon: 'undo-variant',
    color: '#65A30D',
  },
  {
    key: 'income-money-back-cashback',
    parentKey: 'income-money-back',
    name: 'Cashback',
    kind: 'income',
    icon: 'sale',
    color: '#84CC16',
  },
  {
    key: 'income-money-back-rewards',
    parentKey: 'income-money-back',
    name: 'Rewards',
    kind: 'income',
    icon: 'ticket-percent-outline',
    color: '#A3E635',
  },
  {
    key: 'income-gifts',
    name: 'Gifts & support',
    kind: 'income',
    icon: 'gift-outline',
    color: '#DB2777',
    aliases: ['Gifts', 'Gift', 'Gifts, joy'],
  },
  {
    key: 'income-gifts-gifts',
    parentKey: 'income-gifts',
    name: 'Gifts',
    kind: 'income',
    icon: 'gift-open-outline',
    color: '#BE185D',
    aliases: ['Gift', 'Gifts, joy'],
  },
  {
    key: 'income-gifts-family-support',
    parentKey: 'income-gifts',
    name: 'Family support',
    kind: 'income',
    icon: 'account-group-outline',
    color: '#E11D48',
    aliases: ['Allowance'],
  },
  {
    key: 'income-adjustments',
    name: 'Income adjustments',
    kind: 'income',
    icon: 'tune-variant',
    color: '#059669',
  },
  {
    key: 'income-adjustments-misc',
    parentKey: 'income-adjustments',
    name: 'Miscellaneous income',
    kind: 'income',
    icon: 'dots-horizontal-circle-outline',
    color: '#059669',
    aliases: ['Other income', 'Other', 'Others'],
  },
  {
    key: 'income-adjustments-uncategorized',
    parentKey: 'income-adjustments',
    name: 'Uncategorized income',
    kind: 'income',
    icon: 'help-circle-outline',
    color: '#22C55E',
    aliases: ['Unknown Income', 'Unknown income', 'Missing'],
  },
];

export function seedDefaultCategories(state: LedgerState): boolean {
  const categoriesByKey = new Map<string, Category>();
  let changed = false;

  for (const [sortOrder, template] of DEFAULT_CATEGORY_TAXONOMY.entries()) {
    const parent = template.parentKey ? categoriesByKey.get(template.parentKey) : undefined;
    if (template.parentKey && !parent) continue;
    const parentId = parent?.id;
    let category = findMatchingCategory(state, template, parentId);

    if (!category && parentId) {
      category = findAdoptableCategory(state, template, parentId);
      if (category) {
        updateCategory(state, category.id, {
          parentId,
          icon: category.icon ?? template.icon,
          color: category.color ?? template.color,
        });
        changed = true;
      }
    }

    if (!category) {
      category = createCategory(state, {
        name: template.name,
        kind: template.kind,
        parentId,
        icon: template.icon,
        color: template.color,
      });
      category.sortOrder = sortOrder;
      changed = true;
    } else if (backfillCategoryDefaults(state, category, template, sortOrder)) {
      changed = true;
    }

    categoriesByKey.set(template.key, category);
  }

  return changed;
}

function findMatchingCategory(
  state: LedgerState,
  template: CategoryTemplate,
  parentId: string | undefined,
): Category | undefined {
  const names = normalizedTemplateNames(template);
  return state.categories.find(
    (category) =>
      category.kind === template.kind &&
      (category.parentId ?? undefined) === parentId &&
      names.has(normalizeName(category.name)),
  );
}

function findAdoptableCategory(
  state: LedgerState,
  template: CategoryTemplate,
  parentId: string,
): Category | undefined {
  const names = normalizedTemplateNames(template);
  const parent = state.categories.find((category) => category.id === parentId);
  if (!parent || parent.kind !== template.kind) return undefined;

  return state.categories.find(
    (category) =>
      category.id !== parentId &&
      category.kind === template.kind &&
      !category.parentId &&
      !state.categories.some((child) => child.parentId === category.id) &&
      names.has(normalizeName(category.name)),
  );
}

function backfillCategoryDefaults(
  state: LedgerState,
  category: Category,
  template: CategoryTemplate,
  sortOrder: number,
): boolean {
  const patch: Parameters<typeof updateCategory>[2] = {};
  if (!category.icon) patch.icon = template.icon;
  if (!category.color) patch.color = template.color;
  if (category.sortOrder !== sortOrder) patch.sortOrder = sortOrder;
  if (shouldUseTemplateName(state, category, template)) patch.name = template.name;
  if (Object.keys(patch).length === 0) return false;
  updateCategory(state, category.id, patch);
  return true;
}

function shouldUseTemplateName(
  state: LedgerState,
  category: Category,
  template: CategoryTemplate,
): boolean {
  const currentName = normalizeName(category.name);
  if (currentName === normalizeName(template.name)) return false;
  const isKnownAlias = (template.aliases ?? []).some(
    (alias) => normalizeName(alias) === currentName,
  );
  if (!isKnownAlias) return false;

  return !state.categories.some(
    (sibling) =>
      sibling.id !== category.id &&
      sibling.kind === template.kind &&
      (sibling.parentId ?? undefined) === (category.parentId ?? undefined) &&
      normalizeName(sibling.name) === normalizeName(template.name),
  );
}

function normalizedTemplateNames(template: CategoryTemplate): Set<string> {
  return new Set([template.name, ...(template.aliases ?? [])].map(normalizeName));
}

function normalizeName(name: string): string {
  return name.trim().toLowerCase().replace(/\s+/g, ' ');
}
