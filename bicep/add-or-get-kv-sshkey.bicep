param deployRegion string = 'EastUS2'
param secretName string
param vaultName string
param secretTags object = {}
param identityId string

// https://docs.microsoft.com/en-us/azure/key-vault/keys/about-keys-details
@allowed([
  'rsa'
  'ec'
])
@metadata({
  ec: '"Software-protected" Elliptic Curve key'
  rsa: '"Software-protected" RSA key'
})
param keyType string = 'rsa'

@description('If keyType="ec", the curve type to use in generation of the key.')
@allowed([
  '256'
  '384'
  '521'
])
param ecType string = '256'

@description('If keyType="rsa", the key size to use in generation of the key.')
@allowed([
  '2048'
  '3072'
  '4096'
])
param rsaSize string = '2048'

param timestamp string = utcNow()

var keyOption = keyType == 'rsa' ? rsaSize : ecType

resource addOrCreateSecret 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'addOrCreateSecret${secretName}'
  location: deployRegion
  kind: 'AzurePowerShell'
  identity: empty(identityId) ? {} : {
    type:  'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '3.0'

    arguments: ' -secretName ${secretName} -vaultName ${vaultName} -secretType ${keyType}  -keyOption ${keyOption} -tagString \\"${secretTags}\\"'

    scriptContent: '''
    param(
      [string] $secretName,
      [string] $vaultName,
      [ValidateSet("ec",”rsa”)][string] $secretType,
      [string] $keyOption,
      [string] $tagString
      )

    Write-Host $tagString
    $tags = @{}
    ($tagString | ConvertFrom-Json).psobject.properties | Foreach { $tags[$_.Name] = $_.Value }

    $existing = @{
      privateKeyRef = $null
      publicKeyRef = $null
    }

    $existing.publicKeyRef = Get-AzKeyVaultSecret -VaultName $vaultName -Name "${secretName}PublicKey"
    $existing.privateKeyRef = Get-AzKeyVaultSecret -VaultName $vaultName -Name "${secretName}PrivateKey"
    $exists = $($existing.publicKeyRef -and $existing.privateKeyRef)

    if(!$exists){
      Write-Host "Creating ${secretType} key pair"

      switch ($secretType)
      {
          'rsa' {ssh-keygen -t rsa -b $keyOption -f $secretName -N '""'}
          'ec' {ssh-keygen -t ed25519 -b $keyOption -f $secretName -N '""'}
      }

      $secretValue = @{
          privateKey = $(Get-Content $secretName -Raw | ConvertTo-SecureString -AsPlainText -Force)
          publicKey = $(Get-Content "${secretName}.pub" -Raw | ConvertTo-SecureString -AsPlainText -Force)
      }

      $existing.privateKeyRef = $(Set-AzKeyVaultSecret -VaultName $vaultName -Name "${secretName}PrivateKey" -SecretValue $secretValue.privateKey -ContentType "${secretType}-privateKey" -Tags $tags)
      $existing.publicKeyRef = $(Set-AzKeyVaultSecret -VaultName $vaultName -Name "${secretName}PublicKey" -SecretValue $secretValue.publicKey  -ContentType "${secretType}-publicKey"  -Tags $tags)
    
    }

    $DeploymentScriptOutputs['secrets'] = $existing
    '''
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT1H'
    forceUpdateTag: timestamp
  }
}


output deployedSecrets object = addOrCreateSecret.properties.outputs.secrets
output publicKeySecretName string = '${secretName}PublicKey'
output privateKeySecretName string = '${secretName}PrivateKey'
