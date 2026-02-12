const { chromium } = require('playwright');

(async () => {

  const CUSTOMER = process.env.CUSTOMER_CODE;
  const HOST = process.env.DATABRICKS_HOST;
  const PATH = process.env.DATABRICKS_SQL_PATH;
  const CLIENT_ID = process.env.SPN_CLIENT_ID;
  const CLIENT_SECRET = process.env.SPN_SECRET;

  const FABRIC_USER = process.env.FABRIC_USER;
  const FABRIC_PASS = process.env.FABRIC_PASS;

  const WORKSPACE_ID = process.env.FABRIC_WORKSPACE_ID;

  console.log("🚀 Starting Fabric UI automation for:", CUSTOMER);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  // 🔐 LOGIN
  await page.goto("https://app.fabric.microsoft.com");

  await page.waitForSelector('input[type="email"]');
  await page.fill('input[type="email"]', FABRIC_USER);
  await page.click('input[type="submit"]');

  await page.waitForSelector('input[type="password"]');
  await page.fill('input[type="password"]', FABRIC_PASS);
  await page.click('input[type="submit"]');

  await page.waitForLoadState('networkidle');

  // 📍 Navigate to workspace connections
  await page.goto(`https://app.fabric.microsoft.com/groups/${WORKSPACE_ID}/connections`);
  await page.waitForLoadState('networkidle');

  // ➕ Click New connection
  await page.getByRole('button', { name: /new connection/i }).click();

  await page.waitForLoadState('networkidle');

  // 🌐 Select Virtual Network
  await page.getByText(/virtual network/i).click();

  await page.waitForLoadState('networkidle');

  // 📝 Fill Form
  await page.getByLabel(/connection name/i).fill(CUSTOMER);

  await page.getByLabel(/server hostname/i).fill(HOST);
  await page.getByLabel(/http path/i).fill(PATH);

  // Credential Type dropdown
  await page.getByLabel(/authentication type/i).click();
  await page.getByText(/databricks client credentials/i).click();

  await page.getByLabel(/client id/i).fill(CLIENT_ID);
  await page.getByLabel(/client secret/i).fill(CLIENT_SECRET);

  // 💾 Save
  await page.getByRole('button', { name: /create|save/i }).click();

  await page.waitForTimeout(5000);

  console.log("✅ Fabric connection created");

  await browser.close();

})();
