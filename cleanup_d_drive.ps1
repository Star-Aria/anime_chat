$ErrorActionPreference = 'Stop'

$expectedTargets = @(
    'D:\Office 2024',
    'D:\Adobe Audition 2024 v24.0.0.46.iso',
    'D:\AndroidTemp'
)

Write-Host 'D 盘安全清理工具' -ForegroundColor Cyan
Write-Host '只会处理以下三个已核实目标：'
$expectedTargets | ForEach-Object { Write-Host "  $_" }
Write-Host ''

$answer = Read-Host '输入 YES 开始清理'
if ($answer -cne 'YES') {
    Write-Host '已取消，没有删除任何文件。' -ForegroundColor Yellow
    Read-Host '按 Enter 退出'
    exit 0
}

$freeBefore = (Get-PSDrive -Name D).Free

foreach ($target in $expectedTargets) {
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host "已跳过（不存在）：$target" -ForegroundColor DarkGray
        continue
    }

    $resolvedPath = (Resolve-Path -LiteralPath $target).Path
    if ($resolvedPath -cne $target) {
        throw "安全校验失败：$target 实际指向 $resolvedPath"
    }

    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Host "已删除：$target" -ForegroundColor Green
}

$freeAfter = (Get-PSDrive -Name D).Free
$freedGB = [math]::Round(($freeAfter - $freeBefore) / 1GB, 2)
$freeGB = [math]::Round($freeAfter / 1GB, 2)

Write-Host ''
Write-Host "完成：本次释放 $freedGB GB，D 盘当前剩余 $freeGB GB。" -ForegroundColor Cyan
Read-Host '按 Enter 退出'
