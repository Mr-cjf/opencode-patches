<#
.SYNOPSIS
    OpenCode 一键恢复到 1.17.20 版本（含补丁 asar + 冻结自动更新）
.DESCRIPTION
    本脚本用于从 1.18.x 降级回 1.17.20，恢复工作区和补丁功能。
    支持自动下载缺失资产、哈希校验、数据库修复联动。
    下载通道优先级：gh CLI -> Invoke-WebRequest -> curl.exe -> 手动
    用法（推荐使用 restore.bat 双击运行）：
      powershell.exe -ExecutionPolicy Bypass -File ".\restore-opencode.ps1"

    参数：
      -SkipDownload    跳过自动下载缺失资产
      -FixDatabase     恢复完成后自动修复数据库 time 字段
      -Yes             跳过所有确认提示（静默模式）
    本机：双击 restore.bat 一键完成
    异地：只下载 restore.bat 一个文件，双击即自动下载其余资产
    注意：脚本会自动关闭 OpenCode 进程，请先保存工作。
#>

param(
    [switch]$SkipDownload,
    [switch]$FixDatabase,
    [switch]$Yes
)

$ErrorActionPreference = "Continue"
$script:ExitCode = 0

# ---------- 甯搁噺 ----------
$ReleaseBase   = "https://github.com/Mr-cjf/opencode-patches/releases/download/v1.17.20-patched-recovery/"
$ExeFileName   = "opencode-desktop-win-x64-1.17.20.exe"
$ZipFileName   = "app.asar.patched.zip"
$ExpectedExeSize = 134784328
$ExpectedZipSize = 39761484

# ---------- 杈呭姪鍑芥暟 ----------
function Write-Step {
    param([string]$Prefix, [string]$Message)
    Write-Host "[${Prefix}] ${Message}"
}

# ---------- 涓嬭浇澶辫触鏃剁殑鎵嬪姩鎸囧紩 ----------
function Show-ManualDownloadGuide {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "  鑷姩涓嬭浇澶辫触" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "璇锋墜鍔ㄤ笅杞戒互涓嬫枃浠跺苟鏀惧叆鏈洰褰曪細" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Release 椤甸潰:" -ForegroundColor Cyan
    Write-Host "  https://github.com/Mr-cjf/opencode-patches/releases/tag/v1.17.20-patched-recovery"
    Write-Host ""
    Write-Host "  闇€瑕佷笅杞界殑鏂囦欢:" -ForegroundColor Cyan
    Write-Host "  1. ${ExeFileName}"
    Write-Host "  2. ${ZipFileName}(鎴栬В鍘嬪悗鐨?app.asar.patched)"
    Write-Host ""
    Write-Host "  涓嬭浇鍚庢斁鍒颁互涓嬬洰褰?" -ForegroundColor Cyan
    Write-Host "  $PSScriptRoot"
    Write-Host ""
    Write-Host "  鐒跺悗閲嶆柊杩愯鏈剼鏈?鎴栧姞 -SkipDownload 鍙傛暟璺宠繃涓嬭浇妫€鏌?"
    Write-Host ""
}

# ---------- 涓嬭浇鍗曚釜鏂囦欢锛堝绾у洖閫€锛歡h -> IWR -> curl -> 鎵嬪姩锛?---------
function Download-File {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Description,
        [long]$ExpectedSize,
        [string]$Repo = "Mr-cjf/opencode-patches",
        [string]$ReleaseTag = "v1.17.20-patched-recovery",
        [string]$FileName
    )

    Write-Host "  涓嬭浇鍦板潃: ${Url}" -ForegroundColor Gray
    Write-Host "  淇濆瓨浣嶇疆: ${Destination}" -ForegroundColor Gray

    $success = $false

    # ----- 鏂规硶1: gh CLI锛堥閫夛細缁曡繃 DNS/鐩磋繛闃绘柇锛?----
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        try {
            Write-Host "  灏濊瘯鏂规硶1[gh release download] ..." -ForegroundColor Gray
            if (-not $env:GH_TOKEN -and $env:GITHUB_PERSONAL_ACCESS_TOKEN) { $env:GH_TOKEN = $env:GITHUB_PERSONAL_ACCESS_TOKEN }
            & gh release download $ReleaseTag --repo $Repo --pattern $FileName --dir (Split-Path $Destination -Parent) --clobber 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $Destination)) {
                $success = $true
                Write-Step "涓嬭浇" "鏂规硶1鎴愬姛: ${Description}锛坓h CLI锛?
            } else {
                Write-Host "  鏂规硶1澶辫触 (gh exit code: ${LASTEXITCODE})" -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "  鏂规硶1[gh] 澶辫触: $_" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "  鏂规硶1[gh CLI] 涓嶅彲鐢紙鏈畨瑁?gh锛夛紝璺宠繃銆? -ForegroundColor DarkYellow
    }

    # ----- 鏂规硶2: Invoke-WebRequest -----
    if (-not $success) {
        try {
            $oldProgress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            Write-Host "  灏濊瘯鏂规硶2[PowerShell Invoke-WebRequest] ..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
            $ProgressPreference = $oldProgress
            $success = $true
            Write-Step "涓嬭浇" "鏂规硶2鎴愬姛: ${Description}"
        } catch {
            $ProgressPreference = $oldProgress
            Write-Host "  鏂规硶2[IWR] 澶辫触: $_" -ForegroundColor DarkYellow
        }
    }

    # ----- 鏂规硶3: curl.exe -----
    if (-not $success) {
        try {
            Write-Host "  灏濊瘯鏂规硶3[curl.exe] ..." -ForegroundColor Gray
            $null = & curl.exe -L -o "$Destination" "$Url" 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-Path $Destination)) {
                $success = $true
                Write-Step "涓嬭浇" "鏂规硶3鎴愬姛: ${Description}"
            } else {
                Write-Host "  鏂规硶3[curl] 澶辫触 (exit code: ${LASTEXITCODE})" -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "  鏂规硶3[curl] 澶辫触: $_" -ForegroundColor DarkYellow
        }
    }

    if (-not $success) {
        Show-ManualDownloadGuide
        return $false
    }

    # ----- 鏍￠獙澶у皬 -----
    if (Test-Path $Destination) {
        $actualSize = (Get-Item $Destination).Length
        if ($ExpectedSize -gt 0 -and $actualSize -ne $ExpectedSize) {
            Write-Host "[璀﹀憡] 鏂囦欢澶у皬涓嶅尮閰? 鏈熸湜 ${ExpectedSize} 瀛楄妭, 瀹為檯 ${actualSize} 瀛楄妭" -ForegroundColor Red
            Write-Host "  涓嬭浇鍙兘涓嶅畬鏁淬€傚皢涓柇鎿嶄綔銆? -ForegroundColor Red
            return $false
        } else {
            Write-Step "涓嬭浇" "澶у皬楠岃瘉閫氳繃 ($actualSize 瀛楄妭)"
        }
    }

    return $true
}
# ---------- 鑷姩涓嬭浇缂哄け璧勪骇 ----------
function Invoke-AutoDownload {
    if ($SkipDownload) {
        Write-Step "涓嬭浇" "宸茶烦杩囦笅杞?-SkipDownload 鍙傛暟)"
        return
    }

    Write-Step "涓嬭浇" "妫€鏌ョ己澶辫祫浜ф枃浠?.."

    $exePath     = "$PSScriptRoot\$ExeFileName"
    $patchedPath = "$PSScriptRoot\app.asar.patched"
    $zipPath     = "$PSScriptRoot\$ZipFileName"

    $needExe = -not (Test-Path $exePath)
    $needZip = (-not (Test-Path $patchedPath)) -and (-not (Test-Path $zipPath))

    if ($needExe)   { Write-Host "  缂哄け: ${ExeFileName}" -ForegroundColor Yellow }  else { Write-Host "  瀛樺湪: ${ExeFileName}" -ForegroundColor Green }
    if ($needZip)   { Write-Host "  缂哄け: ${ZipFileName}(鎴?app.asar.patched)" -ForegroundColor Yellow }
    elseif (-not (Test-Path $patchedPath)) { Write-Host "  瀛樺湪: ${ZipFileName}" -ForegroundColor Green }
    else                                   { Write-Host "  瀛樺湪: app.asar.patched" -ForegroundColor Green }

    if (-not $needExe -and -not $needZip) {
        Write-Step "涓嬭浇" "鎵€鏈夎祫浜ф枃浠跺凡瀛樺湪銆?
        return
    }

    if (-not $Yes) {
        Write-Host ""
        Write-Host "[纭] 灏嗚嚜鍔ㄤ笅杞界己澶辨枃浠讹紝鏄惁缁х画锛?y/N): " -NoNewline
        $answer = Read-Host
        if ($answer -notin @('y', 'Y', 'yes', 'YES')) {
            Write-Host "[鍙栨秷] 鐢ㄦ埛鍙栨秷浜嗕笅杞姐€?
            Show-ManualDownloadGuide
            exit 1
        }
    }

    Write-Step "涓嬭浇" "寮€濮嬩笅杞?.."
    $oldPp = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    if ($needExe) {
        Write-Step "涓嬭浇" "姝ｅ湪涓嬭浇 ${ExeFileName}..."
        if (-not (Download-File -Url "${ReleaseBase}${ExeFileName}" -Destination $exePath -Description $ExeFileName -ExpectedSize $ExpectedExeSize -FileName $ExeFileName)) { exit 1 }
    }

    if ($needZip) {
        Write-Step "涓嬭浇" "姝ｅ湪涓嬭浇 ${ZipFileName}..."
        if (-not (Download-File -Url "${ReleaseBase}${ZipFileName}" -Destination $zipPath -Description $ZipFileName -ExpectedSize $ExpectedZipSize -FileName $ZipFileName)) { exit 1 }
    }

    $ProgressPreference = $oldPp
    Write-Step "涓嬭浇" "鍏ㄩ儴涓嬭浇瀹屾垚銆?
}

# ---------- 鍝堝笇鏍￠獙 ----------
function Invoke-HashCheck {
    Write-Step "鏍￠獙" "姝ｅ湪鏍￠獙鏂囦欢鍝堝笇鍊?.."

    $checksumFile = "$PSScriptRoot\checksums.txt"
    if (-not (Test-Path $checksumFile)) {
        Write-Step "鏍￠獙" "鏈壘鍒?checksums.txt锛岃烦杩囧搱甯屾牎楠屻€?
        return $true
    }

    # 瑙ｆ瀽 checksums.txt(鏍煎紡: <64hex> *<filename>)
    $checksums = @{}
    Get-Content $checksumFile | ForEach-Object {
        if ($_ -match '^([a-fA-F0-9]{64})\s+\*(.+)$') {
            $checksums[$matches[2]] = $matches[1].ToLower()
        }
    }

    $allValid = $true

    # 鏍￠獙 exe
    $exePath = "$PSScriptRoot\$ExeFileName"
    if (Test-Path $exePath) {
        $hash = (Get-FileHash $exePath -Algorithm SHA256).Hash.ToLower()
        $expected = $checksums[$ExeFileName]
        Write-Step "鏍￠獙" "妫€鏌?${ExeFileName}..."
        if ($expected) {
            if ($hash -eq $expected) {
                Write-Host "  鍝堝笇鍖归厤: ${hash}" -ForegroundColor Green
            } else {
                Write-Host "  鍝堝笇涓嶅尮閰?" -ForegroundColor Red
                Write-Host "  鏈熸湜: ${expected}" -ForegroundColor Red
                Write-Host "  瀹為檯: ${hash}" -ForegroundColor Red
                $allValid = $false
            }
        } else {
            Write-Host "  鏈湪 checksums.txt 涓壘鍒?${ExeFileName} 鐨勫搱甯岋紝璺宠繃鏍￠獙銆? -ForegroundColor Yellow
        }
    }

    # 鏍￠獙 zip
    $zipPath = "$PSScriptRoot\$ZipFileName"
    if (Test-Path $zipPath) {
        $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
        $expected = $checksums[$ZipFileName]
        Write-Step "鏍￠獙" "妫€鏌?${ZipFileName}..."
        if ($expected) {
            if ($hash -eq $expected) {
                Write-Host "  鍝堝笇鍖归厤: ${hash}" -ForegroundColor Green
            } else {
                Write-Host "  鍝堝笇涓嶅尮閰?" -ForegroundColor Red
                Write-Host "  鏈熸湜: ${expected}" -ForegroundColor Red
                Write-Host "  瀹為檯: ${hash}" -ForegroundColor Red
                $allValid = $false
            }
        } else {
            Write-Host "  鏈湪 checksums.txt 涓壘鍒?${ZipFileName} 鐨勫搱甯岋紝璺宠繃鏍￠獙銆? -ForegroundColor Yellow
        }
    }

    if (-not $allValid) {
        Write-Host ""
        Write-Host "[閿欒] 鏂囦欢鍝堝笇鏍￠獙澶辫触锛佽浠?Release 閲嶆柊涓嬭浇鏂囦欢銆? -ForegroundColor Red
        Write-Host "  Release: https://github.com/Mr-cjf/opencode-patches/releases/tag/v1.17.20-patched-recovery" -ForegroundColor Cyan
        exit 1
    }

    Write-Step "鏍￠獙" "鎵€鏈夋枃浠跺搱甯屾牎楠岄€氳繃銆?
    return $true
}

# ---------- 鏁版嵁搴撲慨澶嶈仈鍔?----------
function Invoke-DatabaseFix {
    Write-Step "鏁版嵁搴? "鍑嗗淇鏁版嵁搴?time 瀛楁..."

    # 妫€娴?python
    $pythonCmd = $null
    try { $null = & python --version 2>&1; if ($LASTEXITCODE -eq 0) { $pythonCmd = "python" } } catch {}
    if (-not $pythonCmd) {
        try { $null = & python3 --version 2>&1; if ($LASTEXITCODE -eq 0) { $pythonCmd = "python3" } } catch {}
    }

    if (-not $pythonCmd) {
        Write-Host "[閿欒] 鏈壘鍒?Python銆傝鎵嬪姩杩愯: python fix-db-time-fields.py" -ForegroundColor Red
        return
    }

    $fixScript = "$PSScriptRoot\fix-db-time-fields.py"
    if (-not (Test-Path $fixScript)) {
        Write-Host "[閿欒] 鏈壘鍒颁慨澶嶈剼鏈? ${fixScript}" -ForegroundColor Red
        return
    }

    Write-Step "鏁版嵁搴? "鎵惧埌 Python锛屾墽琛?dry-run 棰勮..."

    # 鍏?dry-run 棰勮
    & $pythonCmd "$fixScript" --dry-run
    $dryRunExit = $LASTEXITCODE
    if ($dryRunExit -ne 0) {
        Write-Host "[璀﹀憡] dry-run 澶辫触(exit code: ${dryRunExit})锛岃烦杩囨暟鎹簱淇銆? -ForegroundColor Yellow
        return
    }

    # 璇㈤棶纭
    if (-not $Yes) {
        Write-Host ""
        Write-Host "[纭] 浠ヤ笂涓洪瑙堢粨鏋溿€傛槸鍚︾户缁墽琛屼慨澶嶏紵(y/N): " -NoNewline
        $answer = Read-Host
        if ($answer -notin @('y', 'Y', 'yes', 'YES')) {
            Write-Host "[鍙栨秷] 鐢ㄦ埛鍙栨秷浜嗘暟鎹簱淇銆? -ForegroundColor Yellow
            return
        }
    } else {
        Write-Step "鏁版嵁搴? "-Yes 宸叉寚瀹氾紝璺宠繃纭銆?
    }

    # 鎵ц淇
    Write-Step "鏁版嵁搴? "鎵ц淇..."
    if ($Yes) {
        & $pythonCmd "$fixScript" --yes
    } else {
        & $pythonCmd "$fixScript"
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Step "鏁版嵁搴? "鏁版嵁搴撲慨澶嶅畬鎴愩€?
    } else {
        Write-Host "[璀﹀憡] 鏁版嵁搴撲慨澶嶅紓甯?exit code: ${LASTEXITCODE})" -ForegroundColor Yellow
    }
}

# ============================================================
#  涓绘祦绋?# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   OpenCode 涓€閿仮澶嶅伐鍏?v2.0" -ForegroundColor Cyan
Write-Host "   鐩爣鐗堟湰: 1.17.20(鍚ˉ涓?" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ---- 绗?姝ワ細鑷姩涓嬭浇缂哄け璧勪骇 ----
Invoke-AutoDownload

# ---- 绗?姝ュ悗锛氬搱甯屾牎楠?----
Invoke-HashCheck

# ---------- 姝ラ 1锛氬叧闂?OpenCode ----------
Write-Step "1/6" "姝ｅ湪鍏抽棴 OpenCode 杩涚▼..."

$procs = Get-Process -Name "*opencode*" -ErrorAction SilentlyContinue
if ($procs) {
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    $remaining = Get-Process -Name "*opencode*" -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-Host "[閿欒] OpenCode 杩涚▼鏈兘瀹屽叏鍏抽棴锛岃鎵嬪姩缁撴潫鍚庨噸璇曘€? -ForegroundColor Red
        exit 1
    }
    Write-Step "1/6" "OpenCode 宸插叧闂€?
} else {
    Write-Step "1/6" "鏈娴嬪埌杩愯涓殑 OpenCode 杩涚▼銆?
}

# ---------- 姝ラ 2锛氬嵏杞藉綋鍓嶇増鏈?----------
Write-Step "2/6" "鍗歌浇褰撳墠 OpenCode 鐗堟湰..."

$uninstaller = "$env:LOCALAPPDATA\Programs\@opencode-aidesktop\Uninstall OpenCode.exe"
if (Test-Path $uninstaller) {
    Write-Step "2/6" "鎵惧埌鍗歌浇绋嬪簭锛屾鍦ㄦ墽琛岄潤榛樺嵏杞?.."
    Start-Process -Wait -FilePath $uninstaller -ArgumentList "/S" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Write-Step "2/6" "鍗歌浇瀹屾垚銆?
} else {
    Write-Step "2/6" "鏈壘鍒板嵏杞界▼搴?鍙兘宸插嵏杞芥垨鏈畨瑁?锛岀户缁笅涓€姝ャ€?
}

# ---------- 姝ラ 3锛氬畨瑁?1.17.20 ----------
Write-Step "3/6" "瀹夎 OpenCode 1.17.20..."

$installer = "$PSScriptRoot\opencode-desktop-win-x64-1.17.20.exe"
if (-not (Test-Path $installer)) {
    Write-Host "[閿欒] 瀹夎鍖呬笉瀛樺湪: ${installer}" -ForegroundColor Red
    exit 1
}

Write-Step "3/6" "姝ｅ湪杩愯瀹夎绋嬪簭(闈欓粯妯″紡)..."
Start-Process -Wait -FilePath $installer -ArgumentList "/S" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Write-Step "3/6" "瀹夎瀹屾垚銆?

# ---------- 姝ラ 4锛氬簲鐢ㄨˉ涓?asar ----------
Write-Step "4/6" "搴旂敤琛ヤ竵 app.asar..."

$resourcesDir = "$env:LOCALAPPDATA\Programs\@opencode-aidesktop\resources"
$targetAsar = "$resourcesDir\app.asar"

$patchedFile = "$PSScriptRoot\app.asar.patched"
$zipFile = "$PSScriptRoot\app.asar.patched.zip"

if (-not (Test-Path $resourcesDir)) {
    Write-Host "[閿欒] 鏈壘鍒?OpenCode 璧勬簮鐩綍: ${resourcesDir}" -ForegroundColor Red
    exit 1
}

if ((-not (Test-Path $patchedFile)) -and (Test-Path $zipFile)) {
    Write-Step "4/6" "瑙ｅ帇 app.asar.patched.zip..."
    Expand-Archive -Path $zipFile -DestinationPath "$PSScriptRoot" -Force -ErrorAction SilentlyContinue
    $patchedFile = "$PSScriptRoot\app.asar.patched"
}

if (-not (Test-Path $patchedFile)) {
    Write-Host "[閿欒] 鏈壘鍒拌ˉ涓佹枃浠?app.asar.patched 鎴?app.asar.patched.zip" -ForegroundColor Red
    exit 1
}

if (Test-Path $targetAsar) {
    $backupAsar = "$targetAsar.pre-restore.bak"
    Copy-Item -Path $targetAsar -Destination $backupAsar -Force -ErrorAction SilentlyContinue
    Write-Step "4/6" "宸插浠藉師 app.asar -> app.asar.pre-restore.bak"
}

Copy-Item -Path $patchedFile -Destination $targetAsar -Force -ErrorAction SilentlyContinue
Write-Step "4/6" "琛ヤ竵宸插簲鐢ㄣ€?

# ---------- 姝ラ 5锛氬喕缁撹嚜鍔ㄥ崌绾?----------
Write-Step "5/6" "鍐荤粨鑷姩鍗囩骇..."

# 5a. 淇敼 app-update.yml
$updateYmlPath = "$resourcesDir\app-update.yml"
if (Test-Path $updateYmlPath) {
    $content = Get-Content $updateYmlPath -Raw -ErrorAction SilentlyContinue
    if ($content -match 'repo:\s*opencode') {
        Copy-Item -Path $updateYmlPath -Destination "$updateYmlPath.bak" -Force -ErrorAction SilentlyContinue
        $content = $content -replace 'repo:\s*opencode', 'repo: block-opencode-update'
        Set-Content -Path $updateYmlPath -Value $content -Force -ErrorAction SilentlyContinue
        Write-Step "5/6" "宸蹭慨鏀?app-update.yml(鍘熸枃浠跺浠戒负 .bak)"
    } else {
        Write-Step "5/6" "app-update.yml 鏃犻渶淇敼銆?
    }
} else {
    Write-Step "5/6" "app-update.yml 涓嶅瓨鍦紝璺宠繃銆?
}

# 5b. 娓呯┖ pending 鐩綍
$pendingDir = "$env:LOCALAPPDATA\@opencode-aidesktop-updater\pending"
if (Test-Path $pendingDir) {
    Remove-Item "$pendingDir\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "5/6" "宸叉竻绌哄緟鏇存柊鐩綍: ${pendingDir}"
} else {
    Write-Step "5/6" "寰呮洿鏂扮洰褰曚笉瀛樺湪锛岃烦杩囥€?
}

# 5c. 鍒犻櫎 updater 鐩綍
$updaterDir = "$env:APPDATA\ai.opencode.desktop\opencode.updater"
if (Test-Path $updaterDir) {
    Remove-Item $updaterDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "5/6" "宸插垹闄?updater: ${updaterDir}"
} else {
    Write-Step "5/6" "updater 鐩綍涓嶅瓨鍦紝璺宠繃銆?
}

# ---------- 姝ラ 6锛氭敹灏鹃獙璇?----------
Write-Step "6/6" "鏀跺熬楠岃瘉..."

$exePath = "$env:LOCALAPPDATA\Programs\@opencode-aidesktop\OpenCode.exe"
if (Test-Path $exePath) {
    try {
        $version = (Get-Item $exePath).VersionInfo.FileVersion
        Write-Step "6/6" "OpenCode 鐗堟湰: $version"
        if ($version -match '1\.17\.20') {
            Write-Host "[瀹屾垚] 鎭㈠鎴愬姛锛佸綋鍓嶇増鏈负 ${version}" -ForegroundColor Green
        } else {
            Write-Host "[璀﹀憡] 鐗堟湰涓嶅尮閰?鏈熸湜 1.17.20锛屽疄闄?${version})锛岃妫€鏌ュ畨瑁呮楠ゃ€? -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[璀﹀憡] 鏃犳硶璇诲彇鐗堟湰淇℃伅銆? -ForegroundColor Yellow
    }
} else {
    Write-Host "[璀﹀憡] 鏈壘鍒?OpenCode.exe锛屽畨瑁呭彲鑳芥湭鎴愬姛銆? -ForegroundColor Yellow
}

# ---------- 鏁版嵁搴撲慨澶?-FixDatabase 鏃? ----------
if ($FixDatabase) {
    Write-Host ""
    Write-Step "DB" "妫€娴嬪埌 -FixDatabase 鍙傛暟锛岃繘鍏ユ暟鎹簱淇娴佺▼..."
    Invoke-DatabaseFix
}

Write-Host ""
Write-Host "===== 涓嬩竴姝?=====" -ForegroundColor Cyan
Write-Host "鍚姩 OpenCode 楠岃瘉锛?
Write-Host "  1. 宸ヤ綔鍖哄彲鐢?
Write-Host "  2. 澶?diffs 浼氳瘽涓嶅崱椤?
Write-Host "  3. 鏇存柊妫€鏌ヨ繑鍥?404(琚樆鏂?"
Write-Host "  4. 濡傞亣鍒?reading time 宕╂簝锛岃繍琛?fix-db-time-fields.py 淇鏁版嵁搴?
Write-Host ""

if ($script:ExitCode -ne 0) {
    exit $script:ExitCode
}