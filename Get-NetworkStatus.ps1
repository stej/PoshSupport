$t = [Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}")
$networkListManager = [Activator]::CreateInstance($t)
$connections = $networkListManager.GetNetworkConnections() 
function getconnectivity {
	param($network)
	switch ($network.GetConnectivity()) {
		 0x0000  { 'disconnected' }
		{ $_ -band 0x0001 } { 'IPV4_NOTRAFFIC' }
		{ $_ -band 0x0002 } { 'IPV6_NOTRAFFIC' }
		{ $_ -band 0x0010 } { 'IPV4_SUBNET' }
		{ $_ -band 0x0020 } { 'IPV4_LOCALNETWORK' }
		{ $_ -band 0x0040 } { 'IPV4_INTERNET' }
		{ $_ -band 0x0100 } { 'IPV6_SUBNET' }
		{ $_ -band 0x0200 } { 'IPV6_LOCALNETWORK' }
		{ $_ -band 0x0400 } { 'IPV6_INTERNET' }
	}
}
$connections | 
	% { 
		$n = $_.GetNetwork(); 
		$name = $n.GetName();
		$category = switch($n.GetCategory()) { 0 { 'public' } 1 { 'private' } 2 { 'domain' } }
		$connectivity = getConnectivity $n
		new-object PsObject -property @{Name=$name; Category=$category; Connectivity=$connectivity } 
	}