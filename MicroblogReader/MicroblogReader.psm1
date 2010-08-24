# v 1.0.0.2
# - OAuth support for Twitter
# v 1.0.0.1

# regex to match url
# http://snipplr.com/view/2371/regex-regular-expression-to-match-a-url/
$script:RegexUrl = ([regex]$r = [regex]'(https?:(?://|\\\\)+[\w\d:#@%/;$()~_?+\-=\\\.&*]*[\w\d:#@%/;$()~_+\-=\\&*])')

#
# Utils
################################################################################################################################
$security = New-Object PSObject
# gets secure string and picks the string from it
function Unwrap-FromSecureString {
	param([system.security.securestring]$str)
	Write-Debug "From secure string: $str"
	$marshal = [Runtime.InteropServices.Marshal]
	$ret = $marshal::PtrToStringAuto($marshal::SecureStringToBSTR($str))
	Write-Debug "From secure string result: $ret"
	$ret
}

#encrypts plain string into secure string
function Encrypt-String {
	param(
		[Parameter(Position=0, Mandatory=$true, ValueFromPipeLine=$true)][string]$str, 
		[object]$key,
		[switch]$keyIsSecureString)
	Write-Debug "Encrypting $str"
	if ($keyIsSecureString) { $key = Unwrap-FromSecureString $key }
	$byteKey = 0..15 | % { if ($_ -lt $key.Length) { [byte]$key[$_]} else { 1 }}
	ConvertFrom-SecureString $(if($isAlreadySecureString){$str}else{ ConvertTo-SecureString $str -asplain -force}) -key $byteKey
}

#decrypts string crypted by Encrypt
function Decrypt-String {
	param(
		[string]$crypted,
		[string]$key
	)
	Write-Debug "Decrypting $crypted"
	$byteKey = 0..15 | % { if ($_ -lt $key.Length) { [byte]$key[$_]} else { 1 }}	# the 1s are there just to fill the array with something
	Write-Debug "Converting to secure string passeed with key"
	$secure = ConvertTo-SecureString $crypted -key $byteKey
	Unwrap-FromSecureString $secure
 }
 
function Download-XmlFromUrl {
	param(
		[Parameter(Position=0, Mandatory=$false)] [PsCustomObject] $service,
		[Parameter(Position=1, Mandatory=$true)] [string]$url
	)
	Write-Debug "url to fetch: $url"
	$request = [Net.WebRequest]::Create($url)
	$request.Timeout = $request.ReadWriteTimeout = -1
	
	if ($service) {
		$request.Credentials = New-Object System.Net.NetworkCredential($service.User,$service.Password)
		Write-Debug "Credentials: $($service.User) / $($service.Password)"
	}else {
		Write-Debug "No credentials provided"
	}
	$request.Method = "GET"
	try {
		$response = $request.GetResponse()
		$reader = [System.IO.StreamReader]$response.GetResponseStream()
		$ret = $reader.ReadToEnd()
		$reader.close()
		Write-Debug "Length of response: $($ret.Length)"
		[xml]$ret
	}
	catch {
		Write-Warning "Error when fetching the content, url: $url"
		Write-Warning "Exception: $_"
		#Write-Warning ($error[0] | select *)
		$null
	}
}

# gets last status id for given service
function Get-LastFetchedStatusId {
	param(
		[Parameter(Position=0, Mandatory=$true)] [PsCustomObject] $service
	)
	$statusFile = (Join-Path $script:BaseDirectory ("lastStatus-{0}-{1}.txt" -f $service.App,$service.User))
	$lastStatusId = 1
	if (test-path $statusFile) {
		$lastStatusId = gc $statusFile -ea Continue
	}
	Write-Debug "last status $lastStatusId"
	$lastStatusId
}

# stores last status id for given service; called after statuses from the service were retrieved
function Set-LastFetchedStatusId {
	param(
		[Parameter(Position=0, Mandatory=$true)] [PsCustomObject] $service,
		[Parameter(Position=1, Mandatory=$true)] [string] $lastStatusId
	)
	$lastStatusId | sc (Join-Path $script:BaseDirectory ("lastStatus-{0}-{1}.txt" -f $service.App,$service.User))
}
 # this is to overcome bug with powerboots (or .NET)
 # downloads user image if not already cached and returns path to disk
 function Get-ImagePath {
 	param(
		[Parameter(Position=0, Mandatory=$true)] [PsCustomObject] $status,
		[Parameter(Position=1, Mandatory=$true)] [PsCustomObject] $imageCacheDir
	)
	$fileName = "{0}-{1}-{2}" -f $status.App,$status.UserName,([System.IO.Path]::GetFileName($status.UserProfileImage))
	$fullName = (Join-Path $imageCacheDir $fileName)
	Write-Debug "file name: $fileName ; full name: $fullName"
	try {
		if (!(Test-Path $fullName)) {
			Write-Debug "downloading $($status.UserProfileImage)"
			$downloader = New-Object System.Net.WebClient
			[System.IO.File]::WriteAllBytes($fullName, $downloader.DownloadData($status.UserProfileImage))
		}
		$fullName
	}catch {
		Write-Warning "Can not load image $($status.UserProfileImage)"
		$null
	}
 }

#
# Twitter API
################################################################################################################################

$twitterApi = New-Object PSObject
$twitterApi | Add-Member ScriptMethod CreateStatusInfo {
	param(
		[Parameter(Mandatory=$true)] [PsCustomObject] $service,
		[Parameter(Mandatory=$true)] [System.Xml.XmlElement] $status
	)
	function parseBool($str, $context) {
		if (!$str){ Write-Host "empty bool at $context"; $false 
		} elseif ($str -match '^(true|false)$') { [bool]::Parse($str) 
		} else { Write-Host "no bool match at $context"; $false }
	}
	$info = new-object PSObject
	$info.PSObject.TypeNames.Insert(0,’TwitterStatusInfo’)
	$info | Add-Member Noteproperty App $service.App
	$info | Add-Member Noteproperty Account $service.User
	$info | Add-Member Noteproperty StatusId ([long]($status.id))
	$info | Add-Member NoteProperty Text $status.text
	$info | Add-Member NoteProperty Date $this.ParseDate($status.created_at)
	$info | Add-Member NoteProperty UserName $status.user.screen_name
	$info | Add-Member NoteProperty UserId $status.user.name
	$info | Add-Member NoteProperty UserProfileImage $status.user.profile_image_url
	$info | Add-Member NoteProperty UserProtected $status.user.protected.Trim() #(parsebool  'protected')
	$info | Add-Member NoteProperty UserFollowersCount ([int]$status.user.followers_count)
	$info | Add-Member NoteProperty UserFriendsCount ([int]$status.user.friends_count)
	$info | Add-Member NoteProperty UserCreationDate $this.ParseDate($status.user.created_at)
	$info | Add-Member NoteProperty UserFavoritesCount ([int]$status.user.favorites_count)
	$info | Add-Member NoteProperty UserOffset ([int]$status.user.utc_offset)
	$info | Add-Member NoteProperty UserUrl $status.user.url
	$info | Add-Member NoteProperty UserStatusesCount ([int]$status.user.statuses_count)
	$info | Add-Member NoteProperty UserIsFollowing $status.user.following.Trim() #(parseBool 'following')
	$info | Add-Member NoteProperty Color $service.Color
	$info | Add-Member NoteProperty ReplyTo ([long]$(if($status.in_reply_to_status_id -match '\d'){[long]$status.in_reply_to_status_id}else{-1}))
	$info | Add-Member NoteProperty Replies @()
	$info | Add-Member NoteProperty ReplyParent $null
	$info | Add-Member Noteproperty Type ($this)
	$info | Add-Member Noteproperty ShortInfo ("$($status.id):: ($($status.user.screen_name)) - $($status.Text.Substring(0,[Math]::Min(40,$status.Text.Length)))..., replyTo: $($status.in_reply_to_status_id)")
	$info | Add-Member Noteproperty ShortShortInfo ("$($status.Text.Substring(0,[Math]::Min(40,$status.Text.Length)))...")
	$info | Add-Member Noteproperty ExtraDownloaded $false
	$info | Add-Member Noteproperty Hidden $false
	# see Remove-MbStatuses
	# this method accepts the array of filters like @({'Account'='Identica'; 'User'='halr9000'}) and returns true if the current status matches the filter
	$info | Add-Member ScriptMethod Matches {
		param([object[]] $itemsToRemove)
		Write-Debug "Examining $($this.ShortShortInfo)"
		$isMatch = $false
		$itemsToRemove | % {
			$filter = $_
			if (!($filter -is [System.Collections.Hashtable])) {
				#it's just a string that identifies user, let's make it hash to simplify things
				$filter = @{'User' = $filter}
			}
			#todo: refactor
			$countOfMissingMatches = $filter.Keys.Count
			Write-Debug "Keys count: $countOfMissingMatches"
			$filter.Keys | % {
				$value = $filter[$_]
				switch ($_) {
					'App'    { if ($this.App      -eq $value)    { Write-Debug "matches app: $value"; $countOfMissingMatches-- } }
					'User'   { if ($this.UserName -match $value) { Write-Debug "matches user: $value";$countOfMissingMatches--} }
					'Account'{ if ($this.Account  -match $value) { Write-Debug "matches account: $value";$countOfMissingMatches--} }
					'Regex'  { if ($this.Text     -match $value) { Write-Debug "matches regex: $value";$countOfMissingMatches--} }
					default  { Write-Host ("Filter key {0} is not known" -f $_) -ForegroundColor Red }
				}
			}
			if ($countOfMissingMatches -eq 0) { 
				Write-Debug "Status $($status.ShortShortInfo) is hidden"; 
				$isMatch = $true
			} else {
				Write-Debug "not match; missing: $countOfMissingMatches"
			}
		}
		$isMatch
	}
	$info
}

# status returned when some error occured when retrieving some status
$twitterApi | Add-Member Noteproperty ErrorStatus ([xml]("<status>" + `
		"<id>1</id><text>error</text><created_at>Sun May 10 20:00:00 +0000 2009</created_at>" + `
		"<user><name>err</name><screen_name>Error</screen_name><profile_image_url></profile_image_url>
      <url></url><protected>false</protected><followers_count>0</followers_count><friends_count>0</friends_count>
      <created_at>Fri Apr 18 02:29:12 +0000 2008</created_at><favourites_count>0</favourites_count>
      <utc_offset>0</utc_offset>
      <statuses_count>0</statuses_count>
      <notifications>false</notifications><geo_enabled>false</geo_enabled><verified>false</verified><following>false</following>
    </user></status>")) # some persistent image should be referenced
# stores the passed status 
$twitterApi | Add-Member ScriptMethod StatusToFile {
	param(
		[Parameter(Position=0, Mandatory=$true)] [PsCustomObject] $service,
		[Parameter(Position=1, Mandatory=$true)] [PSCustomObject] $status
	)
	$fileName = (Join-Path $script:StatusesDirectory ("{0}-{1}-{2}.xml" -f $service.App,$service.User,$status.statusId))
	Write-Debug "Export to $fileName"
	$status | Export-Clixml $fileName
}

# read status from file (stored by StatusToFile)
# todo: use this when downloading reply parents
$twitterApi | Add-Member ScriptMethod StatusFromFile {
	param(
		[Parameter(Position=0, Mandatory=$true)] [PsCustomObject] $service,
		[Parameter(Position=1, Mandatory=$true)] [long] $statusId
	)
	$fileName = (Join-Path $script:StatusesDirectory ("{0}-{1}-{2}.xml" -f $service.App,$service.User,$statusId))
	if (Test-Path $fileName -ErrorAction SilentlyContinue) {
		Write-Debug "Import from $fileName"
		$ret = Import-Clixml -Path $fileName
		Write-Debug "Imported: $ret"
		$ret.Replies = @()
		$ret.ReplyParent = $null
		$ret.type = GetServiceByName $ret.App
		$ret
	} else {
		Write-Debug "$fileName not found"
		$null
	}
}

# downloads status with given id
$twitterApi | Add-Member ScriptMethod DownloadStatus {
	param([long]$statusId, [scriptblock]$downloader, [PsCustomObject]$obj)
	$url = ($obj.StatusUrl -f $statusId)
	Write-Debug "url to download: $url"
	$item = & $downloader $url
	if ($item -and $item.status) { 
		Write-Debug "Read status for $statusId" 
		$item 
	}
	else { 
		Write-Debug "Unable to read status for $statusId";
		return $null 
	}
}

# gets all new statuses
# (all new statuses from the passed service are called)
$twitterApi | Add-Member ScriptMethod FetchNewStatuses {
	param(
		[Parameter(Mandatory=$true)] [PsCustomObject] $service,
		[Parameter(Mandatory=$true)] [scriptblock]$downloader,
		[Parameter(Mandatory=$true)] [PsCustomObject]$obj
	)
	function download {	param($url, $filePrefix)
		Write-Debug "Getting statuses for $($service.App)"
		Write-Debug "url is $url"
		$statuses = & $downloader $url
		if (!$statuses) {
			Write-Warning "Unable to download statuses for $($service.App): $($service.User)"
			return @()
		}
		$fileName = (Join-Path $script:BaseDirectory ("$($filePrefix)-{0}-{1}.xml" -f $service.App,$service.User))
		$statuses.Save($fileName) 
		Write-Debug "statuses read"	
		if (!$statuses.statuses -or !$statuses.statuses.status) { 
			Write-Debug "statuses are empty!"
			return @()
		}
		$statuses.statuses.status
	}
	Write-Debug "going to read statuses for $($service.App): $($service.User)"
	$lastStatusId = Get-LastFetchedStatusId $service
	$statuses     = @(download ($obj.FriendsUrl -f $lastStatusId) "currStatuses")
	$directMessages = @(download ($obj.DirectMessagesUrl -f $lastStatusId) "directMessages")
	
	$statusesById = @{}
	Write-Debug "count: $(@($statuses.statuses.status).count)"	#$statuses.statuses.status muze byt 1 prvek,proto @(..)
	@($statuses + $directMessages) | % {
		$statusInfo = $obj.CreateStatusInfo($service, $_)
		$statusesById[$statusInfo.StatusId] = $statusInfo
		$lastStatusId = [Math]::Max([long]$lastStatusId, [long]$_.id)
		$this.StatusToFile($service, $statusInfo)
	}
	
	Write-Debug "new last status id: $lastStatusId"
	Set-LastFetchedStatusId $service $lastStatusId
	$statusesById
}

# adds reply parents for all statuses that are replies
# (reply parent is a status that has some replies)
# why: in your friends statuses there are some replies. And it would be very useful to see to what status the reply is (like at Jaiku), so
#  I'd like to get the original 'question' and the current status display below it.
$twitterApi | Add-Member ScriptMethod AddReplyParent {
	param(
		[Parameter(Position=0, Mandatory=$true)] [PsCustomObject] $service,
		[Parameter(Position=1, Mandatory=$true)] [PSObject] $status,
		[Parameter(Position=2, Mandatory=$true)] [System.Collections.Hashtable] $currStatuses
	)
	$replies = @()
	while ($status.ReplyTo -ne -1) {
		$replies += $status
		Write-Debug "Added to replies $($status.ShortInfo)"
		
		# move to parent
		if ($currStatuses.ContainsKey($status.ReplyTo)) {
			$replyTo = $currStatuses[$status.ReplyTo] 
			Write-Debug "Reply to is known: $($replyTo.ShortInfo)"
		} else {
			#$fromFile = $this.StatusFromFile($service, $status.ReplyTo) # potreba otestovat to..
			$fromFile = $null	
			if ($fromFile -ne $null) {
				$replyTo = $fromFile
			} else {
				$downloaded = $this.DownloadStatus($service, $status.ReplyTo)
				if (!$downloaded) { 
					Write-Warning "$($status.ReplyTo) not found"
					$downloaded = $this.ErrorStatus
				}
				$replyTo = $this.CreateStatusInfo($service, $downloaded.status)
			}
			$replyTo.ExtraDownloaded = $true
			Write-Debug "Downloaded parent: $($replyTo.ShortInfo)"
			$currStatuses[$replyTo.StatusId] = $replyTo
			if ($downloaded -ne $null) {
				$this.StatusToFile($service, $replyTo)
			}
		}
		
		# did we found the parent ($foundRoot) earlier ?
		$foundRoot = $null
		if ($replyTo.ReplyParent -ne $null)    { $foundRoot = $replyTo.ReplyParent; Write-Debug "ReplyParent not null: $($replyTo.ReplyParent.ShortInfo)" }
		elseif ($replyTo.Replies.Length -gt 0) { $foundRoot = $replyTo; Write-Debug "ReplyTo has replies: $($replyTo.Replies | %{$_.StatusId})"; }
		if ($foundRoot -ne $null) {
			#path from parent is found, we just bind the replies
			Write-Debug "replies to bind still waiting: $($replies | % {$_.StatusId})"
			#select -unique doesn't work :|
			$replies | ? {$foundRoot.Replies -notcontains $_} | % { $foundRoot.Replies += $_ }
			$foundRoot.Replies = $foundRoot.Replies | Sort Date     #resort again
			$foundRoot.Replies | % { $_.ReplyParent = $foundRoot }
			Write-Debug "Bound to found reply root $($status.ShortInfo)"
			return
		}
		
		$status = $replyTo
		Write-Debug "Move to parent: $($status.ShortInfo)"
	}
	$status.Replies = @($replies | Sort Date)
	$status.Replies | % { $_.ReplyParent = $status }
	Write-Debug "Replies bound to $($status.statusId). Count: $($replies.Length)"
}
# parses date sent by twitter
$twitterApi | Add-Member ScriptMethod ParseDate {
	param([string]$date)
	$r = [regex]'^(?<dayInWeek>\w+)\s(?<month>\w+)\s(?<day>\d+)\s(?<h>\d+):(?<m>\d+):(?<s>\d+)\s\+(\d+)\s(?<year>\d+)$'
	$match  = $r.Match($date);
	if (!$match.Success) { Write-Warning 'Date $date not recognized'; return [datetime]::MinValue }
	$groups = $match.Groups
	$months = @('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')
	$month = 0..11 | ? { $months[$_] -eq $groups['month'].Value } | % { $_+1 }
	[DateTime](New-Object datetime $groups['year'].Value,$month,$groups['day'].Value,$groups['h'].Value,$groups['m'].Value,$groups['s'].Value)
}

#
# Twitter
################################################################################################################################
Import-Module $PsScriptRoot\TwitterOAuth.psm1 -Prefix T
$requestTwitter = {
	param($url) 
	Write-Debug "Requesting twitter url $url"
	$r = Request-TTwitter $url;
	if ($r) { [xml]$r }
	else    { $null }
}
$twitter = New-Object PSObject
$twitter | Add-Member Noteproperty Name 'Twitter'
$twitter | Add-Member Noteproperty FriendsUrl 'http://api.twitter.com/1/statuses/friends_timeline.xml?since_id={0}&count=3200'
$twitter | Add-Member Noteproperty StatusUrl 'http://api.twitter.com/1/statuses/show/{0}.xml'
$twitter | Add-Member NoteProperty DirectMessagesUrl 'http://api.twitter.com/1/statuses/mentions.xml?since_id={0}'
$twitter | Add-Member Noteproperty BrowseStatusUrl 'http://twitter.com/{0}/status/{1}'
$twitter | Add-Member Noteproperty RetweetsUrl 'http://api.twitter.com/1/statuses/retweeted_to_me.xml?since_id={0}'
$twitter | Add-Member Noteproperty IconFile 'twitter.png'
$twitter | Add-Member ScriptMethod CreateStatusInfo $twitterApi.CreateStatusInfo.Script
$twitter | Add-Member Noteproperty ErrorStatus      $twitterApi.ErrorStatus
$twitter | Add-Member ScriptMethod StatusToFile     $twitterApi.StatusToFile.Script
$twitter | Add-Member ScriptMethod StatusFromFile   $twitterApi.StatusFromFile.Script
$twitter | Add-Member ScriptMethod DownloadStatus   {param($service, [long]$statusId)
	Set-TAccessTokenPath $service.OAuthAccessToken
	Write-Debug "Setting oauth token to $($service.OAuthAccessToken)"
	$twitterApi.DownloadStatus($statusId, $requestTwitter, $twitter)
}
$twitter | Add-Member ScriptMethod FetchNewStatuses {param($service) 
	Set-TAccessTokenPath $service.OAuthAccessToken
	Write-Debug "Setting oauth token to $($service.OAuthAccessToken)"
	$twitterApi.FetchNewStatuses($service, $requestTwitter, $twitter)
}
$twitter | Add-Member ScriptMethod ParseDate        $twitterApi.ParseDate.Script
$twitter | Add-Member ScriptMethod AddReplyParent   $twitterApi.AddReplyParent.Script

#
# Identi.ca
################################################################################################################################
Import-Module $PsScriptRoot\IdenticaOAuth.psm1 -Prefix I
$requestIdentica = {
	param($url) 
	Write-Debug "Requesting identi.ca url $url"
	$r = Request-IIdentica $url;
	if ($r) { [xml]$r }
	else    { $null }
}
$identica = New-Object PSObject
$identica | Add-Member NoteProperty Name 'Identica'
$identica | Add-Member NoteProperty FriendsUrl 'http://identi.ca/api/statuses/friends_timeline.xml?since_id={0}&count=3200'
$identica | Add-Member Noteproperty StatusUrl 'http://identi.ca/api/statuses/show/{0}.xml'
$identica | Add-Member Noteproperty BrowseStatusUrl 'http://identi.ca/notice/{1}'
$identica | Add-Member NoteProperty DirectMessagesUrl 'http://identi.ca/api/statuses/replies.xml?since_id={0}'
$identica | Add-Member NoteProperty IconFile 'identica.jpg'
$identica | Add-Member ScriptMethod CreateStatusInfo $twitterApi.CreateStatusInfo.Script
$identica | Add-Member Noteproperty ErrorStatus      $twitterApi.ErrorStatus
$identica | Add-Member ScriptMethod StatusToFile     $twitterApi.StatusToFile.Script
$identica | Add-Member ScriptMethod StatusFromFile   $twitterApi.StatusFromFile.Script
$identica | Add-Member ScriptMethod DownloadStatus   {param($service, [long]$statusId)
	Set-IAccessTokenPath $service.OAuthAccessToken
	Write-Debug "Setting oauth token to $($service.OAuthAccessToken)"
	$twitterApi.DownloadStatus($statusId, $requestIdentica, $identica)
}
$identica | Add-Member ScriptMethod FetchNewStatuses  {param($service) 
	Set-IAccessTokenPath $service.OAuthAccessToken
	Write-Debug "Setting oauth token to $($service.OAuthAccessToken)"
	$twitterApi.FetchNewStatuses($service, $requestIdentica, $identica)
}
$identica | Add-Member ScriptMethod ParseDate        $twitterApi.ParseDate.Script
$identica | Add-Member ScriptMethod AddReplyParent   $twitterApi.AddReplyParent.Script

#
# Microblog
################################################################################################################################

$script:BaseDirectory = $null
$script:StatusesDirectory = $null
$script:SevenZipDirectory = $null
$script:ImageCacheDirectory = $null
$script:Services = $null
$script:LastStatuses = $null
$script:LastStatusesById = $null

function WrapFetchedStatuses {
	$global:mbStatuses = New-Object PSObject -Property @{
			StatusesById = $script:LastStatusesById
			StatusesSorted = $script:LastStatuses 
		} |	Add-Member ScriptMethod GetCount { $this.StatusesSorted.Count } -PassThru
}

function GetServiceByName {
	param([string] $name)
	switch($name) {
		$twitter.Name  { return $twitter }
		$identica.Name { return $identica }
		default        {  throw "Unknown name $name" }
	}
}
function GetService {
	param([string]$appName, [string]$userName)
	$script:Services | ? { $_.App -eq $appName -and $_.User -eq $userName }
}

function NewMbService {
	param(
		[Parameter(Mandatory=$true)] [string]$app,
		[Parameter(Mandatory=$true)][string]$user,
		[Parameter(Mandatory=$true)] [string]$oauthAccessToken,
		[Parameter(Mandatory=$false)] [object]$color='White'
	)
	new-object PSObject -Property @{App = $app
									User = $user
									OAuthAccessToken = $oauthAccessToken
									Color = $color}
}

# creates global variables needed for application to work
function Initialize-MbSession {
	param(
		[Parameter(Mandatory=$true)] [string]$directory,
		[Parameter(Mandatory=$false)]  [string] $7zipDirectory
	)
	
	$script:BaseDirectory = $directory
	$script:StatusesDirectory = (Join-Path $directory 'statuses')
	$script:SevenZipDirectory = $7zipDirectory
	$script:ImageCacheDirectory = (Join-Path $directory 'images')
	$script:Services = @()
	$script:LastStatuses = @()
	$script:LastStatusesById = @{}
	$appinfo = gc (Join-Path $directory twitterReaderKeys.txt)
	Write-Debug "Consumer keys for twitter reader: $appinfo"
	Set-TConsumerInfo @appinfo
	$appinfo = gc (Join-Path $directory identicaReaderKeys.txt)
	Write-Debug "Consumer keys for identi.ca reader: $appinfo"
	Set-IConsumerInfo @appinfo
	
	if (!(Test-Path $script:StatusesDirectory))   { New-Item $script:StatusesDirectory -type directory }
	if (!(Test-Path $script:ImageCacheDirectory)) { New-Item $script:ImageCacheDirectory -type directory }
}

# adds twitter credentials to global credential store
function Add-MbTwitter {
	param(
		[Parameter(Mandatory=$true)][string]$user,
		[Parameter(Mandatory=$true)][string]$oauthAccessToken,
		[Parameter(Mandatory=$false)][object]$color
	)
	$script:Services += @(NewMbService $twitter.Name $user $oauthAccessToken $color)
}

# adds identi.ca credentials to global credential store
function Add-MbIdentica {
	param(
		[Parameter(Mandatory=$true)][string]$user,
		[Parameter(Mandatory=$true)][string]$oauthAccessToken,
		[Parameter(Mandatory=$false)][object]$color
	)
	$script:Services += @(NewMbService $identica.Name $user $oauthAccessToken $color)
}

# backups statuses to 7zip archive
function Backup-MbStatuses {
	$fileName = "Statuses.{0}.zip" -f [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
	Write-Host "Backuping status files to $fileName"
		
	$command = "$(join-path $script:SevenZipDirectory 7z.exe) a $(join-path $script:BaseDirectory $fileName) $(join-path $script:StatusesDirectory *.xml) $(join-path $script:StatusesDirectory lastStatus*)"
	Write-Host "Running command $command"
		
	[void](Invoke-Expression -Command $command)

	Write-Host "Deleting status files"
	dir $script:StatusesDirectory *.xml | ? { $_.Name -match '\d+\.xml' } | Remove-Item
}

# returns new statuses for active services
# if something is passed to $sourceStatuses, new statuses are added to it
function Get-MbStatuses {	
	$sourceStatuses = $global:mbStatuses
	
	Write-Debug "Starting function Get-MbStatuses"
	$statusesByApp = $script:Services | % { 
		$fetcher = GetServiceByName $_.App
		Write-Debug "$_"
		$fetched = $fetcher.FetchNewStatuses($_)
		if ($fetched) { $fetched } else { write-host "Null pro $($_.App)" } #ommit nulls
	}
	Write-Debug "Statuses read"
	$statusesById = if($sourceStatuses.StatusesById -ne $null) { $sourceStatuses.StatusesById } else { @{} }
	Write-Debug "Count of read statuses: $($statusesById.Count)"
	if ($statusesByApp) {
		Write-Debug "merging statuses from all channels"
		$statusesByApp | % { 
			foreach($statusId in $_.Keys) { 
				if ($statusesById.ContainsKey($statusId)) {  Write-Debug "already stored: $statusId"  }
				else { Write-Debug "adding $statusId"; $statusesById[$statusId] = $_[$statusId] }
			}
		}
		Write-Debug "merging done"
	}	
	$script:LastStatusesById = $statusesById
	$script:LastStatuses     = @($statusesById.Values | sort Date) #vzestupne
	WrapFetchedStatuses
}

# adds reply parents to passed statuses
function Add-MbReplyParents {
	Write-Debug "Binding statuses to reply parents"
	$global:mbStatuses.StatusesSorted | % { 
		$status = $_
		if ($status.ReplyTo -eq -1)        { Write-Debug "Skipping $($status.ShortShortInfo) - not reply"; return }
		if ($status.ReplyParent -ne $null) { Write-Debug "Skipping $($status.ShortShortInfo) - already set"; return }
		$service = GetService $status.App $status.Account
		$status.Type.AddReplyParent($service, $status, $global:mbStatuses.StatusesById)
	}
	$script:LastStatusesById = $global:mbStatuses.StatusesById;
	$script:LastStatuses     = @($global:mbStatuses.StatusesById.Values | ? { $_.ReplyTo -eq -1 } | sort Date) #vzestupne
	WrapFetchedStatuses
}

function Create-MbRemoveFilter {
	param([string]$name, [object[]]$itemsToRemove, [bool]$isWhiteList)
	New-Object PSObject -Property @{ Name = $name; IsWhiteList = $isWhiteList; FilterItem = $itemsToRemove }
}

# marks some statuses as hidden
# e.g. Get-MbStatuses | Remove-MbStatuses @(@{'App'='Twitter', 'Account'='leporeloeu', 'User'='webdesigndev'})
# hides statuses by webdesigndev that are fetched from twitter with leporeloeu credentials
# e.g. Get-MbStatuses | Remove-MbStatuses @(@{'User'='webdesigndev'})
# e.g. (the same is Get-MbStatuses | Remove-MbStatuses @('webdesigndev')
#  hides statuses by webdesigndev no matter from what service it is fetched (useful when user webdesigndev is on 
#  twitter and identi.ca and you don't want to display any of them
# e.g. Get-MbStatuses | Remove-MbStatuses @(@{'App'='Identica', 'User'='halr9000'},'NETTUTS','shanselman')
#  removes halr9000 from identica (posts the same at twitter) and nettuts + hanselman (too many personal/rt tweets, sorry scott ;))
# if you don't specify the filter, the default filter is used (see Set/Get-MbDefaultRemoveFilter functions)
function Remove-MbStatuses {
	param(
		[Parameter(Position=0, Mandatory=$false)][object[]]$itemsToRemove,
		[Parameter(Position=1, Mandatory=$false)][bool]$isWhiteList=$false,
		[Parameter(Position=2, Mandatory=$false)][string]$filterName
	)
	Write-Debug "Starting function Remove-MbStatuses"
	if (!$itemsToRemove) { 
		if (!$filterName) { Write-Warning '-name parameter not specified. What filter did you mean?'; return;	}
		$filter = $script:mbRemoveFilters[$filterName]
		$itemsToRemove,$isWhiteList = $filter.FilterItem,$filter.IsWhiteList
		Write-Debug "Using filter '$filterName'"
	}
	$global:mbStatuses.StatusesSorted | 
		% {	$status = $_
			$hide = $false
			if ($status.Matches($itemsToRemove)) {
				# match; filter out if it is black list
				if (!$isWhiteList) { $hide = $true } 	#is black list
			} else {
				# no match; filter out if it is white list
				if ($isWhiteList) { $hide = $true } 	#is black list
			}
			$status.Hidden = $status.Hidden -or $hide		#status may be hidden from previous method call
			$status
		} |
		? { $_.Hidden } | 
		Sort-Object UserName |
		% -begin { write-host "Hidden statuses" } `
		  -process { write-host $_.UserName `  -fore Green -nonew; write-host $_.Text -fore Blue }
}

# default filter for statuses removing. See Remove-MbStatuses for examples
$script:mbRemoveFilters = @{'default'=(Create-MbRemoveFilter 'default' @() $false)}
# sets default filter for removing statuses
function Set-MbRemoveFilter {
	param(
		[Parameter(Position=0, Mandatory=$true)][object[]]$itemsToRemove,
		[Parameter(Position=1, Mandatory=$true)][bool]$isWhiteList,
		[Parameter(Position=2, Mandatory=$false)][string]$name
	)
	if (!$name) { Write-Host "Filter stored under name 'default'"; $name = 'default' }
	$script:mbRemoveFilters[$name] = (Create-MbRemoveFilter $name $itemsToRemove $isWhiteList)
}

# gets default filter for removing statuses
# if called with argument -list only the filters are returned
function Get-MbRemoveFilter {
	param(
		[Parameter(Position=0, Mandatory=$false)][string]$name,
		[Parameter()][switch]$list
	)
	if ($list) { return $script:mbRemoveFilters }
	if (!$script:mbRemoveFilters) { Write-Warning 'something is wrong; filters not accessible'; return }
	if (!$name) { Write-Debug "No name specified, default filter will be returned"; $name = 'default' }
	$script:mbRemoveFilters[$name]
}

function MBBrowse {
	param([string] $url)
	Write-Debug "Running $url"
	[Diagnostics.Process]::Start($url)
}

function Write-MbStatuses {
	param(
		[Parameter(Position=0, Mandatory=$true, ValueFromPipeLine=$true)][PsCustomObject]$sourceStatuses
	)
	$newStatuses = $sourceStatuses.StatusesSorted
	if (!$newStatuses -or $newStatuses.count -eq 0) {
		Write-Host "nothing new" -ForegroundColor Green
		return
	}
	$newStatuses | % {
		$status = $_
		if ($status.Hidden) {
			Write-Debug "status is hidden: $status"
			return
		}
		Write-Host "$($status.App)-$($status.Account)" -ForegroundColor $status.Color -NoNewline
		Write-Host " |" $status.UserName -ForegroundColor Green -NoNewline
		Write-Host " |" $status.Date -ForegroundColor White
		Write-Host $status.Text "`n"
		$status.Replies | % {
			$reply = $_
			Write-Host "   $($reply.App)-$($reply.Account)" -ForegroundColor $reply.Color -NoNewline
			Write-Host " |" $reply.UserName -ForegroundColor Green -NoNewline
			Write-Host " |" $reply.Date -ForegroundColor White
			Write-Host "  " $reply.Text "`n"
		}
	}
}

<#
================================================================================================================
================================================================================================================
#>

add-type -AssemblyName System.Web
try { [Void][GetEmptyDelegate] }
catch {
	Add-Type -TypeDefinition `
		"public class GetEmptyDelegate{public delegate void EmptyDelegateD();public static EmptyDelegateD Get { get { return Nothing; } }public static void Nothing(){}}"
}

#
# Helpers
#
#####################################################################################################################################################
function Refresh([object[]]$obj) {
  $null = $obj | % { $_.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [getemptydelegate]::get); }
}
function SetOpacity { param([float]$opacity, [bool]$store)
	write-debug "Setting opacity, $opacity $store"
	if ($store) { $global:MBPreviewTimerBorder.Tag = $global:MBPreviewTimerBorder.Opacity;  }
	$global:MBPreviewTimerBorder.Opacity = $opacity
}
function RestoreOpacity {
	write-debug "Restoring opacity, $($global:MBPreviewTimerBorder.Tag)"
	try { $global:MBPreviewTimerBorder.Opacity = $global:MBPreviewTimerBorder.Tag } 
	catch {write-host "Default opacity 0.2"; $global:MBPreviewTimerBorder.Opacity = 0.2 }
}
function SetGeneralLabelContent { param([Object]$label, [string]$s) 
	$label.Content = $s
	Refresh $label
}
function SetNextLabelContent { 
	$delay = $global:MBStatusesWindow.Tag["delay"]	
	SetGeneralLabelContent $global:MBPreviewInfo ("Next: " + (Get-Date).AddMinutes($delay).ToString("HH:mm:ss"))
}
function MBSetActivityLabelContent { param([string]$s) 
	SetGeneralLabelContent $global:MBPreviewInfo $s
}
function MbRefreshPreview {
	$global:MBPreviewCurrentImages.Children.Clear()
	$global:mbStatuses.StatusesSorted | % {
		if (!$_) { return }
		Write-Debug "Adding info for status $($_.ShortShortInfo)"
		$path = Get-ImagePath $_ $script:ImageCacheDirectory
		Write-Debug "Adding image at $path"
		$global:MBPreviewCurrentImages.Children.Add(
			(Image -source $path -margin 2 -width 30 -height 30 -tooltip ("{0} {1}`n{2}" -f $_.UserName,$_.Date,$_.Text))
		)
	}
	$sqrt = [int][Math]::Sqrt($global:mbStatuses.GetCount()) + 1 # +1 at je to o neco malo sirsi
	$global:MBPreviewCurrentImages.MaxWidth = [Math]::Min((30+4)*$sqrt, 1024); # 30 je sirka, 4 je mezera
	Refresh $global:MBPreviewCurrentImages
}

function CheckNewStatuses {
	$origBg,$origFg = $global:MBPreviewTimerBorder.BackGround,$global:MBPreviewInfo.Foreground	#second is original foreground of some label
	
	$global:MBPreviewTimerBorder.BackGround = 'Orange'
	$labels = $global:MBPreviewContentPanel.Children | ? { $_ -is [System.Windows.Controls.Label]}
	$labels | % { $_.Foreground  = 'White'; }
	
	Refresh $global:MBPreviewTimerBorder
	Refresh $labels
	
	Get-MbStatuses
	$global:mbStatuses | % { Write-Debug "status: $($_.ShortShortInfo)" }
	Write-Debug "count is $($global:mbStatuses.GetCount())"
	
	SetGeneralLabelContent $global:MBPreviewTreshold ("{0}/{1}" -f $global:mbStatuses.GetCount(),$global:MBStatusesWindow.Tag["treshold"])
	$global:MBPreviewTimerBorder.BackGround = $origBg
	$labels | % { $_.Foreground = $origFg; }
}

function TickHandler {
	Write-Debug "tick"
		
	MBSetActivityLabelContent 'Working...'
	CheckNewStatuses
	SetNextLabelContent
	MbRefreshPreview
	
	$treshold,$count = $global:MBStatusesWindow.Tag["treshold"],$global:mbStatuses.GetCount()
	Write-Debug "treshold: $treshold, count: $count"
	if ($treshold -le $count) {
		Write-debug "Threshold reached, changing background and opacity"
		$global:MBPreviewTimerBorder.Opacity = 1
		$global:MBPreviewTimerBorder.BackGround  = '#dfd'
		$global:MBPreviewTimerBorder.BorderBrush = 'Yellow'
	} 
}

#
# Statuses displaying
################################################################################################################################
#powerboots reguired
#Write-Debug "new statuses, count: $($newStatuses.count)"
function ToHtmlWpf { param([string]$text)
	$parts = $script:RegexUrl.split([system.Web.Httputility]::HtmlDecode($text))

	Write-Debug "Count of split parts: $($parts.Length)"
	textblock {
		$parts | % { 
			if ($script:RegexUrl.IsMatch($_)) {HyperLink -navigateUri $_ $_ -On_RequestNavigate {MBBrowse $this.NavigateUri } }
			else                            {Run -text $_; }
		}
	} -textWrapping wrap
}
function Get-StatusContent {
	param(
		[PSCustomObject]$status, 
		[int]$marginLeft
	)
	border -minheight 50 <#-minwidth 500#> -borderBrush $status.Color `
		-borderThickness 8 -cornerRadius "10,0,0,10" -margin "$marginLeft,0,0,1" -background 'white' {
		StackPanel -minheight 50 `
			-background $(if($status.Hidden){'#666'}else{'white'}) `
			-opacity $(if($status.Hidden){0.5}elseif($status.ExtraDownloaded){0.33}else{1}) {
			StackPanel -orientation horizontal -margin 10 -children $(
				StackPanel -orientation vertical -minwidth 60 -children $(
					Image -source (Get-ImagePath $status $script:ImageCacheDirectory) -width 48 -height 48
				)
				StackPanel -orientation vertical -children $(
					StackPanel -orientation horizontal -children $( 
						textBlock { 
							Run -Text $status.UserName
							Run -Text " | "
							HyperLink -navigateUri ($status.Type.BrowseStatusUrl -f $status.UserName,$status.StatusId) $status.StatusId  `
								-On_RequestNavigate { MBBrowse $this.NavigateUri }
							Run -Text " | "
							Run -Text $status.Date -fontstyle 'italic'
							$(if ($status.ReplyTo -gt 0) { Run -Text " | Reply to $($status.ReplyTo)" })
						}
					)
					ToHtmlWpf $status.Text | % { $_.Fontsize = 14; $_.MaxWidth = (380-$marginLeft); $_ } # 400 uz trochu presahuje, nemam dopocitano
				)
			) | % { 
				$_.Background = imagebrush -imageSource (join-path $script:BaseDirectory $status.Type.IconFile) -Opacity 0.45 -stretch none -alignmentx right; 
				$_ 
			}
		}
	}
	#Write-Host 'id' $status.StatusId 'time' (get-date)
}
	
function Show-Statuses {
	Write-Debug "show-statuses"
	$global:MBPreviewTimerBorder.Visibility    = 'Collapsed'
	$global:MBButtonShowWithParents.Visibility = 'Collapsed'
	$global:MBListStatusesContainer.Visibility = 'Visible'
	$global:MBButtonSwitchToPreview.Visibility = 'Visible'
	$global:MBListStatuses.Children.Clear()
	Write-Debug "children cleared"
	$global:MBtimer.Stop()
	Write-Debug "timer stopped"
	$global:mbStatuses.StatusesSorted | 
		? { $global:MBStatusesWindow.Tag["showHidden"] -or !$_.Hidden} |
		% {
			$status = $_
			Write-Debug "status: $status"
			Write-Debug "status text: $($status.text)"
			$global:MBListStatuses.Children.Add((Get-StatusContent $status 0))
			$status.Replies | % {
				$global:MBListStatuses.Children.Add((Get-StatusContent $_ 20))
			}
		} 
}

Add-Type -assembly System.Windows.Forms
$maxHeight = [Math]::Max([system.windows.forms.screen]::PrimaryScreen.WorkingArea.Size.Height*2/3, 600)
function Show-MbStatuses {
	param(
		[switch]$sync,
		[switch]$showHidden,
		[int]$treshold=10, 
		[int]$delay=10, 
		[string]$filterName='default'
	)
	$global:MBStatusesWindow = Boots {
		StackPanel -orientation vertical{
			#buttons
			StackPanel -orientation horizontal {
				Border -minheight 20 -borderBrush Black -borderThickness 1 -cornerRadius 2 -margin 0 `
					-background 'white' {
					Label -Name 'DragMe' -content 'Drag me'
				}
				Button "Show" -On_Click {  `
					$path = Join-Path $env:TEMP ('stats'+[DateTime]::Now.ToString("yyy-MM-dd-hhmmss")+'.sxm')
					Write-Host "exporting statuses to $path"
					$global:mbStatuses | Export-Clixml $path
					
					Write-Debug "closing"
					###$global:MBPreviewTimerBorder.BackGround = 'Orange'
					
					MBSetActivityLabelContent 'removing statuses...'
					Remove-MbStatuses -filterName $global:MBStatusesWindow.Tag['filter']
					
					MBSetActivityLabelContent 'reply parents...'
					Add-MbReplyParents
		
					Show-Statuses
				} | Tee-Object -Variable 'global:MBButtonShowWithParents'
				Button "Preview" -Visibility 'Collapsed' -On_Click {
					SetupStatusesVariable
					$global:MBPreviewTimerBorder.Visibility    = 'Visible'
					$global:MBButtonShowWithParents.Visibility = 'Visible'
					$global:MBListStatusesContainer.Visibility = 'Collapsed'
					$global:MBButtonSwitchToPreview.Visibility = 'Collapsed'
					 
					$global:MBPreviewTimerBorder.Opacity = 0.2
					$global:MBPreviewTimerBorder.BackGround  = 'white'
					$global:MBPreviewTimerBorder.BorderBrush = 'Green'
	
					TickHandler
					$global:MBtimer.Start()
				} | Tee-Object -Variable 'global:MBButtonSwitchToPreview'
				Button "X" -On_Click { `
					write-host "closing"
					$global:MBStatusesWindow.Close()
				}
			}
			ScrollViewer -maxHeight $maxHeight -VerticalScrollBarVisibility Auto -visibility hidden -maxWidth 500 {
				StackPanel -orientation Vertical -background transparent | % { $global:MBListStatuses=$_; $_ }
			} | % { $global:MBListStatusesContainer=$_; $_ }
			Border -minheight 20 -borderBrush Green -borderThickness 2 -cornerRadius 10 -background 'white' -opacity 0.2 {
				StackPanel -orientation vertical -margin 5 { #{ Label '' -padding 0 -margin 0 }
					WrapPanel <#-maxWidth 600#> | % { $global:MBPreviewCurrentImages = $_; $_ }
					Label "" -FontSize 10 -FontFamily Arial -padding 1 -margin "0,3,0,0" -foreground '#aaa' | % { $global:MBPreviewTreshold = $_; $_ }
					Label "" -FontSize 10 -FontFamily Arial -padding 1 -margin 0 -foreground '#aaa' | % { $global:MBPreviewInfo = $_; $_ }
					
				} | % { $global:MBPreviewContentPanel = $_; $_ }
			} | % { $global:MBPreviewTimerBorder = $_; $_ }
		} `
		-On_PreviewMouseLeftButtonDown {
			if ($_.Source.Name -match 'DragMe') { $_.Handled = $true; $global:MBStatusesWindow.DragMove(); }
		}
	} `
	-async:$(!$sync.IsPresent) `
	-pass -allowsTransparency $true -topmost $true -background transparent `
	-showInTaskbar $true -windowStyle None -title 'PowerShell Microreader' `
	-On_MouseEnter { SetOpacity 1 $true } `
	-On_MouseLeave { RestoreOpacity }  `
	-On_Close {
		if (test-path variable:MBtimer) { $global:MBtimer.Stop() }
		if (test-path variable:MBStatusesWindow) { $global:MBStatusesWindow | Remove-BootsWindow  } } `
	-tag @{'treshold'=$treshold; 'delay'=$delay; 'filter'=$filterName; 'showHidden'=$showHidden} `
	-Left 100 -Top 100
	
	$null = Invoke-BootsWindow $global:MBStatusesWindow {
		$global:MBtimer = new-object System.Windows.Threading.DispatcherTimer
		$global:MBtimer.Interval = [TimeSpan]"0:$($delay):0" ### 
		#$global:MBtimer.Interval = [TimeSpan]"0:0:$($delay)" ### 
		$global:MBtimer.Add_Tick( { TickHandler} )
		#backup old statuses
		SetupStatusesVariable
		TickHandler
		$global:MBtimer.Start()
	}
}
function SetupStatusesVariable
{
	if ($global:mbStatuses -and $global:mbStatuses.GetCount() -gt 0) {
		if (!$global:mbStatsStack) { $global:mbStatsStack = @() }
		$global:mbStatsStack += $global:mbStatuses
	}
	$global:mbStatuses = $null
}

# MBSetActivityLabelContent must be exported because it was not known inside handler of Finish button
#MBSetActivityLabelContent, MBBrowse, Show-MbStatuses, Get-StatusContent
Export-ModuleMember `
  Initialize-MbSession, Import-MbSession, Add-MbTwitter, Add-MbIdentica, Backup-MbStatuses, `
  Get-MbStatuses, Add-MbReplyParents, Remove-MbStatuses, Show-MbStatuses, Write-MbStatuses, `
  Set-MbRemoveFilter, Get-MbRemoveFilter, `
  Check-Microblog, `
  Show-MBStatuses, `
  MBSetActivityLabelContent, Show-Statuses, SetOpacity, RestoreOpacity, SetupStatusesVariable, TickHandler, MBBrowse