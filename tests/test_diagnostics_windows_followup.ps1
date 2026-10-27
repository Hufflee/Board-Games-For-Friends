## Подставные Event1000: PID, путь и создание процесса при позднем Diag._ready. Без записи в Windows.
param([string]$QueryPath = "$PSScriptRoot/../build/client_switch_audit/medium-windows-query.ps1")
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $QueryPath -Raw -Encoding UTF8
$script:fixtureMode = 'found'
function Get-WinEvent {
	param($FilterHashtable, $MaxEvents, $ErrorAction)
	if ($FilterHashtable.Id -ne 1000 -or $MaxEvents -ne 128) { throw 'Неверный запрос' }
	if ($script:fixtureMode -eq 'denied') { throw [UnauthorizedAccessException]::new('Доступ запрещён') }
	if ($script:fixtureMode -eq 'empty') { return @() }
	$created = [DateTimeOffset]::FromUnixTimeSeconds(1793103866).UtcDateTime.ToFileTimeUtc()
	$rows = @(
		@{ ProcessId='0x4d3'; AppName='PartyWorld.exe'; AppPath='C:\Игры\PartyWorld.exe' },
		@{ ProcessId='1234'; AppName='Other.exe'; AppPath='C:\Игры\PartyWorld.exe' },
		@{ ProcessId='1234'; AppName='PartyWorld.exe'; AppPath='C:\Other\PartyWorld.exe' },
		@{ ProcessId='1234'; AppName='PartyWorld.exe'; AppPath='C:\Игры\PartyWorld.exe'; ProcessCreationTime='0x1' },
		@{ ProcessId='1234'; AppName='PartyWorld.exe'; AppPath='C:\Игры\PartyWorld.exe'; ProcessCreationTime=('0x{0:x}' -f $created) },
		@{ ProcessId='0x4d2'; AppName='PartyWorld.exe'; AppPath='C:\Игры\PartyWorld.exe'; ProcessCreationTime=('0x{0:x}' -f $created) }
	)
	foreach ($row in $rows) {
		$fields = ''
		foreach ($key in $row.Keys) { $fields += '<Data Name="' + $key + '">' + [Security.SecurityElement]::Escape($row[$key]) + '</Data>' }
		$event = [pscustomobject]@{
			TimeCreated=Get-Date; RecordId=321
			XmlText='<Event><EventData>' + $fields + '<Data Name="ModuleName">fixture.dll</Data><Data Name="ExceptionCode">c0000005</Data></EventData></Event>'
		}
		$event | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.XmlText }
		$event
	}
}
$checks = 0
foreach ($mode in @('found', 'empty', 'denied')) {
	$script:fixtureMode = $mode
	& ([scriptblock]::Create($source))
	$resultPath = "$PSScriptRoot/../build/client_switch_audit/windows-followup-result.json"
	$result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
	if ($mode -eq 'found') {
		if ($result.status -ne 'found' -or $result.events.Count -ne 2) { throw 'Потеряно событие позднего _ready или перепутан PID/путь' }
		if ($result.events[0].module -ne 'fixture.dll' -or $result.events[0].exception_code -ne 'c0000005') { throw 'Потерян код или модуль' }
	} elseif ($mode -eq 'empty' -and $result.status -ne 'not_found') { throw 'Неверный пустой результат' }
	elseif ($mode -eq 'denied' -and $result.status -ne 'unavailable') { throw 'Неверный отказ доступа' }
	$checks += 1
}
Write-Output "WINDOWS FOLLOWUP: сценариев=$checks ошибок=0"
