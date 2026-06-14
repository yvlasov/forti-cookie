import asyncio
import os
import sys
import time
from playwright.async_api import async_playwright

async def get_forti_cookie():
    host = os.environ.get("FORTI_VPN_HOST", "vpn.example.com")
    username = os.environ.get("FORTI_VPN_USER", r"DOMAIN\username")
    headless = os.environ.get("HEADLESS", "true").lower() != "false"
    debug = os.environ.get("DEBUG", "false").lower() == "true"

    password = os.environ.get("FORTI_VPN_PASSWORD")
    if not password:
        try:
            with open("/run/secrets/vpn_password") as f:
                password = f.read().strip()
        except FileNotFoundError:
            pass
    if not password:
        print("Error: FORTI_VPN_PASSWORD not set and /run/secrets/vpn_password not found", file=sys.stderr)
        sys.exit(1)

    os.makedirs("/output", exist_ok=True)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=headless)
        context = await browser.new_context()
        page = await context.new_page()

        await page.goto(f"https://{host}/remote/login", timeout=30_000)

        if debug:
            await page.screenshot(path="/output/login_page.png")

        await page.wait_for_selector('#username', timeout=15_000)
        await page.fill('#username', username)
        await page.fill('#credential', password)
        await page.click('#login_button')

        print("Approve push notification in Microsoft Authenticator...")

        svpncookie = None
        all_cookies = []
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            all_cookies = await context.cookies()
            svpncookie = next((c for c in all_cookies if c["name"] == "SVPNCOOKIE"), None)
            if svpncookie:
                break
            await asyncio.sleep(2)

        if debug:
            try:
                await page.screenshot(path="/output/post_login.png")
            except Exception:
                pass

        await browser.close()

        if svpncookie:
            with open("/output/cookie.txt", "w") as f:
                f.write(svpncookie["value"])
            print(f"FORTI_VPN_COOKIE={svpncookie['value']}")
        else:
            print("SVPNCOOKIE not found — dumping all cookies:", file=sys.stderr)
            for c in all_cookies:
                print(f"  {c['name']}={c['value'][:60]}", file=sys.stderr)
            sys.exit(1)

asyncio.run(get_forti_cookie())
