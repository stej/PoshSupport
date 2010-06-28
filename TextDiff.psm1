Add-Type -path "$PsScriptRoot\lib\DiffPlex.dll"

function Assert-Type {
	param(
		[DiffPlex.DiffBuilder.Model.ChangeType]$oldType,
		[DiffPlex.DiffBuilder.Model.ChangeType]$newType
	)
	if ($oldType -eq 'Unchanged' -and $newType -ne 'Unchanged'){ throw "Unchanged vs. $($newType)." }
	if ($oldType -eq 'Deleted'   -and $newType -ne 'Imaginary' -and $newType -ne 'Inserted') { throw "Deleted vs. $($newType)." }
	if ($oldType -eq 'Imaginary' -and $newType -ne 'Inserted') { throw "Imaginary vs. $($newType)." }
	if ($oldType -eq 'Modified'  -and $newType -ne 'Modified') {  throw "Modified vs. $($newType)." 	}
}

function New-DiffItem {
	param(
		[Parameter(Mandatory=$true)][string]$text, 
		[Parameter(Mandatory=$true)][ValidateSet('u','a','d','separator')][string]$type
	)
	New-Object PSObject -Property @{ Text=$text; Type=$type }
}

function Get-DiffItem {
	param(
		[DiffPlex.DiffBuilder.Model.DiffPiece]$oldItem,
		[DiffPlex.DiffBuilder.Model.DiffPiece]$newItem,
		[string]$itemSeparator,
		[int]$index
	)
	Assert-Type $oldItem.Type $newItem.Type
	switch($oldItem.Type) {
		'Unchanged' { New-DiffItem "$($oldItem.Text)$itemSeparator" u }
		'Deleted'   { New-DiffItem "$($oldItem.Text)$itemSeparator" d
					  if ($newItem.Type -eq 'Inserted') { New-DiffItem "$($newItem.Text)$itemSeparator" a }
					}
		'Imaginary' { New-DiffItem "$($newItem.Text)$itemSeparator" a }
		'Modified'  {
			if ($newItem.Type -ne 'Modified') {
				throw "Old line is modified but new line is $($newItem.Type). Index: $index"
			}
			if ($oldItem.SubPieces.Count -le 0) {
				throw "Item modified but there are no subpieces. Old Text: $($oldItem.Text), new text: $($newItem.Text). Index: $index"
			}
			0..($oldItem.SubPieces.Count-1) | 
				% { 
					Write-Debug "Writing subpiece. $_ : '$($oldItem.Text)' vs. '$($newItem.Text)'"
					$oldWord = $oldItem.SubPieces[$_]
					$newWord = $newItem.SubPieces[$_]
					Get-DiffItem $oldWord $newWord -itemSeparator "" $_
				}
			New-DiffItem $itemSeparator separator
		}
		default { throw "Uknown old item type: $($oldItem.Type), new item type: $($newItem.Type). Index: $_" }
	}
}

function Parse-DiffItems {
	param($oldText, $newText)
	$sdiffer = New-Object DiffPlex.DiffBuilder.SideBySideDiffBuilder (New-Object DiffPlex.Differ)
	$sdiff = $sdiffer.BuildDiffModel($oldText, $newText)
	
	if ($sdiff.OldText.Lines.Count -ne $sdiff.NewText.Lines.Count) {
		throw "Count of lines doesn't match: $($sdiff.OldText.Lines.Count) vs. $($sdiff.NewText.Lines.Count)"
	}
	$ret = New-Object Collections.ArrayList
	0..($sdiff.OldText.Lines.Count-1) | 
		% { 
			$oldLine = $sdiff.OldText.Lines[$_]
			$newLine = $sdiff.NewText.Lines[$_]
			Write-Debug "Line $_; '$($oldLine.Text)' vs. '$($newLine.Text)'"
			$ret += @(Get-DiffItem $oldLine $newLine -itemSeparator "`r`n" $_)
		}
	,$ret
}

function Write-Diff {
	[CmdletBinding(DefaultParameterSetName='text')]
	param(
		[Parameter(Mandatory=$true,Position=0,ParameterSetName='text')][string]$oldText,
		[Parameter(Mandatory=$true,Position=1,ParameterSetName='text')][string]$newText,
		[Parameter(Mandatory=$true,Position=0,ParameterSetName='file')][string]$oldPath,
		[Parameter(Mandatory=$true,Position=1,ParameterSetName='file')][string]$newPath,
		[Parameter()][switch]$Silent,
		[Parameter()][switch]$PassThrough
	)
	if ($oldPath) { $oldText = [IO.File]::ReadAllText($oldPath, [Text.Encoding]::Default) }
	if ($newPath) { $newText = [IO.File]::ReadAllText($newPath, [Text.Encoding]::Default) }
	
	$items = Parse-DiffItems $oldText $newText
	
	if ($PassThrough) {
    	[PsObject[]]$items
  	}
	if (!$Silent) {
		$items | % { 
			$r = $_;
			switch($r.Type) {
				'u' { Write-Host $r.Text -NoNewline }
				'd' { Write-Host $r.Text -NoNewline -ForegroundColor Red }
				'a' { Write-Host $r.Text -NoNewline -ForegroundColor Green }
				'separator' { Write-Host $r.Text -NoNewline }
			}
		}
	}
}

function Write-HtmlDiff {
	[CmdletBinding(DefaultParameterSetName='text')]
	param(
		[Parameter(Mandatory=$true,Position=0,ParameterSetName='text')][string]$oldText,
		[Parameter(Mandatory=$true,Position=1,ParameterSetName='text')][string]$newText,
		[Parameter(Mandatory=$true,Position=0,ParameterSetName='file')][string]$oldPath,
		[Parameter(Mandatory=$true,Position=1,ParameterSetName='file')][string]$newPath,
        [Parameter(Mandatory=$false,Position=2)][string]$outputFile,
        [Parameter()][switch]$Show
	)
	if ($oldPath) { $oldText = [IO.File]::ReadAllText($oldPath, [Text.Encoding]::Default) }
	if ($newPath) { $newText = [IO.File]::ReadAllText($newPath, [Text.Encoding]::Default) }
	
	$items = Parse-DiffItems $oldText $newText
	
	$items | 
	% -Begin { $html = "<html>
         <head>
            <style>
                body { font-family: Verdana }
                ins { color: green }
                del { color: red }
            </style>
         </head>
         <body>" } `
	  -Process { 
		$r = $_;
        $text = [system.Web.Httputility]::HtmlEncode($r.Text) -replace "`n", "<br/>"
		switch($r.Type) {
			'u' { $html += $text }
			'd' { $html += "<del>$text</del>" }
			'a' { $html += "<ins>$text</ins>" }
			'separator' { $html += "<br/>" }
		}
	  } `
	  -End { $html += "</body></html>" }
	  
    if ($outputFile) {
        $html | Set-Content $outputFile -Encoding Utf8
        if ($Show) { 
            Invoke-Item $outputFile
        }
    } else {
        $html
    }
}

Export-ModuleMember Write-Diff, Write-HtmlDiff