// Azure Front Door  + WAF policy in front of the otp-serve App Service.
// Deployed at resource group scope
//
// The origin is referenced by its predictable *.azurewebsites.net hostname
// (computed from the app name in main.bicep), NOT via the serve-app modules input. This is to avoid circular dependency.
//
// With Front Door Standard managed rules for WAF are not supported. Only some basic custom rules are implemented

@description('Name of the Front Door profile.')
param profileName string

@description('Name of the Front Door endpoint. Becomes part of the generated hostname, <endpointName>-<hash>.z01.azurefd.net.')
param endpointName string

@description('Name of the WAF policy. Must be alphanumeric only (no hyphens) per Azure Front Door WAF naming rules.')
param wafPolicyName string

@description('Hostname of the origin (the serve app), e.g. app-x-y.azurewebsites.net.')
param originHostName string

@description('WAF policy mode')
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
    // No managedRules block: Front Door Standard's WAF doesn't support it. Only customRules are allowed.
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
        {
          // OTP's REST/GraphQL APIs only need GET/HEAD/OPTIONS/POST - block
          // anything else (PUT, DELETE, TRACE, CONNECT, PATCH, ...).
          name: 'BlockDisallowedHttpMethods'
          priority: 110
          enabledState: 'Enabled'
          ruleType: 'MatchRule'
          matchConditions: [
            {
              matchVariable: 'RequestMethod'
              operator: 'Equal'
              negateCondition: true
              matchValue: [
                'GET'
                'HEAD'
                'OPTIONS'
                'POST'
              ]
            }
          ]
          action: 'Block'
        }
        {
          // Size constraint: reject abnormally long request URIs
          name: 'BlockOversizedUri'
          priority: 120
          enabledState: 'Enabled'
          ruleType: 'MatchRule'
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'GreaterThan'
              matchValue: [
                '2048'
              ]
            }
          ]
          action: 'Block'
        }
        {
          // Size constraint: reject abnormally long query strings.
          name: 'BlockOversizedQueryString'
          priority: 130
          enabledState: 'Enabled'
          ruleType: 'MatchRule'
          matchConditions: [
            {
              matchVariable: 'QueryString'
              operator: 'GreaterThan'
              matchValue: [
                '2048'
              ]
            }
          ]
          action: 'Block'
        }
        {
          // Best-effort blocklist of common scanner/attack-tool user agents.
          name: 'BlockKnownBadUserAgents'
          priority: 140
          enabledState: 'Enabled'
          ruleType: 'MatchRule'
          matchConditions: [
            {
              matchVariable: 'RequestHeader'
              selector: 'User-Agent'
              operator: 'Contains'
              transforms: [
                'Lowercase'
              ]
              matchValue: [
                'sqlmap'
                'nikto'
                'nmap'
                'masscan'
                'nessus'
                'acunetix'
                'nuclei'
                'w3af'
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
