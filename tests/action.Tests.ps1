param([string]$Scenario)

$ErrorActionPreference = 'Stop'

function Assert($Condition, [string]$Message) {
	if (-not $Condition) { throw $Message }
}

if (-not $Scenario) {
	$cases = @(
		@{ Name = 'pat'; Exit = 0; Message = 'TEST_SUCCESS' },
		@{ Name = 'pat-false'; Exit = 0; Message = 'TEST_SUCCESS' },
		@{ Name = 'oidc'; Exit = 0; Message = 'TEST_SUCCESS' },
		@{ Name = 'oidc-uppercase'; Exit = 0; Message = 'TEST_SUCCESS' },
		@{ Name = 'oidc-existing-query'; Exit = 0; Message = 'TEST_SUCCESS' },
		@{ Name = 'oidc-existing-audience'; Exit = 0; Message = 'TEST_SUCCESS' },
		@{ Name = 'existing-redirect'; Exit = 0; Message = 'TEST_SUCCESS' },
		@{ Name = 'missing-redirect'; Exit = 0; Message = 'TEST_SUCCESS' },
		@{ Name = 'no-msal'; Exit = 0; Message = 'TEST_SUCCESS' },
		@{ Name = 'invalid-msal'; Exit = 1; Message = 'GetAssemblyName' },
		@{ Name = 'missing-config'; Exit = 1; Message = 'because it does not exist' },
		@{ Name = 'missing-url'; Exit = 1; Message = 'id-token: write' },
		@{ Name = 'missing-request-token'; Exit = 1; Message = 'id-token: write' },
		@{ Name = 'no-auth'; Exit = 1; Message = 'Either personal-access-code or oidc' },
		@{ Name = 'conflicting-auth'; Exit = 1; Message = 'Cannot use both' },
		@{ Name = 'oidc-request-failure'; Exit = 1; Message = 'Failed to request a GitHub OIDC token' },
		@{ Name = 'oidc-missing-token'; Exit = 1; Message = 'returned no valid token' },
		@{ Name = 'oidc-invalid-token'; Exit = 1; Message = 'returned no valid token' },
		@{ Name = 'exchange-failure'; Exit = 1; Message = 'Marketplace OIDC token exchange failed' },
		@{ Name = 'exchange-missing-credential'; Exit = 1; Message = 'returned no valid credential' },
		@{ Name = 'exchange-invalid-credential'; Exit = 1; Message = 'returned no valid credential' },
		@{ Name = 'missing-publisher'; Exit = 1; Message = 'requires a publisher identifier' },
		@{ Name = 'invalid-publisher'; Exit = 1; Message = 'requires a publisher identifier' },
		@{ Name = 'malformed-manifest'; Exit = 1; Message = 'Could not parse publishManifest.json' },
		@{ Name = 'missing-vsix'; Exit = 1; Message = 'extension-file not found' },
		@{ Name = 'missing-manifest'; Exit = 1; Message = 'publish-manifest-file not found' },
		@{ Name = 'publisher-failure'; Exit = 17; Message = 'exited with code 17' }
	)
	foreach ($case in $cases) {
		$output = (& (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $PSCommandPath -Scenario $case.Name 2>&1) -join "`n"
		$exitCode = $LASTEXITCODE
		Assert ($exitCode -eq $case.Exit) "$($case.Name): expected exit $($case.Exit), got ${exitCode}: $output"
		Assert ($output.Contains($case.Message)) "$($case.Name): expected message '$($case.Message)': $output"
		if ($case.Exit -eq 1) {
			Assert (-not $output.Contains('TEST_PUBLISHER_CALLED')) "$($case.Name): publishing ran after authentication failed"
		}
		if ($case.Name -in @('pat', 'pat-false')) {
			Assert ($output.Contains('::add-mask::test PAT with spaces')) 'PAT was not masked'
		} elseif ($case.Exit -eq 0 -or $case.Name -eq 'publisher-failure') {
			Assert ($output.IndexOf('::add-mask::test-oidc-token') -lt $output.IndexOf('TEST_PUBLISHER_CALLED') -and $output.Contains('::add-mask::test-oidc-token')) 'OIDC token was not masked before publishing'
			Assert ($output.IndexOf('::add-mask::test-marketplace-credential') -lt $output.IndexOf('TEST_PUBLISHER_CALLED') -and $output.Contains('::add-mask::test-marketplace-credential')) 'Marketplace credential was not masked before publishing'
		}
		Write-Host "PASS: $($case.Name)"
	}
	Write-Host "All $($cases.Count) action regression tests passed."
	exit 0
}

$actionPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'action.yml'
$yaml = Get-Content -LiteralPath $actionPath -Raw
$scriptText = ($yaml -split '      run: \|\r?\n', 2)[1] -replace '(?m)^        ', ''
$parseTokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$parseTokens, [ref]$parseErrors)
Assert ($parseErrors.Count -eq 0) "Action script has syntax errors: $parseErrors"

$fixture = Join-Path ([System.IO.Path]::GetTempPath()) "publish-marketplace-test-$([guid]::NewGuid())"
$null = New-Item -ItemType Directory -Path $fixture
try {
	$env:RUNNER_TEMP = $fixture
	$env:VSIX_FILE = Join-Path $fixture 'extension with spaces.vsix'
	$env:MANIFEST_FILE = Join-Path $fixture 'publish manifest.json'
	$env:GITHUB_STEP_SUMMARY = Join-Path $fixture 'summary.md'
	$env:TOKEN = $null
	$env:USE_OIDC = 'true'
	$env:ACTIONS_ID_TOKEN_REQUEST_URL = 'https://oidc.example.test/token'
	if ($Scenario -eq 'oidc-existing-query') { $env:ACTIONS_ID_TOKEN_REQUEST_URL += '?request=123' }
	if ($Scenario -eq 'oidc-existing-audience') { $env:ACTIONS_ID_TOKEN_REQUEST_URL += '?request=123&audience=other' }
	$env:ACTIONS_ID_TOKEN_REQUEST_TOKEN = 'test-request-token'
	$global:requestCount = 0
	$publisherPath = Join-Path $fixture 'publisher with spaces.ps1'
	[System.IO.File]::WriteAllText($publisherPath, 'Invoke-TestPublisher @args')
	$lib = Join-Path $fixture 'lib'
	$null = New-Item -ItemType Directory -Path $lib
	$msalPath = Join-Path $lib 'Microsoft.Identity.Client.dll'
	Add-Type -TypeDefinition '[assembly: System.Reflection.AssemblyVersion("4.87.0.0")] public class TestMsal { }' -OutputAssembly $msalPath
	$configPath = "$publisherPath.config"
	$msalDependency = switch ($Scenario) {
		'existing-redirect' { '<dependentAssembly><assemblyIdentity name="Microsoft.Identity.Client" publicKeyToken="0a613f4dd989e8ae" culture="neutral"/><bindingRedirect oldVersion="0.0.0.0-4.85.2.0" newVersion="4.85.2.0"/></dependentAssembly>' }
		'missing-redirect' { '<dependentAssembly><assemblyIdentity name="Microsoft.Identity.Client" publicKeyToken="0a613f4dd989e8ae" culture="neutral"/></dependentAssembly>' }
		default { '' }
	}
	[System.IO.File]::WriteAllText($configPath, "<configuration><runtime><assemblyBinding xmlns='urn:schemas-microsoft-com:asm.v1'><probing privatePath='lib\vsixpublisher;lib'/><dependentAssembly><assemblyIdentity name='System.Memory'/><bindingRedirect oldVersion='0.0.0.0-4.0.5.0' newVersion='4.0.5.0'/></dependentAssembly></assemblyBinding><assemblyBinding xmlns='urn:schemas-microsoft-com:asm.v1'>$msalDependency</assemblyBinding></runtime><startup><supportedRuntime version='v4.0'/></startup></configuration>")
	if ($Scenario -eq 'no-msal') { Remove-Item -LiteralPath $msalPath }
	if ($Scenario -eq 'invalid-msal') { [System.IO.File]::WriteAllText($msalPath, 'not an assembly') }
	if ($Scenario -eq 'missing-config') { Remove-Item -LiteralPath $configPath }

	if ($Scenario -in @('pat', 'pat-false', 'conflicting-auth')) { $env:TOKEN = 'test PAT with spaces' }
	if ($Scenario -in @('pat', 'no-auth')) { $env:USE_OIDC = $null }
	if ($Scenario -eq 'pat-false') { $env:USE_OIDC = 'false' }
	if ($Scenario -eq 'oidc-uppercase') { $env:USE_OIDC = 'TRUE' }
	if ($Scenario -eq 'missing-url') { $env:ACTIONS_ID_TOKEN_REQUEST_URL = $null }
	if ($Scenario -eq 'missing-request-token') { $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN = $null }
	$manifest = '{"publisher":"testpublisher","identity":{"internalName":"testextension"}}'
	if ($Scenario -eq 'missing-publisher') { $manifest = '{"identity":{"internalName":"testextension"}}' }
	if ($Scenario -eq 'invalid-publisher') { $manifest = '{"publisher":123}' }
	if ($Scenario -eq 'malformed-manifest') { $manifest = 'not JSON' }
	[System.IO.File]::WriteAllText($env:MANIFEST_FILE, $manifest)
	$archive = [System.IO.Compression.ZipFile]::Open($env:VSIX_FILE, [System.IO.Compression.ZipArchiveMode]::Create)
	try {
		$entry = $archive.CreateEntry('extension.vsixmanifest')
		$writer = [System.IO.StreamWriter]::new($entry.Open())
		try {
			$writer.Write('<PackageManifest><Metadata><Identity Id="testextension" Version="1.2.3"/><DisplayName>Test Extension</DisplayName></Metadata></PackageManifest>')
		} finally { $writer.Dispose() }
	} finally { $archive.Dispose() }
	if ($Scenario -eq 'missing-vsix') { Remove-Item -LiteralPath $env:VSIX_FILE }
	if ($Scenario -eq 'missing-manifest') { Remove-Item -LiteralPath $env:MANIFEST_FILE }

	function Invoke-WebRequest { }
	function Expand-Archive { }
	function Get-ChildItem { [pscustomobject]@{ FullName = $publisherPath } }
	function Invoke-RestMethod {
		param($Method, $Uri, $Headers, $ContentType, $Body)
		$global:requestCount++
		if ($global:requestCount -eq 1) {
			Assert ($Method -eq 'Get') 'Expected GitHub token request first'
			$expectedUri = if ($Scenario -in @('oidc-existing-query', 'oidc-existing-audience')) { 'https://oidc.example.test/token?request=123&audience=marketplace.visualstudio.com' } else { 'https://oidc.example.test/token?audience=marketplace.visualstudio.com' }
			Assert ($Uri -ceq $expectedUri) 'OIDC audience or existing query parameters changed'
			Assert ($Headers.Authorization -ceq 'Bearer test-request-token' -and $Headers.Accept -eq 'application/json') 'Invalid GitHub token request headers'
			if ($Scenario -eq 'oidc-request-failure') { throw 'Simulated GitHub HTTP failure' }
			if ($Scenario -eq 'oidc-missing-token') { return @{} }
			if ($Scenario -eq 'oidc-invalid-token') { return @{ value = 123 } }
			return @{ value = 'test-oidc-token' }
		}
		Assert ($global:requestCount -eq 2) 'Unexpected repeated token exchange'
		Assert ($Method -eq 'Post' -and $Uri -ceq 'https://marketplace.visualstudio.com/_apis/gallery/token?api-version=7.2-preview.1') 'Marketplace exchange must specify the API version'
		Assert ($Headers.Authorization -ceq 'FederatedToken test-oidc-token' -and $Headers.Accept -eq 'application/json') 'Invalid Marketplace authentication headers'
		Assert ($Headers['X-Market-CI-Provider'] -eq 'github-actions' -and $ContentType -eq 'application/json') 'Invalid Marketplace request metadata'
		Assert ($Body -ceq '{"publisherName":"testpublisher"}') 'Marketplace exchange publisher does not match manifest'
		if ($Scenario -eq 'exchange-failure') { throw 'Simulated Marketplace HTTP failure' }
		if ($Scenario -eq 'exchange-missing-credential') { return @{} }
		if ($Scenario -eq 'exchange-invalid-credential') { return @{ credential = ' ' } }
		return @{ credential = 'test-marketplace-credential' }
	}
	function Invoke-TestPublisher {
		$config = [xml](Get-Content -LiteralPath $configPath -Raw)
		$namespaces = [System.Xml.XmlNamespaceManager]::new($config.NameTable)
		$namespaces.AddNamespace('asm', 'urn:schemas-microsoft-com:asm.v1')
		$redirects = $config.SelectNodes("/configuration/runtime/asm:assemblyBinding/asm:dependentAssembly[asm:assemblyIdentity/@name='Microsoft.Identity.Client']/asm:bindingRedirect", $namespaces)
		if ($Scenario -eq 'no-msal') {
			Assert ($redirects.Count -eq 0) 'Added a redirect without a bundled MSAL assembly'
		} else {
			Assert ($redirects.Count -eq 1) 'Expected exactly one MSAL binding redirect before invoking the publisher'
			Assert ($redirects[0].oldVersion -eq '0.0.0.0-4.87.0.0') 'MSAL redirect does not cover the referenced version'
			Assert ($redirects[0].newVersion -eq '4.87.0.0') 'MSAL redirect does not match the bundled assembly version'
			$identity = $redirects[0].ParentNode.assemblyIdentity
			Assert ($identity.publicKeyToken -eq '0a613f4dd989e8ae' -and $identity.culture -eq 'neutral') 'MSAL assembly identity changed'
		}
		Assert ($config.configuration.runtime.assemblyBinding[0].probing.privatePath -eq 'lib\vsixpublisher;lib') 'Publisher probing paths changed'
		Assert ($config.configuration.runtime.assemblyBinding[0].dependentAssembly.bindingRedirect.newVersion -eq '4.0.5.0') 'Unrelated binding redirect changed'
		Assert ($config.configuration.startup.supportedRuntime.version -eq 'v4.0') 'Publisher startup configuration changed'
		$actual = @($args | ForEach-Object { $_ })
		$isPat = $Scenario -in @('pat', 'pat-false')
		$expected = @('publish', '-payload', $env:VSIX_FILE, '-publishManifest', $env:MANIFEST_FILE)
		$expected += '-personalAccessToken', $(if ($isPat) { $env:TOKEN } else { 'test-marketplace-credential' })
		Assert (($actual | ConvertTo-Json -Compress) -ceq ($expected | ConvertTo-Json -Compress)) 'Publisher arguments changed or contain conflicting authentication'
		Assert ($global:requestCount -eq $(if ($isPat) { 0 } else { 2 })) 'PAT made network requests or OIDC did not exchange exactly once'
		Write-Host 'TEST_PUBLISHER_CALLED'
		$global:LASTEXITCODE = if ($Scenario -eq 'publisher-failure') { 17 } else { 0 }
	}

	& ([scriptblock]::Create($scriptText))
	$summary = Get-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Raw
	Assert ($summary.Contains('**Test Extension** 1.2.3')) 'Published extension heading changed'
	Assert ($summary.Contains('https://marketplace.visualstudio.com/items?itemName=testpublisher.testextension')) 'Marketplace summary link changed'
	Write-Host 'TEST_SUCCESS'
} finally {
	Remove-Item -LiteralPath $fixture -Recurse -Force
}