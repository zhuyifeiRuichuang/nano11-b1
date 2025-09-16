<#
脚本功能：Windows 11 精简镜像构建工具（简化配置版）
核心优化：conf文件仅需罗列待删除内容，写入即删除，无需=remove
#>

# ============================== 核心函数定义 ==============================
# 1. 简化版INI配置读取（分类下直接读取待删除内容，忽略注释/空行）
function Get-SimpleIniContent {
    param([string]$Path)
    $ini = @{}
    $currentSection = $null

    Get-Content -Path $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        # 忽略：空行、;开头注释、#开头注释
        if ([string]::IsNullOrEmpty($line) -or $line -match '^[;#].*') { return }
        # 匹配分类（[sectionName]）
        if ($line -match '^\[(.*)\]$') {
            $currentSection = $matches[1].Trim()
            $ini[$currentSection] = @() # 分类下用数组存储待删除内容
            return
        }
        # 分类下的内容：直接加入数组（支持通配符）
        if ($currentSection) {
            $ini[$currentSection] += $line
        }
    }
    return $ini
}

# 2. 日志写入（仅错误/警告显终端，详细内容存日志）
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
    # 终端仅显错误/警告
    if ($Level -eq "ERROR") { Write-Host "`n【错误】$Message`n" -ForegroundColor Red }
    elseif ($Level -eq "WARNING") { Write-Host "【警告】$Message" -ForegroundColor Yellow }
}

# 3. 进度条展示（终端+日志双同步）
function Update-Progress {
    param(
        [Parameter(Mandatory=$true)][string]$Activity,
        [Parameter(Mandatory=$true)][string]$Status,
        [Parameter(Mandatory=$true)][int]$Percent
    )
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $Percent
    # 每10%或末尾更新终端文本
    if ($Percent % 10 -eq 0 -or $Percent -eq 100) {
        Write-Host "[$Activity] $Status - $Percent%"
    }
    Write-Log "[$Activity] $Status - $Percent%"
}

# ============================== 初始化检查 ==============================
# 1. 执行策略检查
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Host "`n当前执行策略为Restricted，需改为RemoteSigned（yes/no）？"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false | Out-Null
        Write-Host "执行策略已修改，脚本将重启..."
        Start-Sleep 2
        # 管理员重启
        $adminProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
        $adminProcess.Arguments = $myInvocation.MyCommand.Definition
        $adminProcess.Verb = "runas"
        [System.Diagnostics.Process]::Start($adminProcess) | Out-Null
        exit
    } else { exit }
}

# 2. 管理员权限检查
$currentPrincipal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n需管理员权限，正在重启..."
    $adminProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $adminProcess.Arguments = $myInvocation.MyCommand.Definition
    $adminProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($adminProcess) | Out-Null
    exit
}

# 3. 日志文件初始化（build_日期时间_随机数.log）
$logFileName = "build_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(Get-Random -Maximum 10000).log"
$logPath = Join-Path -Path $PSScriptRoot -ChildPath $logFileName
try {
    New-Item -Path $logPath -ItemType File -Force | Out-Null
    Write-Host "`n日志文件：$logFileName（详细内容仅存于此）`n"
    Write-Log "=== 脚本启动，初始化完成 ==="
} catch {
    Write-Host "`n错误：创建日志失败！原因：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 4. 确认执行
Write-Host "=== nano11 精简镜像构建工具（简化配置版） ==="
Write-Host "说明：conf文件中填写的内容将自动删除，终端仅显进度`n"
$confirm = Read-Host "是否继续？(y/n)"
if ($confirm -ne 'y') {
    Write-Log "用户取消执行"
    Write-Host "`n脚本退出..."
    exit 0
}

# ============================== 步骤1：读取/生成简化版conf ==============================
Update-Progress -Activity "配置处理" -Status "检查build_remove.conf" -Percent 0
$configPath = Join-Path -Path $PSScriptRoot -ChildPath "build_remove.conf"

# 无conf时生成简化版默认配置
if (-not (Test-Path $configPath -PathType Leaf)) {
    Write-Log "未找到conf文件，生成默认简化版配置" -Level WARNING
    $defaultConfig = @"
; nano11 镜像删除配置文件（简化版）
; 规则：分类下直接填写待删除内容（支持通配符*），写入即删除，空行/;注释忽略

[languages]
; 待删除的语言包（示例：zh-cn*=所有中文包，ja-jp*=日语包）
zh-cn*
ja-jp*
ko-kr*
en-gb*

[languages-ime]
; 待删除的输入法（示例：*IME-zh-cn*=中文输入法，*IME-ja*=日语输入法）
*IME-zh-cn*
*IME-ja-jp*
*IME-ko-kr*
*IME-en*

[service]
; 待删除的系统服务（服务名可通过 services.msc 查看）
Spooler          ; 打印后台处理服务
PrintNotify      ; 打印通知服务
Fax              ; 传真服务
RemoteRegistry   ; 远程注册表服务
diagsvc          ; 诊断服务
WerSvc           ; 错误报告服务
MapsBroker       ; 地图服务
wuauserv         ; Windows更新服务
UsoSvc           ; 更新服务组件

[driver]
; 待删除的驱动（目录名通配符，参考：C:\Windows\System32\DriverStore\FileRepository）
prn*             ; 打印机驱动（如prnms001.inf目录）
scan*            ; 扫描仪驱动
mfd*             ; 多功能设备驱动
wscsmd.inf*      ; 智能卡驱动
tapdrv*          ; 磁带驱动
rdpbus.inf*      ; 远程桌面虚拟总线驱动
tdibth.inf*      ; 蓝牙个人局域网驱动

[appx]
; 待删除的预装AppX应用（包名通配符，如*Bing*=所有Bing相关应用）
*Zune*
*Bing*
*Clipchamp*
*Gaming*
*Teams*
*YourPhone*
*Solitaire*
*FeedbackHub*
*Maps*
*OfficeHub*
*Copilot*
"@
    $defaultConfig | Out-File -Path $configPath -Encoding UTF8 -Force
    Write-Host "`n已生成默认配置：build_remove.conf"
    Write-Host "请编辑配置文件（直接填写待删除内容）后重新运行！`n"
    exit 0
}

# 读取简化版conf（分类下直接取待删除列表）
try {
    $iniConfig = Get-SimpleIniContent -Path $configPath
    # 提取各分类待删除规则（无分类时默认空数组）
    $delLanguages = $iniConfig.ContainsKey('languages') ? $iniConfig['languages'] : @()
    $delLanguagesIme = $iniConfig.ContainsKey('languages-ime') ? $iniConfig['languages-ime'] : @()
    $delServices = $iniConfig.ContainsKey('service') ? $iniConfig['service'] : @()
    $delDrivers = $iniConfig.ContainsKey('driver') ? $iniConfig['driver'] : @()
    $delAppx = $iniConfig.ContainsKey('appx') ? $iniConfig['appx'] : @()

    Update-Progress -Activity "配置处理" -Status "解析完成，加载删除规则" -Percent 100
    Write-Log "=== 配置文件解析结果 ==="
    Write-Log "[languages] 待删除：$($delLanguages -join ', ')"
    Write-Log "[languages-ime] 待删除：$($delLanguagesIme -join ', ')"
    Write-Log "[service] 待删除：$($delServices -join ', ')"
    Write-Log "[driver] 待删除：$($delDrivers -join ', ')"
    Write-Log "[appx] 待删除：$($delAppx -join ', ')"
} catch {
    Write-Log "解析conf文件失败！原因：$($_.Exception.Message)" -Level ERROR
    exit 1
}

# ============================== 步骤2：自动读取ISO并选择 ==============================
Update-Progress -Activity "ISO处理" -Status "扫描脚本目录ISO文件" -Percent 0

# 扫描脚本目录下的ISO
$isoFiles = Get-ChildItem -Path $PSScriptRoot -Filter *.iso -File
if (-not $isoFiles) {
    Write-Log "未在脚本目录找到ISO文件" -Level ERROR
    Write-Host "`n请将Windows 11 ISO放在脚本目录后重试！"
    exit 1
}

# 列表展示ISO供选择
Write-Host "`n找到以下ISO文件："
for ($i = 0; $i -lt $isoFiles.Count; $i++) {
    Write-Host "$($i+1). $($isoFiles[$i].Name) （大小：$([math]::Round($isoFiles[$i].Length/1GB,2))GB）"
}

# 验证用户输入
do {
    $selectedInput = Read-Host "`n请输入ISO编号（1-$($isoFiles.Count)）"
    $isValid = [int]::TryParse($selectedInput, [ref]$selectedIndex) -and $selectedIndex -ge 1 -and $selectedIndex -le $isoFiles.Count
    if (-not $isValid) { Write-Host "输入无效，请输1-$($isoFiles.Count)之间的数字" }
} while (-not $isValid)

$selectedIso = $isoFiles[$selectedIndex - 1]
Update-Progress -Activity "ISO处理" -Status "选择ISO：$($selectedIso.Name)" -Percent 30

# 自动挂载ISO
try {
    Write-Host "`n正在挂载ISO（约10秒）..."
    $mountResult = Mount-DiskImage -ImagePath $selectedIso.FullName -PassThru -ErrorAction Stop
    $volume = $mountResult | Get-Volume
    $DriveLetter = "$($volume.DriveLetter):"
    if (-not (Test-Path "$DriveLetter\sources")) { throw "ISO非Windows镜像（无sources目录）" }
    Update-Progress -Activity "ISO处理" -Status "ISO挂载成功：$DriveLetter" -Percent 100
    Write-Log "ISO挂载信息：文件=$($selectedIso.FullName)，驱动器=$DriveLetter"
} catch {
    Write-Log "ISO挂载失败！原因：$($_.Exception.Message)" -Level ERROR
    if ($mountResult) { Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue }
    exit 1
}

# ============================== 步骤3：镜像复制与预处理 ==============================
$mainOSDrive = $env:SystemDrive
$workDir = "$mainOSDrive\nano11"
$scratchDir = "$mainOSDrive\scratchdir"
Update-Progress -Activity "镜像预处理" -Status "创建工作目录" -Percent 0

# 创建目录
try {
    New-Item -Path "$workDir\sources", $scratchDir -ItemType Directory -Force | Out-Null
    Update-Progress -Activity "镜像预处理" -Status "工作目录创建完成" -Percent 20
} catch {
    Write-Log "创建目录失败！原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# 检查并转换ESD（若有）
if (-not (Test-Path "$DriveLetter\sources\install.wim") -and (Test-Path "$DriveLetter\sources\install.esd")) {
    Update-Progress -Activity "镜像预处理" -Status "发现ESD，转换为WIM" -Percent 30
    Write-Host "`n发现install.esd，需转换为WIM（约5-10分钟）..."
    
    # 获取ESD索引
    Write-Log "读取ESD索引：$DriveLetter\sources\install.esd"
    $esdInfo = & dism /English "/Get-WimInfo" "/wimfile:$DriveLetter\sources\install.esd" 2>&1
    $esdInfo | ForEach-Object { Write-Log "DISM输出：$_" }
    
    $index = Read-Host "`n请输入ESD镜像索引（如2=专业版）"
    if (-not [int]::TryParse($index, [ref]$indexNum)) {
        Write-Log "索引输入无效" -Level ERROR
        Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
        exit 1
    }
    
    # 转换ESD→WIM
    try {
        Update-Progress -Activity "镜像预处理" -Status "转换ESD→WIM（索引$indexNum）" -Percent 50
        & dism /Export-Image `
            /SourceImageFile:"$DriveLetter\sources\install.esd" `
            /SourceIndex:$indexNum `
            /DestinationImageFile:"$workDir\sources\install.wim" `
            /Compress:max /CheckIntegrity 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
        
        if (-not (Test-Path "$workDir\sources\install.wim")) { throw "转换后无install.wim" }
        Update-Progress -Activity "镜像预处理" -Status "ESD转换完成" -Percent 80
    } catch {
        Write-Log "ESD转换失败！原因：$($_.Exception.Message)" -Level ERROR
        Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
        exit 1
    }
} elseif (-not (Test-Path "$DriveLetter\sources\install.wim") -and -not (Test-Path "$DriveLetter\sources\install.esd")) {
    Write-Log "ISO无install.wim/install.esd，非Windows镜像" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# 复制ISO文件到工作目录
Update-Progress -Activity "镜像预处理" -Status "复制ISO文件（约5-15分钟）" -Percent 80
try {
    $sourceFiles = Get-ChildItem -Path $DriveLetter\* -Recurse -File -ErrorAction SilentlyContinue
    $totalFiles = $sourceFiles.Count
    $currentFile = 0

    Get-ChildItem -Path $DriveLetter\* -Recurse -File -ErrorAction Stop | ForEach-Object {
        $currentFile++
        $percent = [math]::Round(($currentFile / $totalFiles) * 20 + 80, 0) # 80-100%进度段
        $destPath = $_.FullName.Replace($DriveLetter, $workDir)
        $destDir = Split-Path $destPath -Parent
        
        if (-not (Test-Path $destDir)) { New-Item -Path $destDir -Force | Out-Null }
        Copy-Item -Path $_.FullName -Destination $destPath -Force | Out-Null
        
        # 每200个文件更新一次进度
        if ($currentFile % 200 -eq 0 -or $currentFile -eq $totalFiles) {
            Update-Progress -Activity "镜像预处理" -Status "已复制：$currentFile/$totalFiles 个文件" -Percent $percent
        }
    }
    # 删除残留ESD
    Remove-Item -Path "$workDir\sources\install.esd" -Force -ErrorAction SilentlyContinue
    Write-Log "ISO复制完成，工作目录：$workDir"
} catch {
    Write-Log "复制ISO失败！原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# ============================== 步骤4：挂载WIM并按conf精简 ==============================
$wimPath = "$workDir\sources\install.wim"
Update-Progress -Activity "WIM处理" -Status "读取WIM镜像信息" -Percent 0

# 获取WIM索引
try {
    Write-Log "读取WIM索引：$wimPath"
    $wimInfo = & dism /English "/Get-WimInfo" "/wimfile:$wimPath" 2>&1
    $wimInfo | ForEach-Object { Write-Log "DISM输出：$_" }
    
    $index = Read-Host "`n请输入WIM镜像索引（如2=专业版）"
    if (-not [int]::TryParse($index, [ref]$indexNum)) { throw "索引需为数字" }
    Update-Progress -Activity "WIM处理" -Status "选择索引：$indexNum" -Percent 20
} catch {
    Write-Log "读取WIM索引失败！原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# 挂载WIM
try {
    Write-Host "`n挂载WIM镜像（约3-5分钟）..."
    $adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount]).Value
    
    # 设置WIM权限
    & takeown "/F" $wimPath 2>&1 | ForEach-Object { Write-Log "takeown输出：$_" }
    & icacls $wimPath "/grant" "$adminGroup:(F)" 2>&1 | ForEach-Object { Write-Log "icacls输出：$_" }
    Set-ItemProperty -Path $wimPath -Name IsReadOnly -Value $false -ErrorAction Stop
    
    # 挂载WIM
    Update-Progress -Activity "WIM处理" -Status "开始挂载WIM" -Percent 30
    & dism /English "/mount-image" `
        "/imagefile:$wimPath" `
        "/index:$indexNum" `
        "/mountdir:$scratchDir" 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
    
    if (-not (Test-Path "$scratchDir\Windows")) { throw "挂载后无Windows目录" }
    Update-Progress -Activity "WIM处理" -Status "WIM挂载成功：$scratchDir" -Percent 50
} catch {
    Write-Log "挂载WIM失败！原因：$($_.Exception.Message)" -Level ERROR
    & dism /English "/unmount-image" "/mountdir:$scratchDir" "/discard" 2>&1 | Out-Null
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# ------------------------------ 4.1：删除预装AppX（按conf的[appx]） ------------------------------
if ($delAppx.Count -gt 0) {
    Update-Progress -Activity "镜像精简" -Status "删除预装AppX（按conf）" -Percent 0
    try {
        $appxPackages = Get-AppxProvisionedPackage -Path $scratchDir -ErrorAction Stop
        $totalApps = $appxPackages.Count
        $currentApp = 0
        $deletedCount = 0

        foreach ($app in $appxPackages) {
            $currentApp++
            $appName = $app.PackageName
            # 匹配conf中任意AppX规则
            $matchRule = $delAppx | Where-Object { $appName -like $_ }
            
            if ($matchRule) {
                Remove-AppxProvisionedPackage -Path $scratchDir -PackageName $appName -ErrorAction SilentlyContinue
                $deletedCount++
                Write-Log "删除AppX：$($app.DisplayName)（匹配规则：$matchRule）"
            }
            
            $percent = [math]::Round(($currentApp / $totalApps) * 20, 0) # 0-20%进度段
            if ($currentApp % 10 -eq 0 -or $currentApp -eq $totalApps) {
                Update-Progress -Activity "镜像精简" -Status "已处理：$currentApp/$totalApps 个App，删除：$deletedCount 个" -Percent $percent
            }
        }
        Update-Progress -Activity "镜像精简" -Status "AppX删除完成，共删除：$deletedCount 个" -Percent 20
    } catch {
        Write-Log "删除AppX失败！原因：$($_.Exception.Message)" -Level WARNING
    }
} else {
    Update-Progress -Activity "镜像精简" -Status "conf无[appx]规则，跳过AppX删除" -Percent 20
    Write-Log "conf未配置[appx]，跳过预装AppX删除"
}

# ------------------------------ 4.2：删除系统组件（语言/输入法，按conf） ------------------------------
$totalDelRules = $delLanguages.Count + $delLanguagesIme.Count
if ($totalDelRules -gt 0) {
    Update-Progress -Activity "镜像精简" -Status "删除系统组件（语言/输入法）" -Percent 20
    try {
        $allPackages = & dism /image:$scratchDir /Get-Packages /Format:Table 2>&1 | Where-Object { $_ -match '^Microsoft' }
        $totalPkgs = $allPackages.Count
        $currentPkg = 0
        $deletedCount = 0
        # 合并语言+输入法删除规则
        $allDelRules = $delLanguages + $delLanguagesIme

        foreach ($pkg in $allPackages) {
            $currentPkg++
            $pkgName = ($pkg -split "\s+")[0]
            # 匹配任意删除规则
            $matchRule = $allDelRules | Where-Object { $pkgName -like $_ }
            
            if ($matchRule) {
                & dism /image:$scratchDir /Remove-Package /PackageName:$pkgName /English 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
                $deletedCount++
                Write-Log "删除组件：$pkgName（匹配规则：$matchRule）"
            }
            
            $percent = [math]::Round(20 + ($currentPkg / $totalPkgs) * 30, 0) # 20-50%进度段
            if ($currentPkg % 5 -eq 0 -or $currentPkg -eq $totalPkgs) {
                Update-Progress -Activity "镜像精简" -Status "已处理：$currentPkg/$totalPkgs 个组件，删除：$deletedCount 个" -Percent $percent
            }
        }
        Update-Progress -Activity "镜像精简" -Status "组件删除完成，共删除：$deletedCount 个" -Percent 50
    } catch {
        Write-Log "删除系统组件失败！原因：$($_.Exception.Message)" -Level WARNING
    }
} else {
    Update-Progress -Activity "镜像精简" -Status "conf无语言/输入法规则，跳过" -Percent 50
    Write-Log "conf未配置[languages]/[languages-ime]，跳过组件删除"
}

# ------------------------------ 4.3：删除驱动（按conf的[driver]） ------------------------------
if ($delDrivers.Count -gt 0) {
    Update-Progress -Activity "镜像精简" -Status "删除驱动（按conf）" -Percent 50
    try {
        $driverRepo = "$scratchDir\Windows\System32\DriverStore\FileRepository"
        $driverDirs = Get-ChildItem -Path $driverRepo -Directory -ErrorAction SilentlyContinue
        $totalDrivers = $driverDirs.Count
        $currentDriver = 0
        $deletedCount = 0

        foreach ($dir in $driverDirs) {
            $currentDriver++
            $dirName = $dir.Name
            # 匹配conf中任意驱动规则
            $matchRule = $delDrivers | Where-Object { $dirName -like $_ }
            
            if ($matchRule) {
                Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $deletedCount++
                Write-Log "删除驱动：$dirName（匹配规则：$matchRule）"
            }
            
            $percent = [math]::Round(50 + ($currentDriver / $totalDrivers) * 20, 0) # 50-70%进度段
            if ($currentDriver % 20 -eq 0 -or $currentDriver -eq $totalDrivers) {
                Update-Progress -Activity "镜像精简" -Status "已处理：$currentDriver/$totalDrivers 个驱动目录，删除：$deletedCount 个" -Percent $percent
            }
        }
        Update-Progress -Activity "镜像精简" -Status "驱动删除完成，共删除：$deletedCount 个目录" -Percent 70
    } catch {
        Write-Log "删除驱动失败！原因：$($_.Exception.Message)" -Level WARNING
    }
} else {
    Update-Progress -Activity "镜像精简" -Status "conf无[driver]规则，跳过驱动删除" -Percent 70
    Write-Log "conf未配置[driver]，跳过驱动删除"
}

# ------------------------------ 4.4：删除系统服务（按conf的[service]） ------------------------------
if ($delServices.Count -gt 0) {
    Update-Progress -Activity "镜像精简" -Status "删除系统服务（按conf）" -Percent 70
    try {
        # 加载系统注册表
        reg load HKLM\zSYSTEM "$scratchDir\Windows\System32\config\SYSTEM" 2>&1 | ForEach-Object { Write-Log "REG输出：$_" }
        $totalServices = $delServices.Count
        $currentService = 0
        $deletedCount = 0

        foreach ($service in $delServices) {
            $currentService++
            $servicePath = "HKLM\zSYSTEM\ControlSet001\Services\$service"
            
            if (Test-Path "Registry::$servicePath") {
                reg delete "$servicePath" /f 2>&1 | ForEach-Object { Write-Log "REG输出：$_" }
                $deletedCount++
                Write-Log "删除服务：$service（注册表路径：$servicePath）"
            } else {
                Write-Log "服务 $service 不存在，跳过" -Level WARNING
            }
            
            $percent = [math]::Round(70 + ($currentService / $totalServices) * 20, 0) # 70-90%进度段
            Update-Progress -Activity "镜像精简" -Status "已处理：$currentService/$totalServices 个服务，删除：$deletedCount 个" -Percent $percent
        }
        
        # 卸载注册表
        reg unload HKLM\zSYSTEM 2>&1 | ForEach-Object { Write-Log "REG输出：$_" }
        Update-Progress -Activity "镜像精简" -Status "服务删除完成，共删除：$deletedCount 个" -Percent 90
    } catch {
        Write-Log "删除服务失败！原因：$($_.Exception.Message)" -Level WARNING
        reg unload HKLM\zSYSTEM 2>&1 | Out-Null # 强制卸载
    }
} else {
    Update-Progress -Activity "镜像精简" -Status "conf无[service]规则，跳过服务删除" -Percent 90
    Write-Log "conf未配置[service]，跳过服务删除"
}

# ------------------------------ 4.5：最终清理与优化 ------------------------------
Update-Progress -Activity "镜像精简" -Status "临时文件清理与组件优化" -Percent 90
try {
    # 删除.NET原生镜像、临时文件
    Remove-Item -Path "$scratchDir\Windows\assembly\NativeImages_*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$scratchDir\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    # 清理WinSxS
    & dism /image:$scratchDir /Cleanup-Image /StartComponentCleanup /ResetBase /English 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
    Write-Log "临时文件清理完成"
    Update-Progress -Activity "镜像精简" -Status "镜像精简全部完成" -Percent 100
} catch {
    Write-Log "最终清理失败！原因：$($_.Exception.Message)" -Level WARNING
}

# ============================== 步骤5：生成最终ISO ==============================
Update-Progress -Activity "最终生成" -Status "卸载WIM并提交修改" -Percent 0
try {
    Write-Host "`n卸载WIM并提交修改（约3-5分钟）..."
    & dism /English "/unmount-image" "/mountdir:$scratchDir" "/commit" 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
    Update-Progress -Activity "最终生成" -Status "WIM卸载完成" -Percent 30
} catch {
    Write-Log "卸载WIM失败！原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# 压缩为ESD（减小体积）
Update-Progress -Activity "最终生成" -Status "压缩WIM为ESD" -Percent 30
try {
    Write-Host "`n压缩镜像为ESD（约10-20分钟）..."
    & dism /Export-Image `
        /SourceImageFile:"$workDir\sources\install.wim" `
        /SourceIndex:1 `
        /DestinationImageFile:"$workDir\sources\install.esd" `
        /Compress:recovery /English 2>&1 | ForEach-Object { Write-Log "DISM输出：$_" }
    
    Remove-Item -Path "$workDir\sources\install.wim" -Force -ErrorAction Stop
    Update-Progress -Activity "最终生成" -Status "ESD压缩完成" -Percent 70
} catch {
    Write-Log "压缩ESD失败！原因：$($_.Exception.Message)" -Level WARNING
    Write-Host "`n警告：ESD压缩失败，保留原WIM格式"
}

# 生成bootable ISO
Update-Progress -Activity "最终生成" -Status "生成最终ISO" -Percent 70
try {
    $oscdimgPath = Join-Path -Path $PSScriptRoot -ChildPath "oscdimg.exe"
    # 下载oscdimg（若缺失）
    if (-not (Test-Path $oscdimgPath)) {
        Write-Log "缺失oscdimg.exe，开始下载"
        Invoke-WebRequest -Uri "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe" -OutFile $oscdimgPath -ErrorAction Stop
    }
    
    # 生成ISO
    $isoOutputPath = Join-Path -Path $PSScriptRoot -ChildPath "nano11_$(Get-Date -Format 'yyyyMMdd').iso"
    & $oscdimgPath `-m -o -u2 -udfver102 `
        "-bootdata:2#p0,e,b$workDir\boot\etfsboot.com#pEF,e,b$workDir\efi\microsoft\boot\efisys.bin" `
        "$workDir" "$isoOutputPath" 2>&1 | ForEach-Object { Write-Log "oscdimg输出：$_" }
    
    if (-not (Test-Path $isoOutputPath)) { throw "ISO生成后无文件" }
    Update-Progress -Activity "最终生成" -Status "ISO生成完成" -Percent 100
    Write-Log "最终ISO路径：$isoOutputPath"
    Write-Host "`n=== 镜像构建成功！ ==="
    Write-Host "最终ISO：$isoOutputPath"
    Write-Host "详细日志：$logPath`n"
} catch {
    Write-Log "生成ISO失败！原因：$($_.Exception.Message)" -Level ERROR
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction SilentlyContinue
    exit 1
}

# ============================== 步骤6：清理资源 ==============================
Write-Host "`n清理临时资源（约1分钟）..."
Update-Progress -Activity "资源清理" -Status "开始清理" -Percent 0

try {
    # 卸载原始ISO
    Dismount-DiskImage -ImagePath $selectedIso.FullName -ErrorAction Stop
    Write-Log "卸载原始ISO：$($selectedIso.FullName)"
    
    # 删除临时目录
    Remove-Item -Path $workDir, $scratchDir -Recurse -Force -ErrorAction Stop
    Write-Log "删除临时目录：$workDir、$scratchDir"
    
    Update-Progress -Activity "资源清理" -Status "清理完成" -Percent 100
    Write-Log "=== 脚本执行完成，所有资源清理完毕 ==="
    Write-Host "`n临时资源清理完成！"
} catch {
    Write-Log "清理失败！原因：$($_.Exception.Message)" -Level WARNING
    Write-Host "`n警告：需手动删除临时目录："
    Write-Host "  - 工作目录：$workDir"
    Write-Host "  - 挂载目录：$scratchDir"
}

Read-Host "`n按Enter键退出"
exit 0
