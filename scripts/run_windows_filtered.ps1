param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArguments
)

$benignFrameTimeLog =
    'Reported frame time is older than the last one; clamping\.'

& flutter run -d windows @FlutterArguments 2>&1 | ForEach-Object {
    $line = $_.ToString()
    if ($line -notmatch $benignFrameTimeLog) {
        $_
    }
}

exit $LASTEXITCODE
