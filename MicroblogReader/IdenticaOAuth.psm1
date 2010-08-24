add-type -path $psscriptRoot\..\lib\DevDefined.OAuth.dll

$script:consumerKey = '';
$script:consumerSecret = ''

$script:accessToken = $null
$script:accessTokenPath = $null

function Set-ConsumerInfo {
	param(
		[Parameter(Mandatory=$true)]
		[string]
		$key,
		[Parameter(Mandatory=$true)]
		[string]
		$secret
	)
	$script:consumerKey = $key
	$script:consumerSecret = $secret
	
	Write-Debug "Key $key"
	Write-Debug "Secret $consumerSecret"
}

function Set-AccessTokenPath {
	param(
		[Parameter(Mandatory=$true)][string]$path
	)
	$script:accessTokenPath = $path
	if (Test-Path $path) {
		$script:accessToken = Import-Clixml -Path $path -EA stop	
	} else {
		Write-Host $path doesnt exist, so do request will not be handled
		Write-Host Either call the function again or register on Identica
	}
}

function Get-AccessToken {
	$token = new-object DevDefined.OAuth.Framework.TokenBase
	$token.ConsumerKey = $script:accessToken.ConsumerKey
	$token.Realm = $script:accessToken.Realm
	$token.Token = $script:accessToken.Token
	$token.TokenSecret = $script:accessToken.TokenSecret
	$token
	
	Write-Debug ($script:accessToken | Format-List | Out-String)
}

function Request-Identica {
	param(
		[Parameter(Mandatory=$true)][string]$url
	)
	if (!$script:accessToken) {
		throw 'token is not initialized'
	}
	try {
    $cons = New-Object devdefined.oauth.consumer.oauthconsumercontext
    $cons.ConsumerKey = $consumerKey
    $cons.ConsumerSecret = $consumerSecret
    $cons.SignatureMethod = [devdefined.oauth.framework.signaturemethod]::HmacSha1
    $session = new-object DevDefined.OAuth.Consumer.OAuthSession `
      $cons,
      "http://identi.ca/api/oauth/request_token",
      "http://identi.ca/api/oauth/authorize",
      "http://identi.ca/api/oauth/access_token"
    $token = Get-AccessToken 
    $req = $session.Request($token)
    $req.Context.RequestMethod = 'GET'
    $req.Context.RawUri = new-object Uri $url
    [DevDefined.OAuth.Consumer.ConsumerRequestExtensions]::ReadBody($req)
  } catch {
    Write-Warning "Exception: $_"
    $null
  }
}

function Register-OnIdentica
{
	$cons = New-Object devdefined.oauth.consumer.oauthconsumercontext
	$cons.ConsumerKey = $consumerKey
	$cons.ConsumerSecret = $consumerSecret
	$cons.SignatureMethod = [devdefined.oauth.framework.signaturemethod]::HmacSha1
	$session = new-object DevDefined.OAuth.Consumer.OAuthSession `
		$cons,
		"http://identi.ca/api/oauth/request_token",
		"http://identi.ca/api/oauth/authorize",
		"http://identi.ca/api/oauth/access_token"
	$rtoken = $session.GetRequestToken()
	$authLink = $session.GetUserAuthorizationUrlForToken($rtoken)
	write-host $authLink
	[diagnostics.process]::start($authLink)
	read-host -prompt '.. press Enter after you authorize the access'
	$accessToken = $session.ExchangeRequestTokenForAccessToken($rtoken)
	$accessToken | Export-Clixml $script:accessTokenPath
	$script:accessToken = $accessToken
}

Export-ModuleMember Set-ConsumerInfo, Set-AccessTokenPath, Request-Identica, Register-OnIdentica