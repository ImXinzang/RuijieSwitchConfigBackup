# 基本配置
$Username = ""
$LoginPassword = ""
$EnablePassword = ""
$PlinkPath = "C:\Users\Administrator\Desktop\nettools\plink.exe"

# 交换机IP列表文件路径（每行一个IP）
$SwitchListFile = "C:\Users\Administrator\Desktop\nettools\AM IP list1.txt"

# 备份文件保存目录
$BackupDir = "C:\Users\Administrator\Desktop\nettools\AM config backup"
$TempDir = "$BackupDir\Temp"
$CurrentTime = Get-Date -Format 'yyyyMMdd_HHmmss'
$ZipFile = "$BackupDir\SwitchConfigs_$CurrentTime.zip"



# 创建备份目录
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Host "创建备份目录: $BackupDir" -ForegroundColor Green
}

if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    Write-Host "创建临时目录: $TempDir" -ForegroundColor Green
}

# 读取交换机IP列表
if (-not (Test-Path $SwitchListFile)) {
    Write-Host "错误：交换机IP列表文件不存在！" -ForegroundColor Red
    Write-Host "请创建文件: $SwitchListFile，每行一个IP地址" -ForegroundColor Yellow
    exit
}

$SwitchIPs = Get-Content $SwitchListFile | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }

if ($SwitchIPs.Count -eq 0) {
    Write-Host "错误：未找到有效的IP地址！" -ForegroundColor Red
    Write-Host "请在 $SwitchListFile 中添加有效的IP地址，每行一个" -ForegroundColor Yellow
    exit
}

Write-Host "找到 $($SwitchIPs.Count) 台交换机需要备份" -ForegroundColor Green
Write-Host "开始时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "-" * 50

# 备份命令（锐捷交换机）
$Commands = @(
    "terminal length 0",
    "show running-config"
)

# 记录备份结果
$BackupResults = @()
$SuccessCount = 0
$FailedCount = 0

# 遍历所有交换机
foreach ($DeviceIP in $SwitchIPs) {
    Write-Host "正在备份交换机: $DeviceIP" -ForegroundColor Cyan
    
    # 方法1：先手动连接一次以接受密钥（需要交互）
    # 使用一种更可靠的方法：创建一个临时脚本文件来交互式接受密钥
    Write-Host "  处理SSH主机密钥..." -ForegroundColor Gray
    
    # 创建接受密钥的脚本
    $AcceptKeyScript = [IO.Path]::GetTempFileName()
    @"
echo y
"@ | Out-File $AcceptKeyScript -Encoding ASCII
    
    # 尝试接受密钥
    $keyResult = & cmd /c "`"$PlinkPath`" -ssh -l $Username -pw $LoginPassword $DeviceIP exit < `"$AcceptKeyScript`" 2>&1"
    
    # 如果还是失败，使用-hostkey参数绕过检查
    if ($keyResult -match "FATAL ERROR" -or $keyResult -match "Connection abandoned") {
        Write-Host "  使用-hostkey绕过主机密钥检查..." -ForegroundColor Gray
        
        # 创建临时文件
        $InputFile = [IO.Path]::GetTempFileName()
        $OutputFile = [IO.Path]::GetTempFileName()
        
        # 构建命令序列
        $commandSequence = "enable`n$EnablePassword"
        foreach ($cmd in $Commands) {
            $commandSequence += "`n$cmd"
        }
        $commandSequence += "`nexit`nexit"
        
        $commandSequence | Out-File $InputFile -Encoding ASCII
        
        # 执行PLink，使用-hostkey参数接受任意密钥（安全风险低，因为是内网设备）
        # 注意：这里使用 "*" 接受任何主机密钥，仅限受信任的内部网络使用
        $process = Start-Process -FilePath $PlinkPath `
            -ArgumentList "-ssh -hostkey * -l $Username -pw $LoginPassword $DeviceIP" `
            -RedirectStandardInput $InputFile `
            -RedirectStandardOutput $OutputFile `
            -RedirectStandardError "$OutputFile.err" `
            -NoNewWindow -Wait -PassThru
    } else {
        # 密钥已接受，正常连接
        # 创建临时文件
        $InputFile = [IO.Path]::GetTempFileName()
        $OutputFile = [IO.Path]::GetTempFileName()
        
        # 构建命令序列
        $commandSequence = "enable`n$EnablePassword"
        foreach ($cmd in $Commands) {
            $commandSequence += "`n$cmd"
        }
        $commandSequence += "`nexit`nexit"
        
        $commandSequence | Out-File $InputFile -Encoding ASCII
        
        # 执行PLink
        $process = Start-Process -FilePath $PlinkPath `
            -ArgumentList "-ssh -l $Username -pw $LoginPassword $DeviceIP" `
            -RedirectStandardInput $InputFile `
            -RedirectStandardOutput $OutputFile `
            -RedirectStandardError "$OutputFile.err" `
            -NoNewWindow -Wait -PassThru
    }
    
    # 清理临时脚本
    Remove-Item $AcceptKeyScript -Force -ErrorAction SilentlyContinue
    
    # 读取输出
    $rawOutput = Get-Content $OutputFile -Raw
    $errorOutput = Get-Content "$OutputFile.err" -Raw 2>$null
    
    # 检查是否成功
    $isSuccess = $process.ExitCode -eq 0 -and ($rawOutput -match "Current configuration" -or $rawOutput -match "Building configuration")
    
    if ($isSuccess) {
        # 提取配置内容（跳过命令和提示符）
        $lines = $rawOutput -split "`r?`n"
        $configLines = @()
        
        # 寻找配置开始位置（通常是"Current configuration"之后）
        $foundStart = $false
        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()
            
            # 跳过交互行和命令回显
            if ($trimmedLine -eq "" -or 
                $trimmedLine -eq "enable" -or 
                $trimmedLine -eq "terminal length 0" -or
                $trimmedLine -eq $EnablePassword -or
                $trimmedLine -eq "exit" -or
                $trimmedLine -match "^Password:$" -or
                $trimmedLine -match "^\S+[#>]\s*$") {
                continue
            }
            
            if ($trimmedLine -match "^Current configuration") {
                $foundStart = $true
            }
            
            if ($foundStart -or $trimmedLine -match "^Building configuration") {
                $configLines += $trimmedLine
            }
        }
        
        # 如果没有找到标准开头，但仍有内容，则保存所有非交互行
        if ($configLines.Count -eq 0) {
            foreach ($line in $lines) {
                $trimmedLine = $line.Trim()
                if ($trimmedLine -ne "" -and
                    $trimmedLine -ne "enable" -and
                    $trimmedLine -ne "terminal length 0" -and
                    $trimmedLine -ne $EnablePassword -and
                    $trimmedLine -ne "exit" -and
                    $trimmedLine -notmatch "^Password:$" -and
                    $trimmedLine -notmatch "^\S+[#>]\s*$") {
                    $configLines += $trimmedLine
                }
            }
        }
        
        # 保存配置文件
        $BackupFileName = "Switch_${DeviceIP}_$CurrentTime.txt"
        $BackupFilePath = "$TempDir\$BackupFileName"
        
        if ($configLines.Count -gt 0) {
            $configLines -join "`r`n" | Out-File $BackupFilePath -Encoding UTF8
            Write-Host "  ? 备份成功: $BackupFileName" -ForegroundColor Green
            $BackupResults += "? $DeviceIP : 备份成功 ($BackupFileName)"
            $SuccessCount++
        } else {
            Write-Host "  ? 备份失败: 未提取到配置内容" -ForegroundColor Yellow
            $BackupResults += "? $DeviceIP : 备份失败 (无配置内容)"
            $FailedCount++
        }
    } else {
        Write-Host "  ? 备份失败: 连接失败或命令执行错误" -ForegroundColor Red
        
        # 显示具体错误
        if ($errorOutput -and $errorOutput.Trim()) {
            $errorMsg = $errorOutput.Trim()
            Write-Host "    错误信息: $errorMsg" -ForegroundColor Red
            $BackupResults += "? $DeviceIP : 备份失败 ($errorMsg)"
        } elseif ($rawOutput -and $rawOutput.Trim()) {
            # 尝试从输出中提取错误信息
            $errorLines = @()
            foreach ($line in ($rawOutput -split "`r?`n")) {
                $trimmedLine = $line.Trim()
                if ($trimmedLine -match "error" -or $trimmedLine -match "fail" -or $trimmedLine -match "拒绝" -or $trimmedLine -match "invalid") {
                    $errorLines += $trimmedLine
                }
            }
            if ($errorLines.Count -gt 0) {
                $errorMsg = $errorLines[0]
                Write-Host "    错误信息: $errorMsg" -ForegroundColor Red
                $BackupResults += "? $DeviceIP : 备份失败 ($errorMsg)"
            } else {
                Write-Host "    未知错误" -ForegroundColor Red
                $BackupResults += "? $DeviceIP : 备份失败 (未知错误)"
            }
        } else {
            Write-Host "    未知错误" -ForegroundColor Red
            $BackupResults += "? $DeviceIP : 备份失败 (未知错误)"
        }
        
        $FailedCount++
    }
    
    # 清理临时文件
    Remove-Item $InputFile, $OutputFile, "$OutputFile.err" -Force -ErrorAction SilentlyContinue
}

# 压缩备份文件
Write-Host "`n正在压缩备份文件..." -ForegroundColor Cyan

# 检查是否有备份文件
$BackupFiles = Get-ChildItem $TempDir -Filter "*.txt" -File
if ($BackupFiles.Count -eq 0) {
    Write-Host "没有备份文件可压缩！" -ForegroundColor Red
} else {
    # 使用Compress-Archive压缩文件
    try {
        $BackupFilesCount = $BackupFiles.Count
        $ZipFileName = Split-Path $ZipFile -Leaf
        
        Compress-Archive -Path "$TempDir\*" -DestinationPath $ZipFile -CompressionLevel Optimal -Force
        Write-Host "? 压缩完成: $ZipFileName" -ForegroundColor Green
        Write-Host "  包含 $BackupFilesCount 个配置文件，大小: $([math]::Round((Get-Item $ZipFile).Length/1KB, 2)) KB" -ForegroundColor Gray
        
        # 清理临时文件
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  临时文件已清理" -ForegroundColor Gray
    } catch {
        Write-Host "? 压缩失败: $_" -ForegroundColor Red
    }
}

# 生成备份报告
$ReportTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ReportContent = @"
锐捷交换机批量配置备份报告
======================================
备份时间: $ReportTime
备份总数: $($SwitchIPs.Count) 台
成功备份: $SuccessCount 台
备份失败: $FailedCount 台
压缩文件: $(Split-Path $ZipFile -Leaf)
备份目录: $BackupDir

详细结果:
$($BackupResults -join "`r`n")

注意：对于新设备，SSH主机密钥已自动接受。
操作完成！
======================================
"@

# 显示报告
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "备份完成报告" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host $ReportContent -ForegroundColor White

# 保存报告到文件
$ReportFile = "$BackupDir\BackupReport_$CurrentTime.txt"
$ReportContent | Out-File $ReportFile -Encoding UTF8
Write-Host "备份报告已保存到: $ReportFile" -ForegroundColor Green

# 显示备份文件位置
if (Test-Path $ZipFile) {
    Write-Host "配置备份文件: $ZipFile" -ForegroundColor Green
    Write-Host "文件大小: $([math]::Round((Get-Item $ZipFile).Length/1KB, 2)) KB" -ForegroundColor Gray
}

Write-Host "`n脚本执行完成！" -ForegroundColor Green
Write-Host "备份目录: $BackupDir" -ForegroundColor Yellow
Write-Host "下次运行时，SSH主机密钥已缓存，不会再提示确认" -ForegroundColor Cyan