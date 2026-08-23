// Dzienny snapshot wartości portfela inwestycyjnego (uruchamiany cronem
// w GitHub Actions). Bez tego wykres wartości w czasie rośnie tylko gdy
// ktoś wejdzie w zakładkę Inwestycje. Tu liczymy wartość raz dziennie po
// stronie serwera i zapisujemy do `portfolio_snapshots`.
//
// Źródła kursów (te same, darmowe co w apce):
//   krypto → CoinGecko (vs PLN), złoto → NBP (PLN/g),
//   srebro → stooq XAG/USD × kurs USD/PLN z NBP ÷ 31.1035.
//
// Wymaga env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (bypass RLS).
// Best-effort: gdy jakieś źródło padnie, pomijamy te pozycje (wartość
// zakupu jako fallback), nie wywracając całego joba.

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('Brak SUPABASE_URL lub SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

const restHeaders = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  'Content-Type': 'application/json',
};

async function getJson(url, opts = {}) {
  const resp = await fetch(url, opts);
  if (!resp.ok) throw new Error(`${resp.status} ${url}`);
  return resp.json();
}

async function fetchCryptoPln(ids) {
  const out = {};
  if (ids.length === 0) return out;
  try {
    const url =
      `https://api.coingecko.com/api/v3/coins/markets` +
      `?vs_currency=pln&ids=${encodeURIComponent(ids.join(','))}`;
    const list = await getJson(url);
    for (const row of list) {
      if (row.id != null && row.current_price != null) {
        out[row.id] = Number(row.current_price);
      }
    }
  } catch (e) {
    console.error('CoinGecko:', e.message);
  }
  return out;
}

async function fetchGoldPlnPerGram() {
  try {
    const list = await getJson('https://api.nbp.pl/api/cenyzlota');
    return Number(list[list.length - 1].cena);
  } catch (e) {
    console.error('NBP gold:', e.message);
    return null;
  }
}

async function fetchUsdPln() {
  try {
    const j = await getJson('https://api.nbp.pl/api/exchangerates/rates/a/usd');
    return Number(j.rates[0].mid);
  } catch (e) {
    console.error('NBP usd:', e.message);
    return null;
  }
}

async function fetchSilverPlnPerGram() {
  try {
    const resp = await fetch(
      'https://stooq.pl/q/l/?s=xagusd&f=sd2t2ohlcv&h&e=csv',
    );
    if (!resp.ok) return null;
    const text = await resp.text();
    const lines = text.trim().split('\n');
    if (lines.length < 2) return null;
    const cols = lines[1].split(',');
    const usdPerOz = Number(cols[6]);
    const usdPln = await fetchUsdPln();
    if (!usdPerOz || !usdPln) return null;
    return (usdPerOz * usdPln) / 31.1035;
  } catch (e) {
    console.error('stooq silver:', e.message);
    return null;
  }
}

function todayIso() {
  // Data polska (nie UTC) — apka upsertuje snapshot po dacie lokalnej
  // telefonu, więc cron musi celować w ten sam wiersz, inaczej między
  // 00:00 a 02:00 czasu PL powstają dwa snapshoty na dobę.
  return new Date().toLocaleDateString('en-CA', {
    timeZone: 'Europe/Warsaw',
  });
}

async function main() {
  const investments = await getJson(
    `${SUPABASE_URL}/rest/v1/investments?select=id,household_id,asset_type,symbol,quantity,buy_price_cents`,
    { headers: restHeaders },
  );
  if (investments.length === 0) {
    console.log('Brak inwestycji — nic do zapisania.');
    return;
  }

  // Sprzedane ilości per pozycja (migracja 0010) — liczymy wartość tylko
  // z części POZOSTAŁEJ, tak samo jak apka. Bez tego cron zawyżał wykres
  // o sprzedane jednostki i nadpisywał poprawny snapshot z apki.
  const sales = await getJson(
    `${SUPABASE_URL}/rest/v1/investment_sales?select=investment_id,quantity`,
    { headers: restHeaders },
  );
  const soldByInvestment = new Map();
  for (const s of sales) {
    soldByInvestment.set(
      s.investment_id,
      (soldByInvestment.get(s.investment_id) ?? 0) + Number(s.quantity),
    );
  }

  const cryptoIds = [
    ...new Set(
      investments
        .filter((i) => i.asset_type === 'crypto')
        .map((i) => i.symbol),
    ),
  ];
  const needGold = investments.some((i) => i.asset_type === 'gold');
  const needSilver = investments.some((i) => i.asset_type === 'silver');

  const [cryptoPrices, goldPg, silverPg] = await Promise.all([
    fetchCryptoPln(cryptoIds),
    needGold ? fetchGoldPlnPerGram() : Promise.resolve(null),
    needSilver ? fetchSilverPlnPerGram() : Promise.resolve(null),
  ]);

  const priceFor = (inv) => {
    if (inv.asset_type === 'crypto') return cryptoPrices[inv.symbol] ?? null;
    if (inv.asset_type === 'gold') return goldPg;
    if (inv.asset_type === 'silver') return silverPg;
    return null;
  };

  const totals = new Map(); // household_id → cents
  for (const inv of investments) {
    const price = priceFor(inv);
    const qty = Number(inv.quantity) - (soldByInvestment.get(inv.id) ?? 0);
    // Pozycja w całości sprzedana → 0 zł, ale wiersz household zostaje
    // (portfel spadł do zera — apka liczy tak samo, wykres to pokaże).
    const valuePln =
      qty <= 0
        ? 0
        : price == null
          ? (qty * inv.buy_price_cents) / 100
          : qty * price;
    const cents = Math.round(valuePln * 100);
    totals.set(inv.household_id, (totals.get(inv.household_id) ?? 0) + cents);
  }

  const captured_at = todayIso();
  const rows = [...totals.entries()].map(([household_id, total_value_cents]) => ({
    household_id,
    total_value_cents,
    captured_at,
  }));

  const resp = await fetch(
    `${SUPABASE_URL}/rest/v1/portfolio_snapshots?on_conflict=household_id,captured_at`,
    {
      method: 'POST',
      headers: { ...restHeaders, Prefer: 'resolution=merge-duplicates' },
      body: JSON.stringify(rows),
    },
  );
  if (!resp.ok) {
    console.error('Upsert nieudany:', resp.status, await resp.text());
    process.exit(1);
  }
  console.log(`Zapisano ${rows.length} snapshot(ów) na ${captured_at}.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
