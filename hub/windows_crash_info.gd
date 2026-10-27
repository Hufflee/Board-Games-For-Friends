extends RefCounted
## После незавершённого запуска читает Windows Application Error (1000), без прав администратора.
## Отдельный скрытый PowerShell не блокирует игру. Ничего не меняет в реестре и настройках WER.


static func query_script(session: Dictionary, output_path: String) -> String:
	var source := """
$ErrorActionPreference = 'Stop'
$result = @{status='not_found'; note='Windows не записала подходящее событие Application Error.'; events=@()}
try {
	$events = @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; Id=1000; StartTime=$since; EndTime=$until} -MaxEvents 128 -ErrorAction Stop)
	foreach ($event in $events) {
		[xml]$xml = $event.ToXml()
		$data = @{}
		foreach ($field in $xml.Event.EventData.Data) { $data[[string]$field.Name] = [string]$field.'#text' }
		$eventPid = 0L
		$pidText = [string]$data.ProcessId
		if ($pidText.StartsWith('0x')) { $eventPid = [Convert]::ToInt64($pidText.Substring(2),16) }
		elseif ($pidText -match '^\\d+$') { $eventPid = [long]$pidText }
		if ($eventPid -ne $targetPid) { continue }
		if ([string]$data.AppName -ine [IO.Path]::GetFileName($executable)) { continue }
		if ($data.AppPath -and [string]$data.AppPath -ine $executable) { continue }
		if ($data.ProcessCreationTime -match '^0x[0-9a-fA-F]+$') {
			$created = [DateTime]::FromFileTimeUtc([Convert]::ToInt64($data.ProcessCreationTime.Substring(2),16))
			if ([Math]::Abs(($created - $started).TotalSeconds) -gt 5) { continue }
		}
		$result.events += @{
			time_utc=$event.TimeCreated.ToUniversalTime().ToString('o'); record_id=$event.RecordId;
			process_id=$eventPid; application=$data.AppName; module=$data.ModuleName;
			module_path=$data.ModulePath; exception_code=$data.ExceptionCode; offset=$data.FaultingOffset
		}
	}
	if ($result.events.Count -gt 0) { $result.status='found'; $result.note='' }
} catch {
	if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
		$result.status='unavailable'; $result.note=$_.Exception.Message
	}
}
[IO.File]::WriteAllText($output, ($result | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
"""
	var last_seen := int(session.get("last_seen", session.get("started", 0)))
	var prelude := "$since = [DateTimeOffset]::FromUnixTimeSeconds(" + str(maxi(0, last_seen - 120)) + ").LocalDateTime\n"
	prelude += "$until = [DateTimeOffset]::FromUnixTimeSeconds(" + str(int(Time.get_unix_time_from_system())) + ").LocalDateTime\n"
	prelude += "$targetPid = " + str(int(session.get("pid", -1))) + "L\n"
	# _ready наступает после загрузки ресурсов: для PID matching нужен старт движка, а не Diag.
	var process_started := int(session.get("process_started", session.get("started", 0)))
	prelude += "$started = [DateTimeOffset]::FromUnixTimeSeconds(" + str(process_started) + ").UtcDateTime\n"
	prelude += "$executable = '" + str(session.get("executable", "")).replace("'", "''") + "'\n"
	prelude += "$output = '" + output_path.replace("'", "''") + "'\n"
	return prelude + source


static func start(session: Dictionary, output_path: String) -> int:
	if OS.get_name() != "Windows" or int(session.get("pid", -1)) <= 0:
		return -1
	# CreateProcess у Godot не ищет программу в PATH; используем системный Windows PowerShell.
	var powershell := OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	if not FileAccess.file_exists(powershell):
		return -1
	return OS.create_process(powershell, PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", query_script(session, output_path)
	]), false)
