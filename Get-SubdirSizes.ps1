param(
  [Parameter(Mandatory=$true)]
  [string]
  $path
)

dir $path -force | 
  ? { $_.PSIsContainer} |
  % { new-object PsObject -property @{
        Length = (dir $_.FullName -recurse -force | ? {! $_.PSIsContainer} | measure-object -sum Length).Sum;
        Name = $_.Name
      }
  } | 
  sort Length -desc | ft Name,@{l="Size in MB"; e={[int]($_.Length/1MB)}} -autosize