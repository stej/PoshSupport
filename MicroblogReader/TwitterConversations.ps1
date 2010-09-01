param(
  [long]$statusId
)

Add-Type -Assembly System.ServiceModel.Web,System.Runtime.Serialization

function Convert-JsonToXml([string]$json)
{
  $bytes = [byte[]][char[]]$json
  $quotas = [System.Xml.XmlDictionaryReaderQuotas]::Max
  $jsonReader = [System.Runtime.Serialization.Json.JsonReaderWriterFactory]::CreateJsonReader($bytes,$quotas)
  try
  {
      $xml = new-object System.Xml.XmlDocument
      $xml.Load($jsonReader)
      $xml
  }
  finally
  {
    $jsonReader.Close()
  }
}

function DownloadPage { 
	param([string]$url)
	Write-Debug "Downloading $url"
	(New-Object net.webclient).DownloadString($url)
}

function GetStatus {
	param(
		[long]$id
	)
	if (!$statusesCache) {
		Write-Debug "New statuses cache.."
		$script:statusesCache = @{}
	}
	if ($statusesCache.ContainsKey($id)) {
		Write-Debug "Found in cache: $id"
		return $statusesCache[$id]
	}
	$st = ([xml](DownloadPage http://api.twitter.com/1/statuses/show/$id.xml)).status
	$statusesCache[$id] = $st
	Write-Debug "Count of statuses in cache: $($statusesCache.Count)"
	$st
}
function Search {
	param($name, $sinceId)
	$url = "http://search.twitter.com/search.json?q=%40$name`&since_id=$sinceId&rpp=100&result_type=recent"
	Write-Debug "Getting $url"
	Convert-JsonToXml (DownloadPage $url)
}

function IsReply {
	param($status, $parentId)
	# returns true if the passed status is reply to parent with id $parentId
	$status.in_reply_to_status_id -eq $parentId
}

function NewStatusObject {
	param($status, $parentId)
	New-Object PsObject -Property @{User=$status.user.screen_name; StatusId=$status.id; Text=$status.text; ReplyTo=$id }
}

# get original status
$status = [xml](DownloadPage http://api.twitter.com/1/statuses/show/$statusId.xml)

$result = @(NewStatusObject $status.status 0)
# incrementally add replies
$i = 0
do { 
	$o = $result[$i]
	$name, $id = $o.User, $o.StatusId
	Write-Debug "Processing $i : $name/$id"
	$result += @(Search $name $id | 
		Select-Xml -XPath //results/item |   # if used only % { $_.root.results.item } and there was no element Item, it worked; member info about Item was returned :(
        Select-Object -Exp Node |
		% { GetStatus $_.id.'#text' } |
		? { IsReply $_ $id } |
		% { NewStatusObject $_ $id } |
		% { Write-Debug "$_"; $_ }
	)
	$i++
} while($i -lt $result.Length)

# create structure
$result | 
	Add-Member NoteProperty Children @() -PassThru |
	% { $id = $_.StatusId; $_.Children = @( $result | ? { [long]$_.ReplyTo -eq [long]$id } ) }
	
# write conversation to console
function WriteStatus($status, $depth=0) {
	Write-Host (" "*$depth*3) -NoNewline
	Write-Host $status.User $status.Text
	$status.Children | % { WriteStatus $_ ($depth+1) }
}
WriteStatus $result[0]