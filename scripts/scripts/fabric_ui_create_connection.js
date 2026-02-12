const { chromium } = require('playwright');

(async () => {

  const CUSTOMER = process.env.CUSTOMER_CODE;
  const HOST = process.env.DATABRICKS_HOST;
  const PATH = process.env.DATABRICKS_SQL_PATH;
  const CLIENT_ID = process.env.SPN_CLIENT_ID;
  const CLIENT_SECRET = process.env.SPN_SECRET;

  const FABRIC_USER = process.env.FABRIC_USER;
  const FABRIC_PASS = process.env.FABRIC_PASS;

  console.log("=================================");
  console.log("🚀 FABRIC UI AUTOMATION STARTED");
  console.log("Customer:", CUSTOMER);
  console.log("=================================");

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  // 1️⃣ Login
  await page.goto("https://app.fabric.microsoft.com");

  await page.fill('input[type="email"]', FABRIC_USER);
  await page.click('input[type="submit"]');

  await page.waitForTimeout(3000);

  await page.fill('input[type="password"]', FABRIC_PASS);
  await page.click('input[type="submit"]');

  await page.waitForTimeout(8000);

  // 2️⃣ Navigate to Manage Connections
  await page.goto("https://app.fabric.microsoft.com/groups/me/connections");

  await page.waitForTimeout(5000);

  // 3️⃣ Click New Connection
  await page.click('text=New connection');

  await page.waitForTimeout(3000);

  // 4️⃣ Select Virtual Network
  await page.click('text=Virtual network');

  await page.waitForTimeout(2000);

  // 5️⃣ Fill Form

  await page.fill('input[placeholder="Connection name"]', CUSTOMER);

  await page.fill('input[placeholder="example.azuredatabricks.net"]', HOST);
  await page.fill('input[placeholder="/sql/1.0/warehouses/abcd"]', PATH);

  await page.selectOption('select', { label: 'Databricks Client Credentials' });

  await page.fill('input[aria-label="Databricks Client ID"]', CLIENT_ID);
  await page.fill('input[aria-label="Databricks Client Secret"]', CLIENT_SECRET);

  // 6️⃣ Submit
  await page.click('text=Save');

  await page.waitForTimeout(8000);

  console.log("✅ Connection Created Successfully");

  await browser.close();

})();
