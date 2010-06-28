Import-Module "$PsScriptRoot\Formatting.psm1"

function download($url) {
	Write-Debug "Downloading $url"
	$webRequest = New-Object Net.WebClient
	$webRequest.Headers.Add("User-Agent", 'Mozilla/5.0 (Windows; U; Windows NT 6.0; cs; rv:1.9.1.5) Gecko/20091102 Firefox/3.5.5 (.NET CLR 3.5.30729) from Posh')
	$webRequest.Headers.Add("Accept", 'text/html,application/xhtml+xml,application/xml;')
	$webRequest.Headers.Add("Accept-Language", 'cs')
	$webRequest.Headers.Add("Accept-Encoding", 'deflate')
	$webRequest.Headers.Add("Accept-Charset", 'windows-1250') #utf-8
	$webRequest.Encoding = [system.text.encoding]::UTF8
	$str = $webRequest.DownloadString($url)
	$str
}
function convert2xml($s) {
	$s = $s.Replace(' xmlns="http://www.w3.org/1999/xhtml"', '')
	Add-Type -path "$PsScriptRoot\lib\SgmlReaderDll.dll"
	
	$sr = new-object io.stringreader $s
	
	$sgmlReader = new-object Sgml.SgmlReader
	$sgmlReader.DocType = 'HTML';
	$sgmlReader.WhitespaceHandling = 'All';
	$sgmlReader.CaseFolding = 'ToLower';
	$sgmlReader.InputStream = $sr;
	
	$xml = new-object Xml.XmlDocument;
	$xml.PreserveWhitespace = $true;
	$xml.XmlResolver = $null;
	$xml.Load($sgmlReader);
	
	$sgmlReader.Close()
	$sr.Close()
	
	$xml
}

function parse($xml, $word) {
	$nodes = Select-Xml -Xml $xml -XPath '//div[@id="vocables_main"]/div[@class="pair"]'
	$res = @($nodes | 
		? { $_.Node.span[0].InnerText -eq $word } |
		% { $_.Node.span[1].InnerText })
	$res += @($nodes | 
		? { ($_.Node.span[0].InnerText -ne $word) -and $_.Node.span[0].InnerText.StartsWith($word) } |
		% { "[{0}] {1}" -f $($_.Node.span[0].InnerText), $_.Node.span[1].InnerText })
	$res
}

function run($url, $word) {
	$res = @(parse (convert2xml (download $url)) $word)
	if ($res.Count -lt 20) { $res | Format-Columns -autosize -maxcol 4 }
	else                   { $res | Format-Columns -autosize }
}

function Translate-ToEnglish {
	run "http`://slovnik.cz/bin/mld.fpl?vcb=$($args -join '+')&dictdir=encz.cz&lines=50" ($args -join ' ')
}

function Translate-ToCzech {
	run "http://slovnik.cz/bin/mld.fpl?vcb=$($args -join '+')&dictdir=encz.en&lines=50" ($args -join ' ')
}

Export-ModuleMember Translate-ToCzech, Translate-ToEnglish