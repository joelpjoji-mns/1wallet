export const screens = [
  ['Getting started', 'Launch', '/launch', 'Session and startup status'],
  ['Getting started', 'Sign in', '/login', 'Offline entry is available; Google sign-in is disabled in the demo.'],
  ['Getting started', 'Permission setup', '/permissions-setup', 'Optional device permissions'],
  ['Getting started', 'Onboarding', '/onboarding', 'First account setup; choose Empty wallet to inspect a new user.'],
  ['Getting started', 'Account deletion', '/account-deletion', 'Account deletion status; no real account is connected.'],
  ['Everyday', 'Dashboard', '/', 'Balances, summaries and recent activity'],
  ['Everyday', 'History', '/?tab=1', 'Search, filter and inspect transactions'],
  ['Everyday', 'Calendar', '/?tab=2', 'Day-by-day activity and planned balance forecasts'],
  ['Everyday', 'Accounts tab', '/?tab=3', 'Main navigation accounts screen'],
  ['Everyday', 'All accounts', '/accounts', 'Manage accounts and account groups'],
  ['Records', 'Add expense', '/add?type=expense', 'Enter amount, account, category and details; save updates the demo wallet.'],
  ['Records', 'Add income', '/add?type=income', 'Record money received'],
  ['Records', 'Transfer', '/add?type=transfer&accountId=demo-bank&counterAccountId=demo-cash', 'Move money between accounts'],
  ['Records', 'USD to EUR transfer', '/add?type=transfer&accountId=demo-usd&counterAccountId=demo-eur', 'Cross-currency transfer with illustrative sample exchange rates'],
  ['Records', 'Planned record tab', '/add?tab=1', 'Plan a future transaction'],
  ['Records', 'Edit transaction', '/add?transactionId=demo-salary', 'Edit the sample salary record'],
  ['Records', 'Transaction detail', '/transaction/demo-salary', 'Inspect, edit or delete a record'],
  ['Accounts & debt', 'New account', '/account/new', 'Create an account with an opening balance'],
  ['Accounts & debt', 'Edit account', '/account/demo-bank', 'Account settings and presentation'],
  ['Accounts & debt', 'Secure account details', '/account/demo-bank/secure', 'Credential details; use fictitious values only'],
  ['Accounts & debt', 'Cards', '/cards', 'Credit cards and payments'],
  ['Accounts & debt', 'Loans', '/loans', 'Loans and repayments'],
  ['Accounts & debt', 'New loan', '/loans/new', 'Loan terms and repayment schedule'],
  ['Accounts & debt', 'Past loans', '/loans/past', 'Past loans and closed debt'],
  ['Accounts & debt', 'Loan forecast', '/loans/forecast', 'Future repayment overview'],
  ['Accounts & debt', 'Loan details', '/loans/demo-loan', 'Inspect the sample home loan'],
  ['Accounts & debt', 'Edit loan', '/loans/demo-loan/edit', 'Change the sample loan terms'],
  ['Accounts & debt', 'Car loan details', '/loans/demo-car-loan', 'Active car loan with eighteen past repayments'],
  ['Accounts & debt', 'Education loan USD', '/loans/demo-education-loan', 'USD loan with twelve past repayments'],
  ['Accounts & debt', 'Paid-off loan details', '/loans/demo-paid-loan', 'Completed laptop loan with twelve payments and zero remaining balance'],
  ['Accounts & debt', 'Business overdraft', '/loans/demo-overdraft', 'Outstanding business overdraft'],
  ['Planning', 'Planned payments', '/recurring', 'Scheduled and recurring records'],
  ['Planning', 'New planned payment', '/recurring/new', 'Create a payment plan'],
  ['Planning', 'Past planned payments', '/recurring/past', 'Completed plans'],
  ['Planning', 'Planned detail', '/recurring/demo-rent', 'Upcoming rent payment'],
  ['Planning', 'Edit planned payment', '/recurring/demo-rent/edit', 'Edit the sample rent plan'],
  ['Planning', 'Record planned payment', '/add?plannedId=demo-rent', 'Record an actual payment against a plan'],
  ['Planning', 'Salary plan history', '/recurring/demo-salary-plan', 'Monthly salary with thirty past credits'],
  ['Planning', 'Overdue bill details', '/recurring/demo-electricity', 'Overdue electricity bill with payment history'],
  ['Planning', 'Paused plan', '/recurring/demo-paused-yoga', 'Paused weekly yoga plan and previous payments'],
  ['Planning', 'Completed plan', '/recurring/demo-finished-course', 'Finished six-payment course installment plan'],
  ['Capture & import', 'Review inbox', '/review', 'Expense, income, refund and paired transfer captures; overdue, upcoming, card-due and statement alerts'],
  ['Capture & import', 'Capture detail', '/capture/demo-capture', 'Sample capture candidate; no real SMS content'],
  ['Capture & import', 'Salary capture', '/capture/demo-capture-salary', 'Suggested salary income record'],
  ['Capture & import', 'USD notification capture', '/capture/demo-capture-usd', 'Foreign-currency subscription notification'],
  ['Capture & import', 'Unmatched capture', '/capture/demo-capture-no-account', 'Choose the account for an unrecognized alert before saving'],
  ['Capture & import', 'Statement import', '/import-statement', 'Import a CSV or PDF using the browser file picker'],
  ['Capture & import', 'Import batch detail', '/imports/demo-import', 'Inspect a sample completed import'],
  ['Capture & import', 'Auto capture', '/auto-capture', 'Device capture setup; Android features unavailable in browser'],
  ['Capture & import', 'Capture diagnostics', '/auto-capture/debug', 'Capture pipeline diagnostics'],
  ['Capture & import', 'SMS import', '/import-sms', 'Android SMS capture settings'],
  ['Capture & import', 'Notification capture', '/notification-capture', 'Android notification capture settings'],
  ['Capture & import', 'Notification apps', '/notification-capture/apps', 'Supported notification sources'],
  ['Personalization', 'Settings', '/settings', 'Profile, privacy, appearance and app-tour replays'],
  ['Personalization', 'Update sheet', '/settings?updatePreview=available', 'Custom Google Play update half sheet with simulated download progress'],
  ['Personalization', 'Glass effects', '/settings/glass', 'Actual glass styling and component controls'],
  ['Personalization', 'Theme', '/settings/theme', 'Light, AMOLED and system appearance'],
  ['Personalization', 'Feedback', '/settings/feedback', 'Feedback form; external submission is not part of the demo'],
  ['Personalization', 'Dashboard widgets', '/widgets', 'Choose and arrange dashboard content'],
  ['Personalization', 'Categories', '/categories', 'Income and expense category management'],
  ['Personalization', 'Currencies', '/currencies', 'Currency preferences'],
  ['Privacy & data', 'Sync', '/sync', 'Offline-only status; Firebase is not initialized'],
  ['Privacy & data', 'Backup & restore', '/data-backup', 'Export or restore disposable sample data'],
  ['Privacy & data', 'Device permissions', '/device-permissions', 'Platform-specific permission settings'],
];

const flows = {
  setup: ['/login', '/permissions-setup', '/onboarding', '/'],
  expense: ['/', '/add?type=expense', '/?tab=1'],
  transfer: ['/accounts', '/add?type=transfer&accountId=demo-bank&counterAccountId=demo-cash', '/?tab=1'],
  plan: ['/recurring', '/recurring/new', '/recurring/demo-rent'],
  review: ['/review', '/capture/demo-capture', '/?tab=1'],
  appearance: ['/settings', '/settings/theme', '/settings/glass', '/widgets'],
};

let selected = screens[5];
let mode = 'preview';
let activeFlow = null;
let flowStep = 0;
let galleryObserver = null;
const $ = (id) => document.getElementById(id);
const workspace = $('workspace');

function appUrl(route) {
  const query = new URLSearchParams({ theme: $('theme').value, state: $('data-state').value });
  return `./app/?${query}#${route}`;
}

function visibleScreens() {
  const search = $('search').value.trim().toLowerCase();
  return screens.filter((screen) => screen.join(' ').toLowerCase().includes(search));
}

function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text) node.textContent = text;
  if (className) node.className = className;
  return node;
}

function makeFrame(screen) {
  const frame = document.createElement('iframe');
  frame.title = `1Wallet ${screen[1]}`;
  frame.src = appUrl(screen[2]);
  frame.loading = 'eager';
  // Keep demo actions inside their frame; do not permit popups or top navigation.
  frame.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-downloads');
  return frame;
}

function selectScreen(screen, keepFlow = false) {
  selected = screen;
  mode = 'preview';
  if (!keepFlow) activeFlow = null;
  render();
}

function renderLibrary() {
  const list = $('screen-list');
  list.replaceChildren();
  let group = '';
  for (const screen of visibleScreens()) {
    if (group !== screen[0]) {
      group = screen[0];
      list.append(element('div', group, 'section-label'));
    }
    const button = element('button', screen[1], `screen${screen === selected ? ' selected' : ''}`);
    button.setAttribute('aria-current', screen === selected ? 'page' : 'false');
    button.addEventListener('click', () => selectScreen(screen));
    list.append(button);
  }
}

function render() {
  galleryObserver?.disconnect();
  galleryObserver = null;
  renderLibrary();
  $('preview-mode').setAttribute('aria-pressed', String(mode === 'preview'));
  $('gallery-mode').setAttribute('aria-pressed', String(mode === 'gallery'));
  workspace.replaceChildren();
  if (mode === 'gallery') {
    const gallery = element('div', '', 'gallery');
    const boards = new Map();
    galleryObserver = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        const thumbnail = entry.target;
        if (entry.isIntersecting && !thumbnail.querySelector('iframe')) {
          thumbnail.replaceChildren(makeFrame(boards.get(thumbnail)));
        } else if (!entry.isIntersecting) {
          thumbnail.replaceChildren(element('p', 'Scroll here to preview', 'empty'));
        }
      }
    });
    let group = '';
    for (const screen of visibleScreens()) {
      if (group !== screen[0]) {
        group = screen[0];
        gallery.append(element('h2', group, 'gallery-heading'));
      }
      const board = element('section', '', 'artboard');
      const title = element('div', screen[1], 'artboard-title');
      const open = element('button', 'Open');
      open.setAttribute('aria-label', `Open ${screen[1]} in phone preview`);
      open.addEventListener('click', () => selectScreen(screen));
      title.append(open);
      const thumbnail = element('div', '', 'thumbnail');
      thumbnail.append(element('p', 'Scroll here to preview', 'empty'));
      boards.set(thumbnail, screen);
      galleryObserver.observe(thumbnail);
      board.append(title, thumbnail);
      gallery.append(board);
    }
    if (!visibleScreens().length) gallery.append(element('p', 'No matching screens.', 'empty'));
    workspace.append(gallery);
    return;
  }
  const [width, height] = $('device').value.split(',').map(Number);
  const layout = element('div', '', 'preview-layout');
  const phone = element('div', '', 'phone');
  phone.style.setProperty('--phone-width', `${width}px`);
  phone.style.setProperty('--phone-height', `${height}px`);
  const status = element('div', '', 'statusbar');
  status.append(element('span', '9:41'), element('span', 'Demo | 100%'));
  phone.append(status, makeFrame(selected), element('div', '', 'homebar'));
  const inspector = element('section', '', 'inspector');
  inspector.append(element('p', selected[0], 'section-label'), element('h2', selected[1]),
    element('p', selected[3], 'muted'), element('code', selected[2]), element('div', '', 'rule'));
  inspector.append(element('p', `${width} x ${height} logical pixels. Tap, scroll and type directly inside the phone.`, 'muted'));
  const reset = element('button', 'Reset this preview');
  reset.addEventListener('click', render);
  inspector.append(reset);
  if (activeFlow) {
    inspector.append(element('div', '', 'rule'), element('h2', `Flow ${flowStep + 1} / ${activeFlow.length}`),
      element('p', 'Use the real app controls, or jump between reference steps below. Jumping resets the frame data.', 'muted'));
    for (const [label, delta] of [['Previous step', -1], ['Next step', 1]]) {
      const button = element('button', label);
      button.disabled = flowStep + delta < 0 || flowStep + delta >= activeFlow.length;
      button.addEventListener('click', () => {
        flowStep += delta;
        selectScreen(screens.find((screen) => screen[2] === activeFlow[flowStep]), true);
      });
      inspector.append(button);
    }
  }
  layout.append(phone, inspector);
  workspace.append(layout);
}

$('preview-mode').addEventListener('click', () => { mode = 'preview'; render(); });
$('gallery-mode').addEventListener('click', () => { mode = 'gallery'; render(); });
$('search').addEventListener('input', () => mode === 'gallery' ? render() : renderLibrary());
for (const id of ['theme', 'device', 'data-state']) $(id).addEventListener('change', render);
$('wireframe').addEventListener('click', () => {
  const enabled = !$('workspace').classList.contains('wireframe');
  $('workspace').classList.toggle('wireframe', enabled);
  $('wireframe').setAttribute('aria-pressed', String(enabled));
});
document.querySelectorAll('[data-flow]').forEach((button) => {
  button.addEventListener('click', () => {
    activeFlow = flows[button.dataset.flow];
    flowStep = 0;
    if (button.dataset.flow === 'setup') $('data-state').value = 'empty';
    selectScreen(screens.find((screen) => screen[2] === activeFlow[0]), true);
  });
});
render();
