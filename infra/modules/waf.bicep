// Azure Front Door (Standard) + WAF policy in front of the otp-serve App
// Service. Deployed at resource group scope (called from main.bicep).
//
// The origin is referenced by its predictable *.azurewebsites.net hostname
// (computed from the app name in main.bicep), NOT via the serve-app
// module's own output - this avoids a circular dependency: the serve app's
// Access Restrictions need this module's frontDoorId output to only allow
// Front Door traffic through, so the serve-app module depends on this one,
// not the other way around.
//
// WAF policy starts in Detection mode (logs matches, doesn't block) per
// plan - flip wafMode to 'Prevention' once logs have been reviewed for
// false positives against real OTP traffic.
//
// Front Door Standard (not Premium) - no Bot Manager rules, no Private
// Link to the origin needed per plan (origin stays public, locked down
// via the X-Azure-FDID header check instead).
//
// IMPORTANT: Front Door Standard's WAF does NOT support managed rule sets
// (Default Rule Set/OWASP protections, Bot Manager) at all - that's a
// Premium-only capability, confirmed 2026-08-12 after a deployment error
// ("...does not support ManagedRules"). Standard's WAF is limited to
// custom rules only. A baseline rate-limiting custom rule is included
// below; add more custom rules (IP/geo blocking, header/query matching)
// as needed - there's no signature-based attack detection on this tier.

@description('Name of the Front Door profile.')
param profileName string

@description('Name of the Front Door endpoint. Becomes part of the generated hostname, <endpointName>-<hash>.z01.azurefd.net.')
param endpointName string

@description('Name of the WAF policy. Must be alphanumeric only (no hyphens) per Azure Front Door WAF naming rules.')
param wafPolicyName string

@description('Hostname of the origin (the serve app), e.g. app-x-y.azurewebsites.net.')
param originHostName string

@description('WAF policy mode. Start in Detection, switch to Prevention once logs have been reviewed.')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Detection'

@description('''
Health probe path on the origin used by Front Door to check origin health.
Requires OTP's ActuatorAPI feature enabled in otp-config.json (otpFeatures.ActuatorAPI).
''')
param healthProbePath string = '/otp/actuators/health'

@description('Resource ID of the storage account to send Front Door/WAF diagnostic logs to.')
param logsStorageAccountId string

param tags object = {}

resource wafPolicy 'Microsoft.Network/frontdoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: wafPolicyName
  location: 'global'
  tags: tags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
    }
    // No managedRules block: Front Door Standard's WAF doesn't support
    // managed rule sets (see note above) - only customRules are allowed.
    customRules: {
      rules: [
        {
          name: 'RateLimitPerClientIP'
          priority: 100
          enabledState: 'Enabled'
          ruleType: 'RateLimitRule'
          rateLimitThreshold: 300
          rateLimitDurationInMinutes: 1
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'Contains'
              matchValue: [
                '/'
              ]
            }
          ]
          action: 'Block'
        }
      ]
    }
  }
}

resource profile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: profileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: profile
  name: endpointName
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: profile
  name: 'og-otp-serve'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: healthProbePath
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'otp-serve-origin'
  properties: {
    hostName: originHostName
    originHostHeader: originHostName
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: endpoint
  name: 'route-otp-serve'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    httpsRedirect: 'Enabled'
    linkToDefaultDomain: 'Enabled'
  }
  dependsOn: [
    origin
  ]
}

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  parent: profile
  name: 'secpolicy-otp-serve'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-otp-waf'
  scope: profile
  properties: {
    storageAccountId: logsStorageAccountId
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: true
      }
      {
        category: 'FrontDoorHealthProbeLog'
        enabled: true
      }
      {
        category: 'FrontDoorWebApplicationFirewallLog'
        enabled: true
      }
    ]
  }
}

output endpointHostName string = endpoint.properties.hostName
output frontDoorId string = profile.properties.frontDoorId
output profileName string = profile.name
output wafPolicyName string = wafPolicy.name
