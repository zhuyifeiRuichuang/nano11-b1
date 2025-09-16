<#
脚本功能：Windows 11 精简镜像构建工具（优化版）
核心优化点：
1. 自动读取脚本目录ISO文件，支持编号选择
2. 日志定向到「build_日期时间_随机数.log」，终端仅显进度
3. 基于build_remove.conf配置文件管理删除规则（支持通配符）
4. 全流程进度条展示，关键步骤错误捕获
#>

# ============================== 核心函数定义 ==============================
# 1. INI配置文件读取函数（支持section、key-value、注释过滤）
function Get-IniContent {
    param([string]$Path)
    $ini = @{}
    $section = "default"
    $ini[$section] = @{}
    
    Get-Content -Path $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        # 忽略注释（;开头）和空行
        if ($line -match '^;.*' -or [string]::IsNullOrEmpty($line)) { return }
        # 匹配section（[sectionName]）
        if ($line -match '^\[(.*)\]$') {
            $section = $matches[1].Trim()
            $ini[$section] = @{}
            return
        }
        # 匹配key=value
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $ini[$section][$key] = $value
            return
        }
    }
    return $ini
}

# 2. 日志写入函数（带时间戳，仅错误/警告显终端）
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    # 写入日志文件
    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
    # 终端仅显示错误/警告
    if ($Level -eq "ERROR") {
        Write-Host "`n【错误】$Message`n" -ForegroundColor Red
    } elseif ($Level -eq "WARNING") {
        Write-Host "【警告】$Message" -ForegroundColor Yellow
    }
}

# 3. 进度条更新函数（终端+日志双记录）
function Update-Progress {
    param(
        [Parameter(Mandatory=$true)][string]$Activity,
        [Parameter(Mandatory=$true)][string]$Status,
        [Parameter(Mandatory=$true)][int]$Percent
    )
    # 终端进度条（PowerShell原生控件）
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $Percent
    # 每10%更新一次终端文本提示（避免频繁刷新）
    if ($Percent % 10 -eq 0 -or $Percent -eq 100) {
        Write-Host "[$Activity] $Status - $Percent%"
    }
    # 日志记录进度
    Write-Log "[$Activity] $Status - $Percent%"
}

# ============================== 初始化检查 ==============================
# 1. 执行策略检查（仅首次运行提示）
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Host "`n当前PowerShell执行策略为Restricted，无法运行脚本，是否改为RemoteSigned？(yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false | Out-Null
        Write-Host "执行策略已修改，脚本将重启..."
        Start-Sleep 2
        # 管理员权限重启脚本
        $adminProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
        $adminProcess.Arguments = $myInvocation.MyCommand.Definition
        $adminProcess.Verb = "runas"
        [System.Diagnostics.Process]::Start($adminProcess) | Out-Null
        exit
    } else {
        Write-Host "未修改执行策略，脚本退出..."
        exit
    }
}

# 2. 管理员权限检查
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
$currentPrincipal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole($adminRole)) {
    Write-Host "`n脚本需要管理员权限，正在重启..."
    $adminProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $adminProcess.Arguments = $myInvocation.MyCommand.Definition
    $adminProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($adminProcess) | Out-Null
    exit
}

# 3. 日志文件初始化（build_yyyyMMdd_HHmmss_随机数.log）
$logFileName = "build_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(Get-Random -Maximum 10000).log"
$logPath = Join-Path -Path $PSScriptRoot -ChildPath $logFileName
try {
    New-Item -Path $logPath -ItemType File -Force | Out-Null
    Write-Host "`n日志文件已创建：$logFileName`n"
    Write-Log "=== 脚本启动，初始化完成 ==="
} catch {
    Write-Host "`n错误：创建日志文件失败，原因：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 4. 欢迎信息与确认
Write-Host "=== Welcome to nano11 Builder (Optimized) ==="
Write-Host "功能：生成精简Windows 11镜像（仅用于测试/开发，不支持后续更新）"
Write-Host "注意：所有详细操作日志已定向到日志文件，终端仅显示进度`n"
$confirm = Read-Host "是否继续？(y/n)"
if ($confirm -ne 'y') {
    Write-Log "用户选择取消，脚本退出"
    Write-Host "`n脚本退出..."
    exit 0
}
Write-Log "用户确认继续，开始执行镜像构建流程"

# ============================== 步骤1：ISO文件选择与挂载 ==============================
Update-Progress -Activity "ISO文件处理" -Status "扫描脚本目录ISO文件" -Percent 0

# 扫描脚本目录下的ISO文件
$isoFiles = Get-ChildItem -Path $PSScriptRoot -Filter *.iso -File
if (-not $isoFiles) {
    Write-Log "未在脚本目录（$PSScriptRoot）找到ISO文件" -Level ERROR
    Write-Host "`n请将Windows 11 ISO文件放在脚本目录后重试！"
    exit 1
}

# 列出ISO文件供用户选择
Write-Host "`n找到以下ISO文件："
for ($i = 0; $i -lt $isoFiles.Count; $i++) {
    Write-Host "$($i+1). $($isoFiles[$i].Name) （大小：$([math]::Round($isoFiles[$i].Length/1GB,2))GB）"
}

# 验证用户输入
do {
    $selectedInput = Read-Host "`n请输入要操作的ISO编号（1-$($isoFiles.Count)）"
    $isValid = [int]::TryParse($selectedInput, [ref]$selectedIndex) -and $selectedIndex -ge 1 -and $selectedIndex -le $isoFiles.Count
    if (-not $isValid) {
        Write-Host "输入无效，请输入1-$($isoFiles.Count)之间的数字"
    }
} while (-not $isValid)

$selectedIso = $isoFiles[$selectedIndex - 1]
Update-Progress -Activity "ISO文件处理" -Status "选择的ISO：$($selectedIso.Name)" -Percent 30

# 自动挂载ISO并获取驱动器号
try {
    Write-Host "`n正在挂载ISO文件...（约10秒）"
    $mountResult = Mount-DiskImage -ImagePath $selectedIso.FullName -PassThru -ErrorAction Stop
    $volume = $mountResult | Get-Volume
    $DriveLetter = "$($volume.DriveLetter):"
    # 验证挂载是否成功（存在sources目录）
    if (-not (Test-Path "$DriveLetter\sources")) {
        throw "ISO挂载后未找到sources目录，可能不是Windows镜像"
    }
    Update-Progress -Activity "ISO文件处理" -Status "ISO挂载成功，驱动器号：$DriveLetter" -Percent 100
    Write-Log "ISO挂载信息：文件=$($selectedIso.FullName)，驱动器号=$DriveLetter"
} catch {
    Write-Log "ISO挂载失败，原因：$($_.Exception.Message)" -Level ERROR
    # 清理：卸载可能的残留挂载
    if ($mountResult) { Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue }
    exit 1
}

# ============================== 步骤2：读取删除配置文件 ==============================
Update-Progress -Activity "配置文件处理" -Status "检查build_remove.conf" -Percent 0

$configPath = Join-Path -Path $PSScriptRoot -ChildPath "build_remove.conf"
# 检查配置文件是否存在，不存在则生成默认配置
if (-not (Test-Path $configPath -PathType Leaf)) {
    Write-Log "未找到配置文件，生成默认build_remove.conf" -Level WARNING
    $defaultConfig = @"
; nano11 镜像删除配置文件
; 格式：[分类] -> key=remove（key支持通配符*，value=remove表示删除）

[languages]
; 要删除的语言包（示例：zh-cn*=删除所有中文包，ja-jp*=删除日语包）
zh-cn*=remove
ja-jp*=remove
ko-kr*=remove

[languages-ime]
; 要删除的输入法（示例：*IME-zh-cn*=删除中文输入法）
*IME-zh-cn*=remove
*IME-ja-jp*=remove
*IME-ko-kr*=remove

[service]
; 要删除的系统服务（服务名参考：services.msc）
Spooler=remove          ; 打印后台处理服务
PrintNotify=remove      ; 打印通知服务
Fax=remove              ; 传真服务
RemoteRegistry=remove   ; 远程注册表服务
diagsvc=remove          ; 诊断服务
WerSvc=remove           ; 错误报告服务
MapsBroker=remove       ; 地图服务
wuauserv=remove         ; Windows更新服务

[driver]
; 要删除的驱动（驱动目录名通配符，参考：C:\Windows\System32\DriverStore\FileRepository）
prn*=remove             ; 打印机驱动
scan*=remove            ; 扫描仪驱动
mfd*=remove             ; 多功能设备驱动
wscsmd.inf*=remove      ; 智能卡驱动
tapdrv*=remove          ; 磁带驱动
"@
    $defaultConfig | Out-File -Path $configPath -Encoding UTF8 -Force
    Write-Host "`n已生成默认配置文件：build_remove.conf"
    Write-Host "请根据需求修改配置文件后重新运行脚本！`n"
    # 清理：卸载ISO
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 0
}

# 读取并解析配置文件
try {
    $iniConfig = Get-IniContent -Path $configPath
    # 提取各分类的删除规则（仅保留value=remove的key）
    $delLanguages = if ($iniConfig.ContainsKey('languages')) {
        $iniConfig['languages'] | Where-Object { $_.Value -eq 'remove' } | Select-Object -ExpandProperty Key
    } else { @() }
    
    $delLanguagesIme = if ($iniConfig.ContainsKey('languages-ime')) {
        $iniConfig['languages-ime'] | Where-Object { $_.Value -eq 'remove' } | Select-Object -ExpandProperty Key
    } else { @() }
    
    $delServices = if ($iniConfig.ContainsKey('service')) {
        $iniConfig['service'] | Where-Object { $_.Value -eq 'remove' } | Select-Object -ExpandProperty Key
    } else { @() }
    
    $delDrivers = if ($iniConfig.ContainsKey('driver')) {
        $iniConfig['driver'] | Where-Object { $_.Value -eq 'remove' } | Select-Object -ExpandProperty Key
    } else { @() }

    Update-Progress -Activity "配置文件处理" -Status "解析完成，加载删除规则" -Percent 100
    Write-Log "配置文件解析结果："
    Write-Log "  [languages] 删除规则：$($delLanguages -join ', ')"
    Write-Log "  [languages-ime] 删除规则：$($delLanguagesIme -join ', ')"
    Write-Log "  [service] 删除规则：$($delServices -join ', ')"
    Write-Log "  [driver] 删除规则：$($delDrivers -join ', ')"
} catch {
    Write-Log "解析配置文件失败，原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# ============================== 步骤3：镜像复制与预处理 ==============================
$mainOSDrive = $env:SystemDrive  # 系统盘（如C:）
$workDir = "$mainOSDrive\nano11" # 工作目录
$scratchDir = "$mainOSDrive\scratchdir" # WIM挂载目录

Update-Progress -Activity "镜像预处理" -Status "创建工作目录" -Percent 0

# 创建工作目录
try {
    New-Item -ItemType Directory -Path "$workDir\sources" -Force | Out-Null
    New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
    Update-Progress -Activity "镜像预处理" -Status "工作目录创建完成" -Percent 20
} catch {
    Write-Log "创建工作目录失败，原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# 检查并转换ESD为WIM（如果需要）
if (-not (Test-Path "$DriveLetter\sources\install.wim") -and (Test-Path "$DriveLetter\sources\install.esd")) {
    Update-Progress -Activity "镜像预处理" -Status "发现ESD文件，开始转换为WIM" -Percent 30
    Write-Host "`n发现install.esd，需转换为install.wim（约5-10分钟）..."
    
    # 获取ESD镜像索引
    Write-Log "获取ESD镜像索引信息：$DriveLetter\sources\install.esd"
    $esdInfo = & dism /English "/Get-WimInfo" "/wimfile:$DriveLetter\sources\install.esd" 2>&1
    $esdInfo | ForEach-Object { Write-Log "DISM输出：$_" }
    
    # 让用户选择索引（通常1=家庭版，2=专业版）
    $index = Read-Host "`n请输入要转换的镜像索引（如2=专业版）"
    if (-not [int]::TryParse($index, [ref]$indexNum)) {
        Write-Log "镜像索引输入无效，退出转换" -Level ERROR
        Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
        exit 1
    }
    
    # 转换ESD到WIM
    try {
        Update-Progress -Activity "镜像预处理" -Status "转换ESD->WIM（索引$indexNum）" -Percent 50
        & dism /Export-Image `
            /SourceImageFile:"$DriveLetter\sources\install.esd" `
            /SourceIndex:$indexNum `
            /DestinationImageFile:"$workDir\sources\install.wim" `
            /Compress:max /CheckIntegrity 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
        
        if (-not (Test-Path "$workDir\sources\install.wim")) { throw "转换后未找到install.wim" }
        Update-Progress -Activity "镜像预处理" -Status "ESD转换WIM完成" -Percent 80
    } catch {
        Write-Log "ESD转换失败，原因：$($_.Exception.Message)" -Level ERROR
        Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
        exit 1
    }
} elseif (-not (Test-Path "$DriveLetter\sources\install.wim") -and -not (Test-Path "$DriveLetter\sources\install.esd")) {
    Write-Log "ISO中未找到install.wim/install.esd，不是Windows镜像" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# 复制ISO文件到工作目录
Update-Progress -Activity "镜像预处理" -Status "复制ISO文件到工作目录" -Percent 80
Write-Host "`n正在复制ISO文件到工作目录（约5-15分钟）..."
try {
    # 粗略计算进度（按文件数）
    $sourceFiles = Get-ChildItem -Path $DriveLetter\* -Recurse -File -ErrorAction SilentlyContinue
    $totalFiles = $sourceFiles.Count
    $currentFile = 0

    Get-ChildItem -Path $DriveLetter\* -Recurse -File -ErrorAction Stop | ForEach-Object {
        $currentFile++
        $percent = [math]::Round(($currentFile / $totalFiles) * 20 + 80, 0) # 80-100%进度段
        $destPath = $_.FullName.Replace($DriveLetter, $workDir)
        $destDir = Split-Path $destPath -Parent
        
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -Path $_.FullName -Destination $destPath -Force | Out-Null
        
        # 每200个文件更新一次终端进度
        if ($currentFile % 200 -eq 0 -or $currentFile -eq $totalFiles) {
            Update-Progress -Activity "镜像预处理" -Status "已复制：$currentFile/$totalFiles 个文件" -Percent $percent
        }
    }
    # 删除残留ESD（如果存在）
    Remove-Item -Path "$workDir\sources\install.esd" -Force -ErrorAction SilentlyContinue
    Write-Log "ISO文件复制完成，工作目录：$workDir"
} catch {
    Write-Log "复制ISO文件失败，原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# ============================== 步骤4：挂载WIM并精简 ==============================
$wimPath = "$workDir\sources\install.wim"
Update-Progress -Activity "WIM处理" -Status "获取WIM镜像信息" -Percent 0

# 获取WIM镜像索引
try {
    Write-Log "获取WIM镜像信息：$wimPath"
    $wimInfo = & dism /English "/Get-WimInfo" "/wimfile:$wimPath" 2>&1
    $wimInfo | ForEach-Object { Write-Log "DISM输出：$_" }
    
    # 让用户选择要精简的索引
    $index = Read-Host "`n请输入要精简的WIM镜像索引（如2=专业版）"
    if (-not [int]::TryParse($index, [ref]$indexNum)) {
        throw "索引输入无效，必须是数字"
    }
    Update-Progress -Activity "WIM处理" -Status "选择索引：$indexNum" -Percent 20
} catch {
    Write-Log "获取WIM索引失败，原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# 挂载WIM
try {
    Write-Host "`n正在挂载WIM镜像（约3-5分钟）..."
    # 获取管理员组（用于权限设置）
    $adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount]).Value
    
    # 设置WIM文件权限
    & takeown "/F" $wimPath 2>&1 | ForEach-Object { Write-Log "takeown输出：$_" }
    & icacls $wimPath "/grant" "$adminGroup:(F)" 2>&1 | ForEach-Object { Write-Log "icacls输出：$_" }
    Set-ItemProperty -Path $wimPath -Name IsReadOnly -Value $false -ErrorAction Stop
    
    # 挂载WIM
    Update-Progress -Activity "WIM处理" -Status "开始挂载WIM" -Percent 30
    & dism /English "/mount-image" `
        "/imagefile:$wimPath" `
        "/index:$indexNum" `
        "/mountdir:$scratchDir" 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
    
    if (-not (Test-Path "$scratchDir\Windows")) { throw "WIM挂载后未找到Windows目录，挂载失败" }
    Update-Progress -Activity "WIM处理" -Status "WIM挂载成功，挂载目录：$scratchDir" -Percent 50
} catch {
    Write-Log "挂载WIM失败，原因：$($_.Exception.Message)" -Level ERROR
    # 清理：卸载可能的残留挂载
    & dism /English "/unmount-image" "/mountdir:$scratchDir" "/discard" 2>&1 | Out-Null
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# ------------------------------ 4.1：删除预装应用（AppX） ------------------------------
Update-Progress -Activity "镜像精简" -Status "删除预装应用（AppX）" -Percent 0
try {
    $appxPackages = Get-AppxProvisionedPackage -Path $scratchDir -ErrorAction Stop
    $totalApps = $appxPackages.Count
    $currentApp = 0
    
    foreach ($app in $appxPackages) {
        $currentApp++
        $percent = [math]::Round(($currentApp / $totalApps) * 20, 0) # 0-20%进度段
        # 匹配常见预装应用（可通过配置文件扩展，此处保留默认规则）
        $appName = $app.PackageName
        if ($appName -match 'Zune|Gaming|Teams|YourPhone|Solitaire|FeedbackHub|Maps|OfficeHub|Alarms|Copilot|Photos|Camera') {
            Remove-AppxProvisionedPackage -Path $scratchDir -PackageName $appName -ErrorAction SilentlyContinue
            Write-Log "删除预装应用：$($app.DisplayName)（包名：$appName）"
        }
        # 每10个应用更新一次进度
        if ($currentApp % 10 -eq 0 -or $currentApp -eq $totalApps) {
            Update-Progress -Activity "镜像精简" -Status "已处理：$currentApp/$totalApps 个应用" -Percent $percent
        }
    }
    Update-Progress -Activity "镜像精简" -Status "预装应用删除完成" -Percent 20
} catch {
    Write-Log "删除预装应用失败，原因：$($_.Exception.Message)" -Level WARNING
}

# ------------------------------ 4.2：删除系统组件（基于配置文件） ------------------------------
Update-Progress -Activity "镜像精简" -Status "删除系统组件（语言/输入法）" -Percent 20
try {
    # 获取所有系统组件
    $allPackages = & dism /image:$scratchDir /Get-Packages /Format:Table 2>&1 | Where-Object { $_ -match '^Microsoft' }
    $totalPkgs = $allPackages.Count
    $currentPkg = 0
    $deletePatterns = @()
    
    # 加载配置文件中的删除规则
    if ($delLanguages) {
        $deletePatterns += foreach ($lang in $delLanguages) { "Microsoft-Windows-LanguageFeatures-*-${lang}-Package~" }
    }
    if ($delLanguagesIme) {
        $deletePatterns += $delLanguagesIme
    }
    # 固定删除规则（保留原脚本核心精简逻辑）
    $deletePatterns += @(
        "Microsoft-Windows-InternetExplorer-Optional-Package~",
        "Microsoft-Windows-MediaPlayer-Package~",
        "Windows-Defender-Client-Package~",
        "Microsoft-Windows-BitLocker-DriveEncryption-FVE-Package~"
    )
    
    # 执行组件删除
    foreach ($pattern in $deletePatterns) {
        $pkgsToDelete = $allPackages | Where-Object { $_ -like "$pattern*" }
        foreach ($pkg in $pkgsToDelete) {
            $currentPkg++
            $percent = [math]::Round(20 + ($currentPkg / $totalPkgs) * 30, 0) # 20-50%进度段
            $pkgName = ($pkg -split "\s+")[0]
            & dism /image:$scratchDir /Remove-Package /PackageName:$pkgName /English 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
            Write-Log "删除系统组件：$pkgName（匹配规则：$pattern）"
            
            if ($currentPkg % 5 -eq 0 -or $currentPkg -eq $totalPkgs) {
                Update-Progress -Activity "镜像精简" -Status "已删除：$currentPkg 个组件" -Percent $percent
            }
        }
    }
    Update-Progress -Activity "镜像精简" -Status "系统组件删除完成" -Percent 50
} catch {
    Write-Log "删除系统组件失败，原因：$($_.Exception.Message)" -Level WARNING
}

# ------------------------------ 4.3：删除驱动（基于配置文件） ------------------------------
if ($delDrivers) {
    Update-Progress -Activity "镜像精简" -Status "删除驱动（基于配置）" -Percent 50
    try {
        $driverRepo = "$scratchDir\Windows\System32\DriverStore\FileRepository"
        $totalDrivers = (Get-ChildItem -Path $driverRepo -Directory -ErrorAction SilentlyContinue).Count
        $currentDriver = 0
        
        Get-ChildItem -Path $driverRepo -Directory -ErrorAction Stop | ForEach-Object {
            $currentDriver++
            $driverDir = $_.Name
            $percent = [math]::Round(50 + ($currentDriver / $totalDrivers) * 20, 0) # 50-70%进度段
            
            # 匹配配置文件中的驱动删除规则
            foreach ($pattern in $delDrivers) {
                if ($driverDir -like "$pattern*") {
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "删除驱动目录：$driverDir（匹配规则：$pattern）"
                    break
                }
            }
            
            if ($currentDriver % 20 -eq 0 -or $currentDriver -eq $totalDrivers) {
                Update-Progress -Activity "镜像精简" -Status "已处理：$currentDriver/$totalDrivers 个驱动目录" -Percent $percent
            }
        }
        Update-Progress -Activity "镜像精简" -Status "驱动删除完成" -Percent 70
    } catch {
        Write-Log "删除驱动失败，原因：$($_.Exception.Message)" -Level WARNING
    }
} else {
    Update-Progress -Activity "镜像精简" -Status "未配置驱动删除规则，跳过" -Percent 70
    Write-Log "未配置驱动删除规则，跳过驱动删除步骤"
}

# ------------------------------ 4.4：删除服务（基于配置文件） ------------------------------
if ($delServices) {
    Update-Progress -Activity "镜像精简" -Status "删除系统服务（基于配置）" -Percent 70
    try {
        # 加载系统注册表（服务配置存储在SYSTEM hive）
        reg load HKLM\zSYSTEM "$scratchDir\Windows\System32\config\SYSTEM" 2>&1 | ForEach-Object { Write-Log "REG输出：$_" }
        $totalServices = $delServices.Count
        $currentService = 0
        
        foreach ($service in $delServices) {
            $currentService++
            $percent = [math]::Round(70 + ($currentService / $totalServices) * 20, 0) # 70-90%进度段
            $servicePath = "HKLM\zSYSTEM\ControlSet001\Services\$service"
            
            if (Test-Path "Registry::$servicePath") {
                reg delete "$servicePath" /f 2>&1 | ForEach-Object { Write-Log "REG输出：$_" }
                Write-Log "删除系统服务：$service（注册表路径：$servicePath）"
            } else {
                Write-Log "服务 $service 不存在，跳过删除" -Level WARNING
            }
            
            Update-Progress -Activity "镜像精简" -Status "已处理：$currentService/$totalServices 个服务" -Percent $percent
        }
        
        # 卸载注册表
        reg unload HKLM\zSYSTEM 2>&1 | ForEach-Object { Write-Log "REG输出：$_" }
        Update-Progress -Activity "镜像精简" -Status "服务删除完成" -Percent 90
    } catch {
        Write-Log "删除系统服务失败，原因：$($_.Exception.Message)" -Level WARNING
        reg unload HKLM\zSYSTEM 2>&1 | Out-Null # 强制卸载注册表
    }
} else {
    Update-Progress -Activity "镜像精简" -Status "未配置服务删除规则，跳过" -Percent 90
    Write-Log "未配置服务删除规则，跳过服务删除步骤"
}

# ------------------------------ 4.5：清理临时文件与优化 ------------------------------
Update-Progress -Activity "镜像精简" -Status "最终清理与优化" -Percent 90
try {
    # 删除.NET原生镜像、临时文件
    Remove-Item -Path "$scratchDir\Windows\assembly\NativeImages_*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$scratchDir\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    # 清理WinSxS（保留核心组件）
    & dism /image:$scratchDir /Cleanup-Image /StartComponentCleanup /ResetBase /English 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
    Write-Log "临时文件清理与组件优化完成"
    Update-Progress -Activity "镜像精简" -Status "镜像精简全部完成" -Percent 100
} catch {
    Write-Log "最终清理失败，原因：$($_.Exception.Message)" -Level WARNING
}

# ============================== 步骤5：卸载WIM并生成最终ISO ==============================
Update-Progress -Activity "最终生成" -Status "卸载WIM并提交修改" -Percent 0
try {
    Write-Host "`n正在卸载WIM并提交修改（约3-5分钟）..."
    & dism /English "/unmount-image" "/mountdir:$scratchDir" "/commit" 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
    Update-Progress -Activity "最终生成" -Status "WIM卸载完成" -Percent 30
} catch {
    Write-Log "卸载WIM失败，原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# 压缩WIM为ESD（减小体积）
Update-Progress -Activity "最终生成" -Status "压缩WIM为ESD格式" -Percent 30
try {
    Write-Host "`n正在压缩镜像为ESD格式（约10-20分钟）..."
    & dism /Export-Image `
        /SourceImageFile:"$workDir\sources\install.wim" `
        /SourceIndex:1 `
        /DestinationImageFile:"$workDir\sources\install.esd" `
        /Compress:recovery /English 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
    
    # 删除原WIM
    Remove-Item -Path "$workDir\sources\install.wim" -Force -ErrorAction Stop
    Update-Progress -Activity "最终生成" -Status "ESD压缩完成" -Percent 70
} catch {
    Write-Log "压缩ESD失败，原因：$($_.Exception.Message)" -Level WARNING
    Write-Host "`n警告：ESD压缩失败，将保留原WIM格式"
}

# 生成最终ISO（需要oscdimg.exe）
Update-Progress -Activity "最终生成" -Status "生成bootable ISO" -Percent 70
try {
    $oscdimgPath = Join-Path -Path $PSScriptRoot -ChildPath "oscdimg.exe"
    # 下载oscdimg.exe（如果不存在）
    if (-not (Test-Path $oscdimgPath)) {
        Write-Log "未找到oscdimg.exe，开始下载"
        Invoke-WebRequest -Uri "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe" -OutFile $oscdimgPath -ErrorAction Stop
    }
    
    # 生成ISO命令
    $isoOutputPath = Join-Path -Path $PSScriptRoot -ChildPath "nano11_$(Get-Date -Format 'yyyyMMdd').iso"
    & $oscdimgPath `-m -o -u2 -udfver102 `
        "-bootdata:2#p0,e,b$workDir\boot\etfsboot.com#pEF,e,b$workDir\efi\microsoft\boot\efisys.bin" `
        "$workDir" "$isoOutputPath" 2>&1 | ForEach-Object { Write-Log "oscdimg输出：$_" }
    
    if (-not (Test-Path $isoOutputPath)) { throw "ISO生成后未找到文件" }
    Update-Progress -Activity "最终生成" -Status "ISO生成完成" -Percent 100
    Write-Log "最终ISO生成成功，路径：$isoOutputPath"
    Write-Host "`n=== 镜像构建完成！ ==="
    Write-Host "最终ISO文件：$isoOutputPath"
    Write-Host "详细日志文件：$logPath`n"
} catch {
    Write-Log "生成ISO失败，原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# ============================== 步骤6：清理资源 ==============================
Write-Host "`n正在清理临时资源（约1分钟）..."
Update-Progress -Activity "资源清理" -Status "开始清理临时文件" -Percent 0

try {
    # 1. 卸载原始ISO
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction Stop
    Write-Log "成功卸载原始ISO：$($selectedIso.FullName)"
    
    # 2. 删除工作目录和挂载目录
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction Stop
    Remove-Item -Path $scratchDir -Recurse -Force -ErrorAction Stop
    Write-Log "成功删除临时目录：$workDir 和 $scratchDir"
    
    Update-Progress -Activity "资源清理" -Status "清理完成" -Percent 100
    Write-Log "=== 脚本执行完成，所有资源清理完毕 ==="
    Write-Host "`n临时资源清理完成，脚本退出！"
} catch {
    Write-Log "清理临时资源失败，原因：$($_.Exception.Message)" -Level WARNING
    Write-Host "`n警告：部分临时资源未清理，请手动删除以下目录："
    Write-Host "  - 工作目录：$workDir"
    Write-Host "  - 挂载目录：$scratchDir"
}

Read-Host "`n按Enter键退出"
exit 0
