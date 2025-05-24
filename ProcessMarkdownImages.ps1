param(
    [Parameter(Mandatory=$true)]
    [string]$TargetDir
)

<#
.SYNOPSIS
    处理Markdown文件中的图片，将网络图片下载到本地，整理本地图片到assets文件夹

.DESCRIPTION
    此脚本会：
    1. 备份现有的assets文件夹
    2. 处理所有Markdown文件中的图片引用
    3. 下载网络图片到本地assets文件夹
    4. 复制本地图片到assets文件夹
    5. 更新Markdown文件中的图片路径引用
    6. 处理文件重名问题，确保文件唯一性

.PARAMETER TargetDir
    要处理的目标目录路径

.EXAMPLE
    .\ProcessMarkdownImages.ps1 -TargetDir "C:\MyMarkdownFiles"
#>

# ================================
# 全局变量定义
# ================================

# 文件重命名映射表，用于跟踪重命名的文件
$script:fileRenameMap = @{}

# ================================
# 核心功能函数
# ================================

<#
.SYNOPSIS
    下载网络图片到本地文件系统

.DESCRIPTION
    使用Invoke-WebRequest下载指定URL的图片到目标路径
    包含错误处理和状态输出

.PARAMETER Url
    要下载的图片URL地址

.PARAMETER Dest
    图片保存的目标路径

.EXAMPLE
    Download-Image -Url "https://example.com/image.jpg" -Dest "C:\images\image.jpg"
#>
function Download-Image {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [Parameter(Mandatory=$true)]
        [string]$Dest
    )
    
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -ErrorAction Stop
        Write-Host "下载图片成功: $Url" -ForegroundColor Green
    } catch {
        Write-Warning "下载失败: $Url - 错误: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    生成唯一的文件名以避免文件重名冲突

.DESCRIPTION
    当目标文件夹中已存在同名文件时，此函数会：
    1. 首先检查文件是否存在
    2. 如果存在且提供了源文件路径，则比较文件内容（MD5哈希）
    3. 如果内容相同，返回原始文件名
    4. 如果内容不同或无法比较，生成带时间戳和随机数的新文件名

.PARAMETER AssetsDir
    目标assets文件夹路径

.PARAMETER OriginalFileName
    原始文件名

.PARAMETER SourceFilePath
    源文件路径，用于内容比较（可选）

.RETURNS
    string - 唯一的文件名

.EXAMPLE
    $uniqueName = Get-UniqueFileName -AssetsDir "C:\assets" -OriginalFileName "image.jpg" -SourceFilePath "C:\temp\image.jpg"
#>
function Get-UniqueFileName {
    param(
        [Parameter(Mandatory=$true)]
        [string]$AssetsDir,
        [Parameter(Mandatory=$true)]
        [string]$OriginalFileName,
        [Parameter(Mandatory=$false)]
        [string]$SourceFilePath = $null
    )
    
    $fullPath = Join-Path $AssetsDir $OriginalFileName
    
    # 如果文件不存在，直接返回原始文件名
    if (-not (Test-Path $fullPath)) {
        return $OriginalFileName
    }
    
    # 如果提供了源文件路径，比较文件内容
    if ($null -ne $SourceFilePath -and (Test-Path $SourceFilePath)) {
        try {
            # 使用MD5哈希值比较文件内容
            $existingFileHash = Get-FileHash -Path $fullPath -Algorithm MD5
            $sourceFileHash = Get-FileHash -Path $SourceFilePath -Algorithm MD5
            
            if ($existingFileHash.Hash -eq $sourceFileHash.Hash) {
                Write-Host "文件内容相同，无需重复保存: $OriginalFileName" -ForegroundColor Yellow
                return $OriginalFileName
            } else {
                Write-Host "文件重名但内容不同，需要重命名: $OriginalFileName" -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "无法比较文件内容，将进行重命名: $OriginalFileName - 错误: $($_.Exception.Message)"
        }
    }
    
    # 生成新的唯一文件名
    $fileExtension = [System.IO.Path]::GetExtension($OriginalFileName)
    $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFileName)
    
    # 生成时间戳（时分秒毫秒）+ 随机数后缀
    $timestamp = Get-Date -Format "HHmmssff"  # 8位时间戳
    $randomNum = Get-Random -Minimum 10 -Maximum 99  # 2位随机数
    $suffix = "$timestamp$randomNum"
    
    $newFileName = "$fileNameWithoutExt`_$suffix$fileExtension"
    
    Write-Host "文件重名，生成新文件名: $OriginalFileName -> $newFileName" -ForegroundColor Cyan
    return $newFileName
}

<#
.SYNOPSIS
    备份现有的assets文件夹

.DESCRIPTION
    在处理图片之前，将现有的assets文件夹备份到带日期的备份文件夹中
    如果备份文件夹已存在，会自动添加序号确保唯一性

.PARAMETER TargetDir
    目标目录路径

.RETURNS
    hashtable - 包含备份信息的哈希表
    - BackupDir: 备份文件夹路径（如果没有备份则为null）
    - AssetsDir: assets文件夹路径
    - RelativeFolderName: 备份文件夹的相对名称
#>
function Backup-AssetsFolder {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetDir
    )
    
    $assetsDir = Join-Path $TargetDir "assets"
    $backupFolderName = "assets_bak_" + (Get-Date -Format "yyyyMMdd")
    $backupDir = Join-Path $TargetDir $backupFolderName
    
    $result = @{
        BackupDir = $null
        AssetsDir = $assetsDir
        RelativeFolderName = $null
    }
    
    if (Test-Path $assetsDir) {
        # 确保备份文件夹名称唯一
        $counter = 1
        $originalBackupDir = $backupDir
        while (Test-Path $backupDir) {
            $backupDir = "$originalBackupDir`_$counter"
            $counter++
        }
        
        # 创建备份文件夹并移动文件
        New-Item -Path $backupDir -ItemType Directory | Out-Null
        Write-Host "创建备份文件夹: $backupDir" -ForegroundColor Green
        
        # 移动所有文件到备份文件夹
        Get-ChildItem -Path $assetsDir | Move-Item -Destination $backupDir
        Write-Host "已将assets文件夹内容移动到备份文件夹" -ForegroundColor Green
        
        $result.BackupDir = $backupDir
        $result.RelativeFolderName = Split-Path $backupDir -Leaf
    } else {
        # 创建新的assets文件夹
        New-Item -Path $assetsDir -ItemType Directory | Out-Null
        Write-Host "创建assets文件夹: $assetsDir" -ForegroundColor Green
    }
    
    return $result
}

<#
.SYNOPSIS
    更新Markdown文件中的图片路径引用

.DESCRIPTION
    将Markdown文件中指向assets的图片路径更新为指向备份文件夹的路径

.PARAMETER TargetDir
    目标目录路径

.PARAMETER RelativeFolderName
    备份文件夹的相对名称
#>
function Update-MarkdownImagePaths {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetDir,
        [Parameter(Mandatory=$true)]
        [string]$RelativeFolderName
    )
    
    $mdFiles = Get-ChildItem -Path $TargetDir -Filter *.md
    
    foreach ($mdFile in $mdFiles) {
        # 使用UTF8编码读取文件内容
        $content = Get-Content $mdFile.FullName -Raw -Encoding UTF8
        
        # 匹配并替换图片路径：![alt](assets/xxx) -> ![alt](backup_folder/xxx)
        $pattern = '!\[(.*?)\]\(assets/(.*?)\)'
        $replacement = '![$1](' + $RelativeFolderName + '/$2)'
        $newContent = $content -replace $pattern, $replacement
        
        if ($content -ne $newContent) {
            # 保存修改后的内容
            Set-Content -Path $mdFile.FullName -Value $newContent -Encoding UTF8
            Write-Host "已更新Markdown文件中的图片引用路径: $($mdFile.Name)" -ForegroundColor Green
        }
    }
}

<#
.SYNOPSIS
    将备份文件夹中的图片复制回assets文件夹

.DESCRIPTION
    处理备份文件夹中的所有图片文件，检查重名并复制到assets文件夹
    同时更新文件重命名映射表

.PARAMETER BackupDir
    备份文件夹路径

.PARAMETER AssetsDir
    assets文件夹路径
#>
function Restore-ImagesFromBackup {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupDir,
        [Parameter(Mandatory=$true)]
        [string]$AssetsDir
    )
    
    Write-Host "将备份文件夹中的图片复制到assets文件夹..." -ForegroundColor Cyan
    $backupImages = Get-ChildItem -Path $BackupDir -File
    
    foreach ($img in $backupImages) {
        # 检查文件重名并生成唯一文件名
        $uniqueImgName = Get-UniqueFileName -AssetsDir $AssetsDir -OriginalFileName $img.Name -SourceFilePath $img.FullName
        $targetPath = Join-Path $AssetsDir $uniqueImgName
        
        # 记录文件重命名映射关系
        $script:fileRenameMap[$img.Name] = $uniqueImgName
        
        # 根据是否需要重命名来决定复制策略
        if ($img.Name -eq $uniqueImgName) {
            # 文件名相同，检查是否需要复制
            if (-not (Test-Path $targetPath)) {
                Copy-Item -Path $img.FullName -Destination $targetPath -Force
                Write-Host "已复制图片: $($img.Name) 到 assets 文件夹" -ForegroundColor Green
            } else {
                Write-Host "文件已存在且内容相同，跳过复制: $($img.Name)" -ForegroundColor Yellow
            }
        } else {
            # 文件名不同，需要复制并重命名
            Copy-Item -Path $img.FullName -Destination $targetPath -Force
            Write-Host "已复制图片（重命名）: $($img.Name) -> $uniqueImgName 到 assets 文件夹" -ForegroundColor Green
        }
    }
}

<#
.SYNOPSIS
    处理单个Markdown文件中的所有图片

.DESCRIPTION
    扫描Markdown文件中的所有图片引用，下载网络图片或复制本地图片到assets文件夹
    并更新文件中的图片路径引用

.PARAMETER MdFile
    要处理的Markdown文件对象

.PARAMETER AssetsDir
    assets文件夹路径

.PARAMETER BackupRelativeName
    备份文件夹的相对名称（可选）

.RETURNS
    int - 处理的图片数量
#>
function Process-MarkdownFile {
    param(
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$MdFile,
        [Parameter(Mandatory=$true)]
        [string]$AssetsDir,
        [Parameter(Mandatory=$false)]
        [string]$BackupRelativeName = $null
    )
    
    $dir = Split-Path $MdFile.FullName
    
    # 确保assets文件夹存在
    if (-not (Test-Path $AssetsDir)) {
        New-Item -Path $AssetsDir -ItemType Directory | Out-Null
    }

    # 使用UTF8编码读取文件内容
    $content = Get-Content $MdFile.FullName -Raw -Encoding UTF8
    
    # 匹配所有图片：![alt](url) 格式
    $imgPattern = '!\[(.*?)\]\((.*?)\)'
    $matches = [regex]::Matches($content, $imgPattern)
    
    # 存储需要替换的图片信息
    $replaceMap = @{}
    
    foreach ($match in $matches) {
        $imgUrl = $match.Groups[2].Value
        
        # 处理备份文件夹中的图片引用
        if ($null -ne $BackupRelativeName -and $imgUrl -match "^$([regex]::Escape($BackupRelativeName))/(.*?)$") {
            $originalImgName = $Matches[1]
            
            # 检查是否有重命名映射
            $actualImgName = if ($script:fileRenameMap.ContainsKey($originalImgName)) {
                $script:fileRenameMap[$originalImgName]
            } else {
                $originalImgName
            }
            
            $assetsPath = "assets/$actualImgName"
            $oldStr = $match.Value
            $newStr = $oldStr -replace [regex]::Escape($imgUrl), $assetsPath
            $replaceMap[$oldStr] = $newStr
            continue
        }
        
        # 跳过已经指向assets的图片
        if ($imgUrl -match '^assets/') {
            continue
        }
        
        # 处理图片文件名
        $imgName = [System.IO.Path]::GetFileName(($imgUrl -split '\?')[0])
        if ([string]::IsNullOrEmpty($imgName)) {
            $imgName = "image_" + [guid]::NewGuid().ToString().Substring(0, 8) + ".jpg"
        }
        
        $assetsPath = $null
        
        if ($imgUrl -match '^https?://') {
            # 处理网络图片
            $assetsPath = Process-NetworkImage -ImageUrl $imgUrl -ImageName $imgName -AssetsDir $AssetsDir
        } else {
            # 处理本地图片
            $assetsPath = Process-LocalImage -ImageUrl $imgUrl -ImageName $imgName -AssetsDir $AssetsDir -BaseDir $dir
        }
        
        # 如果处理成功，记录替换信息
        if ($null -ne $assetsPath) {
            $oldStr = $match.Value
            $newStr = $oldStr -replace [regex]::Escape($imgUrl), $assetsPath
            $replaceMap[$oldStr] = $newStr
        }
    }
    
    # 统一替换所有图片路径
    if ($replaceMap.Count -gt 0) {
        $newContent = $content
        foreach ($oldStr in $replaceMap.Keys) {
            $newContent = $newContent.Replace($oldStr, $replaceMap[$oldStr])
        }
        
        # 保存修改后的内容
        Set-Content -Path $MdFile.FullName -Value $newContent -Encoding UTF8
        Write-Host "处理完成: $($MdFile.FullName) (更新了 $($replaceMap.Count) 个图片路径)" -ForegroundColor Green
    } else {
        Write-Host "处理完成: $($MdFile.FullName) (没有需要更新的图片路径)" -ForegroundColor Yellow
    }
    
    return $replaceMap.Count
}

<#
.SYNOPSIS
    处理网络图片

.DESCRIPTION
    下载网络图片到临时位置，检查重名后移动到assets文件夹

.PARAMETER ImageUrl
    图片URL地址

.PARAMETER ImageName
    图片文件名

.PARAMETER AssetsDir
    assets文件夹路径

.RETURNS
    string - 处理后的图片相对路径，失败时返回null
#>
function Process-NetworkImage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ImageUrl,
        [Parameter(Mandatory=$true)]
        [string]$ImageName,
        [Parameter(Mandatory=$true)]
        [string]$AssetsDir
    )
    
    # 创建临时文件
    $tempFile = [System.IO.Path]::GetTempFileName()
    $tempFileWithExt = $tempFile + [System.IO.Path]::GetExtension($ImageName)
    
    try {
        # 下载到临时文件
        Invoke-WebRequest -Uri $ImageUrl -OutFile $tempFileWithExt -ErrorAction Stop
        
        # 检查文件重名并生成唯一文件名
        $uniqueImgName = Get-UniqueFileName -AssetsDir $AssetsDir -OriginalFileName $ImageName -SourceFilePath $tempFileWithExt
        $assetsPath = "assets/$uniqueImgName"
        $fullAssetsPath = Join-Path $AssetsDir $uniqueImgName
        
        # 根据是否需要重命名来决定处理策略
        if ($ImageName -eq $uniqueImgName) {
            if (-not (Test-Path $fullAssetsPath)) {
                Move-Item -Path $tempFileWithExt -Destination $fullAssetsPath -Force
                Write-Host "下载图片成功: $ImageUrl -> $uniqueImgName" -ForegroundColor Green
            } else {
                Write-Host "网络图片已存在且内容相同，跳过下载: $ImageUrl" -ForegroundColor Yellow
                Remove-Item -Path $tempFileWithExt -Force -ErrorAction SilentlyContinue
            }
        } else {
            Move-Item -Path $tempFileWithExt -Destination $fullAssetsPath -Force
            Write-Host "下载图片成功（重命名）: $ImageUrl -> $uniqueImgName" -ForegroundColor Green
        }
        
        return $assetsPath
        
    } catch {
        Write-Warning "下载失败: $ImageUrl - 错误: $($_.Exception.Message)"
        return $null
    } finally {
        # 清理临时文件
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempFileWithExt -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    处理本地图片

.DESCRIPTION
    复制本地图片到assets文件夹，处理重名问题

.PARAMETER ImageUrl
    图片相对或绝对路径

.PARAMETER ImageName
    图片文件名

.PARAMETER AssetsDir
    assets文件夹路径

.PARAMETER BaseDir
    Markdown文件所在目录（用于解析相对路径）

.RETURNS
    string - 处理后的图片相对路径，失败时返回null
#>
function Process-LocalImage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ImageUrl,
        [Parameter(Mandatory=$true)]
        [string]$ImageName,
        [Parameter(Mandatory=$true)]
        [string]$AssetsDir,
        [Parameter(Mandatory=$true)]
        [string]$BaseDir
    )
    
    # 解析图片的绝对路径
    $absImgPath = if ([System.IO.Path]::IsPathRooted($ImageUrl)) { 
        $ImageUrl 
    } else { 
        Join-Path $BaseDir $ImageUrl 
    }
    
    if (Test-Path $absImgPath) {
        # 检查文件重名并生成唯一文件名
        $uniqueImgName = Get-UniqueFileName -AssetsDir $AssetsDir -OriginalFileName $ImageName -SourceFilePath $absImgPath
        $assetsPath = "assets/$uniqueImgName"
        $fullAssetsPath = Join-Path $AssetsDir $uniqueImgName
        
        # 根据是否需要重命名来决定处理策略
        if ($ImageName -eq $uniqueImgName) {
            if (-not (Test-Path $fullAssetsPath)) {
                Copy-Item -Path $absImgPath -Destination $fullAssetsPath -Force
                Write-Host "已复制本地图片: $absImgPath -> $fullAssetsPath" -ForegroundColor Green
            } else {
                Write-Host "本地图片已存在且内容相同，跳过复制: $absImgPath" -ForegroundColor Yellow
            }
        } else {
            Copy-Item -Path $absImgPath -Destination $fullAssetsPath -Force
            Write-Host "已复制本地图片（重命名）: $absImgPath -> $fullAssetsPath" -ForegroundColor Green
        }
        
        return $assetsPath
    } else {
        Write-Warning "本地图片未找到: $absImgPath"
        return $null
    }
}

<#
.SYNOPSIS
    最终更新所有引用备份文件夹的图片路径

.DESCRIPTION
    遍历所有Markdown文件，将引用备份文件夹的图片路径更新为assets路径
    考虑文件重命名映射

.PARAMETER TargetDir
    目标目录路径

.PARAMETER RelativeFolderName
    备份文件夹的相对名称
#>
function Update-BackupReferences {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetDir,
        [Parameter(Mandatory=$true)]
        [string]$RelativeFolderName
    )
    
    Write-Host "更新所有引用备份文件夹的图片路径..." -ForegroundColor Cyan
    $mdFiles = Get-ChildItem -Path $TargetDir -Filter *.md
    
    foreach ($mdFile in $mdFiles) {
        # 使用UTF8编码读取文件内容
        $content = Get-Content $mdFile.FullName -Raw -Encoding UTF8
        $newContent = $content
        
        # 匹配备份文件夹中的图片引用
        $pattern = '!\[(.*?)\]\(' + [regex]::Escape($RelativeFolderName) + '/(.*?)\)'
        $matches = [regex]::Matches($content, $pattern)
        
        foreach ($match in $matches) {
            $originalImgName = $match.Groups[2].Value
            
            # 检查是否有重命名映射
            $actualImgName = if ($script:fileRenameMap.ContainsKey($originalImgName)) {
                $script:fileRenameMap[$originalImgName]
            } else {
                $originalImgName
            }
            
            $oldStr = $match.Value
            $altText = $match.Groups[1].Value
            $newStr = "![$altText](assets/$actualImgName)"
            $newContent = $newContent.Replace($oldStr, $newStr)
        }
        
        if ($content -ne $newContent) {
            # 保存修改后的内容
            Set-Content -Path $mdFile.FullName -Value $newContent -Encoding UTF8
            Write-Host "已更新引用备份文件夹的图片路径: $($mdFile.Name)" -ForegroundColor Green
        }
    }
}

# ================================
# 主程序执行流程
# ================================

Write-Host "开始处理Markdown文件图片..." -ForegroundColor Cyan
Write-Host "目标目录: $TargetDir" -ForegroundColor Cyan

try {
    # 第一步：备份现有的assets文件夹
    Write-Host "`n=== 第一步：备份assets文件夹 ===" -ForegroundColor Magenta
    $backupInfo = Backup-AssetsFolder -TargetDir $TargetDir
    
    # 第二步：如果有备份，更新Markdown文件中的图片路径引用
    if ($null -ne $backupInfo.BackupDir) {
        Write-Host "`n=== 第二步：更新Markdown文件中的图片引用路径 ===" -ForegroundColor Magenta
        Update-MarkdownImagePaths -TargetDir $TargetDir -RelativeFolderName $backupInfo.RelativeFolderName
        
        # 第三步：将备份文件夹中的图片复制回assets文件夹
        Write-Host "`n=== 第三步：恢复备份图片到assets文件夹 ===" -ForegroundColor Magenta
        Restore-ImagesFromBackup -BackupDir $backupInfo.BackupDir -AssetsDir $backupInfo.AssetsDir
    }
    
    # 第四步：处理所有Markdown文件中的图片
    Write-Host "`n=== 第四步：处理Markdown文件中的图片 ===" -ForegroundColor Magenta
    $mdFiles = Get-ChildItem -Path $TargetDir -Filter *.md
    $totalProcessed = 0
    
    foreach ($mdFile in $mdFiles) {
        $processed = Process-MarkdownFile -MdFile $mdFile -AssetsDir $backupInfo.AssetsDir -BackupRelativeName $backupInfo.RelativeFolderName
        $totalProcessed += $processed
    }
    
    # 第五步：最终更新所有引用备份文件夹的图片路径
    if ($null -ne $backupInfo.BackupDir) {
        Write-Host "`n=== 第五步：最终更新备份文件夹引用 ===" -ForegroundColor Magenta
        Update-BackupReferences -TargetDir $TargetDir -RelativeFolderName $backupInfo.RelativeFolderName
    }
    
    # 输出处理结果统计
    Write-Host "`n=== 处理完成 ===" -ForegroundColor Green
    Write-Host "处理的Markdown文件数量: $($mdFiles.Count)" -ForegroundColor Green
    Write-Host "处理的图片数量: $totalProcessed" -ForegroundColor Green
    if ($null -ne $backupInfo.BackupDir) {
        Write-Host "备份文件夹: $($backupInfo.RelativeFolderName)" -ForegroundColor Green
    }
    Write-Host "Assets文件夹: $($backupInfo.AssetsDir)" -ForegroundColor Green
    
} catch {
    Write-Error "处理过程中发生错误: $($_.Exception.Message)"
    Write-Error "错误位置: $($_.InvocationInfo.ScriptLineNumber) 行"
    exit 1
}

Write-Host "`n全部处理完成！" -ForegroundColor Green
