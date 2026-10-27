## Проверяет разбор Windows Event 1000 на подставных событиях, не изменяя системный журнал.
## После test_diagnostics.gd: powershell -File tests/test_windows_crash_info.ps1
param([string]$QueryPath = "$PSScriptRoot/../build/crash_logging_tests/windows-query.ps1")
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $QueryPath -Raw -Encoding UTF8
$taskOutput = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $QueryPath)) 'windows-fixture-result.json'
$source = $source -replace "(?m)^\`$output = .*", (('$output = ''{0}''' -f $taskOutput.Replace("'", "''")))
$script:fixtureMode = 'found'
function Get-WinEvent {
	param($FilterHashtable, $MaxEvents, $ErrorAction)
	if ($FilterHashtable.Id -ne 1000 -or $FilterHashtable.ProviderName -ne 'Application Error') { throw 'Неверный фильтр событий' }
	if ($script:fixtureMode -eq 'denied') { throw [UnauthorizedAccessException]::new('Доступ запрещён') }
	if ($script:fixtureMode -eq 'empty') { return @() }
	$rows = @(
		@{ ProcessId='0x4d3'; AppName='PartyWorld.exe'; AppPath="C:\Игры\Друг'а\PartyWorld.exe" },
		@{ ProcessId='0x4d2'; AppName='Other.exe'; AppPath='C:\Other.exe' },
		@{ ProcessId='0x4d2'; AppName='PartyWorld.exe'; AppPath='C:\Other\PartyWorld.exe' },
		@{ ProcessId='0x4d2'; AppName='PartyWorld.exe'; AppPath="C:\Игры\Друг'а\PartyWorld.exe"; ProcessCreationTime='0x1' },
		@{ ProcessId='0x4d2'; AppName='PartyWorld.exe'; AppPath="C:\Игры\Друг'а\PartyWorld.exe" },
		@{ ProcessId='1234'; AppName='PartyWorld.exe'; AppPath="C:\Игры\Друг'а\PartyWorld.exe" }
	)
	foreach ($row in $rows) {
		$fields = ''
		foreach ($key in $row.Keys) { $fields += '<Data Name="' + $key + '">' + [Security.SecurityElement]::Escape($row[$key]) + '</Data>' }
		$event = [pscustomobject]@{
			TimeCreated = Get-Date; RecordId = 321
			XmlText = '<Event><EventData>' + $fields + '<Data Name="ModuleName">gpu.dll</Data><Data Name="ExceptionCode">c0000005</Data></EventData></Event>'
		}
		$event | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.XmlText }
		$event
	}
}
foreach ($mode in @('found', 'empty', 'denied')) {
	$script:fixtureMode = $mode
	& ([scriptblock]::Create($source))
	$result = Get-Content -LiteralPath $taskOutput -Raw -Encoding UTF8 | ConvertFrom-Json
	if ($mode -eq 'found') {
		if ($result.status -ne 'found' -or $result.events.Count -ne 2) { throw 'Перепутаны события разных процессов или путей' }
		if ($result.events[0].module -ne 'gpu.dll' -or $result.events[0].exception_code -ne 'c0000005') { throw 'Потеряны модуль и код исключения' }
	} elseif ($mode -eq 'empty' -and $result.status -ne 'not_found') { throw 'Неверная обработка отсутствия события' }
	elseif ($mode -eq 'denied' -and $result.status -ne 'unavailable') { throw 'Неверная обработка отказа доступа' }
	Write-Output "ПРОВЕРКА Windows: $mode — OK"
}
