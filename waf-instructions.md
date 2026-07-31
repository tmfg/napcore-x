# WAF Integration — Steps Needed

Notes for when the organisation's WAF is put in front of the OTP serve app
([infra/modules/serve-app.bicep](infra/modules/serve-app.bicep)). Exact steps
depend on which WAF product the org uses — confirm with the networking team,
then follow the matching section below.

## Steps needed regardless of WAF type

1. **Pick/confirm the public hostname** the WAF will present (e.g.
   `otp.yourcompany.com`) — the org's WAF is the thing users hit, not
   `*.azurewebsites.net` directly.
2. **Give the networking team the origin info**: current default hostname
   (`serveApp.properties.defaultHostName` output from
   [infra/modules/serve-app.bicep](infra/modules/serve-app.bicep)), and
   confirm the app already speaks HTTPS only (`httpsOnly: true` is already
   set).
3. **Confirm/add a health-check path** the WAF's health probe can hit. Check
   what OTP exposes (likely `/otp/actuators/health` or similar) — if there
   isn't a lightweight one, add or document one so the WAF doesn't mark the
   origin unhealthy under load.
4. **Lock down direct access to the origin** once the WAF is in place, so
   people can't bypass it by hitting `*.azurewebsites.net` directly — done
   via App Service Access Restrictions (`ipSecurityRestrictions` in
   `siteConfig`), scoped to only the WAF's IPs/service tag.
5. **Custom domain + certificate ownership**: decide who manages the TLS
   cert for the public hostname — usually the WAF/edge layer terminates TLS
   and the org owns that cert; the App Service origin can keep using its own
   managed cert for the backend hop.

## Where it diverges

- **Azure Front Door (edge/global)**: Access Restrictions alone aren't
  enough because Front Door's IP ranges are shared across all Azure
  customers — must also validate the `X-Azure-FDID` header (or
  `X-Forwarded-Host`) against the org's specific Front Door instance ID,
  otherwise anyone with any Front Door profile could reach the origin. No
  plan-tier change needed; stays on Basic B2.
- **Application Gateway (regional/VNet)**: if the networking team wants a
  fully private origin (no public IP at all), the App Service needs
  **Private Endpoint** support, which requires upgrading from Basic to
  **Premium V2/V3** — a real cost and tier change to confirm before making.
  If they're fine with a public origin restricted by IP, Basic B2 stays
  fine.

## Status

Pending — waiting to hear back from the org's networking team on which WAF
product will be used and whether private connectivity (Private
Endpoint/VNet) is required. No Bicep changes made yet for this.

## Dev environment: keeping it non-public while allowing developer access

The dev deployment might not need public access at all. Two options,
depending on how developers connect:

### Option 2 — Auth-based restriction (Azure AD / Easy Auth), for individual/dynamic-IP developers

Since IP allow-listing doesn't work without fixed IPs, restrict by
**identity** instead of network:

1. Enable App Service's built-in Authentication (**Easy Auth** /
   `authsettingsV2`) with Microsoft Entra ID (Azure AD) as the identity
   provider — a `Microsoft.Web/sites/config` child resource (name
   `authsettingsV2`), same pattern as the existing `azurestorageaccounts`
   config block in [infra/modules/serve-app.bicep](infra/modules/serve-app.bicep).
2. Set `globalValidation.requireAuthentication: true` and
   `unauthenticatedClientAction: 'RedirectToLoginPage'` (or `'Return401'`
   if it's mostly API calls rather than browser use).
3. Register an app in Entra ID (can be an "Express" registration done
   automatically by the portal, or a proper App Registration Bicep
   resource).
4. **Restrict to just the dev team**: create an Entra ID security group
   with the developers, then set "Assignment required" on the app's
   Enterprise Application and assign only that group — otherwise anyone in
   the whole tenant could sign in.
5. Works from anywhere (home, laptop, coffee shop) since it's
   identity-based, not network-based — no VPN needed.
6. Trade-off: adds a login redirect in front of the app. Fine for browser
   use; if the API is also hit directly/programmatically (curl, automated
   tests), bearer tokens would be needed instead of the redirect flow —
   some extra friction for non-interactive testing.
7. No plan-tier change needed, stays on Basic B2. Cheaper/faster option.

### Option 3 — Fully private (VNet-only, no public endpoint at all)

More isolation, more infrastructure:

1. **Upgrade the App Service Plan from Basic to Premium V2/V3** — Private
   Endpoints for App Service require Premium v2/v3 (or Isolated v2);
   Basic/Standard don't support it. Real cost increase.
2. Create/reuse a **VNet + subnet** in the resource group.
3. Add a **Private Endpoint** (`Microsoft.Network/privateEndpoints`)
   targeting the web app (`sites` group ID), plus a **Private DNS Zone**
   (`privatelink.azurewebsites.net`) linked to the VNet so the app's
   hostname resolves privately.
4. Set `publicNetworkAccess: 'Disabled'` on the web app — the public
   `*.azurewebsites.net` hostname stops working entirely.
5. Developers then need a way _into_ that VNet: Point-to-Site VPN,
   ExpressRoute, VNet peering from a network they already connect to, or a
   bastion/jump box — the real friction point if the org doesn't already
   have VPN infra for dev access.

### Recommendation

For a dev environment, Option 2 is usually the better fit unless there's a
compliance requirement mandating no public endpoint at all — cheaper,
faster, and doesn't require developers to have VPN access set up.

Status: no changes made yet, decision pending.
