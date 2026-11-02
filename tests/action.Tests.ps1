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
		@{ Name = 'missing-url'; Exit = 1; Message = 'id-token: write' },
		@{ Name = 'missing-request-token'; Exit = 1; Message = 'id-token: write' },
		@{ Name = 'no-auth'; Exit = 1; Message = 'Either personal-access-code or oidc' },
		@{ Name = 'conflicting-auth'; Exit = 1; Message = 'Cannot use both' },
		@{ Name = 'unsupported-tool'; Exit = 1; Message = 'does not support OIDC' },
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
	$env:ACTIONS_ID_TOKEN_REQUEST_TOKEN = 'test-request-token'
	$script:helpCount = 0

	if ($Scenario -in @('pat', 'pat-false', 'conflicting-auth')) { $env:TOKEN = 'test PAT with spaces' }
	if ($Scenario -in @('pat', 'no-auth')) { $env:USE_OIDC = $null }
	if ($Scenario -eq 'pat-false') { $env:USE_OIDC = 'false' }
	if ($Scenario -eq 'oidc-uppercase') { $env:USE_OIDC = 'TRUE' }
	if ($Scenario -eq 'missing-url') { $env:ACTIONS_ID_TOKEN_REQUEST_URL = $null }
	if ($Scenario -eq 'missing-request-token') { $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN = $null }
	$manifest = '{"publisher":"testpublisher","identity":{"internalName":"testextension"}}'
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
	function Get-ChildItem { [pscustomobject]@{ FullName = 'Invoke-TestPublisher' } }
	function Invoke-RestMethod { throw 'Unexpected network request from action' }
	function Invoke-TestPublisher {
		$actual = @($args | ForEach-Object { $_ })
		if ($actual.Count -eq 2 -and $actual[0] -eq 'publish' -and $actual[1] -eq '-help') {
			$script:helpCount++
			if ($Scenario -eq 'unsupported-tool') {
				Write-Output '  -personalAccessToken  The personal access token to use for publishing.'
			} else {
				Write-Output '  -oidc  Use trusted publishing with an OIDC token from the CI provider.'
			}
			$global:LASTEXITCODE = -1
			return
		}
		$isPat = $Scenario -in @('pat', 'pat-false')
		$expected = @('publish', '-payload', $env:VSIX_FILE, '-publishManifest', $env:MANIFEST_FILE)
		if ($isPat) { $expected += '-personalAccessToken', $env:TOKEN } else { $expected += '-oidc' }
		Assert (($actual | ConvertTo-Json -Compress) -ceq ($expected | ConvertTo-Json -Compress)) 'Publisher arguments changed or contain conflicting authentication'
		Assert ($script:helpCount -eq $(if ($isPat) { 0 } else { 1 })) 'Unexpected publisher capability check count'
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