function Get-FtpChildItem {
  param(
    [Parameter(Mandatory=$true)]
    [string]
    $sourceuri,
    [Parameter(Mandatory=$true)]
    [string]
    $username,
    [Parameter(Mandatory=$true)]
    [string]
    $password
  )
  $ftprequest = [System.Net.FtpWebRequest]::Create($sourceuri);
  $ftprequest.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails;

  $ftprequest.Credentials = New-Object System.Net.NetworkCredential($username,$password)

  $ftpresponse = $ftprequest.GetResponse();

  $ftpresponseStream = $ftpresponse.GetResponseStream();
  $reader = new-object IO.StreamReader $ftpresponseStream
  
  $reader.ReadToEnd()
  
  Write-Host "Directory List Complete, status " $ftpresponse.StatusDescription

  $reader.Close()
  $ftpresponse.Close()
}

function Upload-FtpFile {
  param(
    [Parameter(Mandatory=$true)]
    [string]
    $sourceuri,
    [Parameter(Mandatory=$true)]
    [string]
    $username,
    [Parameter(Mandatory=$true)]
    [string]
    $password,
    [Parameter(Mandatory=$true)]
    [string]
    $path
  )
  if ($sourceUri -match '\\$|\\\w+$') { throw 'sourceuri should end with a file name' }
  $ftprequest = [System.Net.FtpWebRequest]::Create($sourceuri);
  $ftprequest.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile;
  $ftprequest.UseBinary = $true

  $ftprequest.Credentials = New-Object System.Net.NetworkCredential($username,$password)

  #$sourceStream = new-object IO.StreamReader $path
  #$fileContents = [Text.Encoding]::UTF8.GetBytes($sourceStream.ReadToEnd());
  #$sourceStream.Close();
  $fileContents = Get-Content $path -encoding byte
  $ftprequest.ContentLength = $fileContents.Length;

  $requestStream = $ftprequest.GetRequestStream();
  $requestStream.Write($fileContents, 0, $fileContents.Length);
  $requestStream.Close();

  $response = $ftprequest.GetResponse();

  Write-Host Upload File Complete, status $response.StatusDescription

  $response.Close();
}

function Create-FtpDirectory {
  param(
    [Parameter(Mandatory=$true)]
    [string]
    $sourceuri,
    [Parameter(Mandatory=$true)]
    [string]
    $username,
    [Parameter(Mandatory=$true)]
    [string]
    $password
  )
  if ($sourceUri -match '\\$|\\\w+$') { throw 'sourceuri should end with a file name' }
  $ftprequest = [System.Net.FtpWebRequest]::Create($sourceuri);
  $ftprequest.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
  $ftprequest.UseBinary = $true

  $ftprequest.Credentials = New-Object System.Net.NetworkCredential($username,$password)

  $response = $ftprequest.GetResponse();

  Write-Host Upload File Complete, status $response.StatusDescription

  $response.Close();
}