# Glider 8443端口防火墙管理脚本
# 用途：管理8443端口的访问权限，只允许特定IP访问

# 规则名称常量
$RULE_BASE_NAME = "Glider-8443"
$BLOCK_RULE_NAME = "$RULE_BASE_NAME-Block-All"
$LOCAL_RULE_NAME = "$RULE_BASE_NAME-Allow-Local"

# 保存已允许IP的文件路径
$allowedIPsFilePath = Join-Path $PSScriptRoot "allowed_ips.txt"

# 检查是否以管理员权限运行
function Check-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host "Please run this script as administrator!" -ForegroundColor Red
        exit
    }
}

# 获取当前IP地址
function Get-CurrentIP {
    $ipAddresses = Get-NetIPAddress | Where-Object {
        $_.AddressFamily -eq "IPv4" -and 
        $_.PrefixOrigin -ne "WellKnown" -and
        $_.IPAddress -ne "127.0.0.1"
    }
    
    # 如果找到多个IP，显示选择菜单
    if ($ipAddresses.Count -gt 1) {
        Write-Host "Multiple IP addresses detected, please select one:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $ipAddresses.Count; $i++) {
            Write-Host "[$i] $($ipAddresses[$i].IPAddress) (Interface: $($ipAddresses[$i].InterfaceAlias))"
        }
        
        $choice = Read-Host "Enter your choice"
        $selectedIP = $ipAddresses[$choice].IPAddress
    } else {
        $selectedIP = $ipAddresses[0].IPAddress
    }
    
    return $selectedIP
}

# 初始化防火墙规则
function Initialize-FirewallRules {
    # 检查是否已存在阻止规则，如果不存在则创建
    $blockRule = Get-NetFirewallRule -DisplayName $BLOCK_RULE_NAME -ErrorAction SilentlyContinue
    if (-not $blockRule) {
        Write-Host "Creating rule to block all IPs from accessing port 8443..." -ForegroundColor Yellow
        New-NetFirewallRule -DisplayName $BLOCK_RULE_NAME -Direction Inbound -LocalPort 8443 -Protocol TCP -Action Block | Out-Null
    }
    
    # 检查是否已存在本地访问规则，如果不存在则创建
    $localRule = Get-NetFirewallRule -DisplayName $LOCAL_RULE_NAME -ErrorAction SilentlyContinue
    if (-not $localRule) {
        Write-Host "Creating rule to allow local access to port 8443..." -ForegroundColor Yellow
        New-NetFirewallRule -DisplayName $LOCAL_RULE_NAME -Direction Inbound -LocalPort 8443 -Protocol TCP -RemoteAddress 127.0.0.1 -Action Allow | Out-Null
    }
}

# 添加当前IP到防火墙允许规则
function Add-CurrentIPToFirewall {
    $currentIP = Get-CurrentIP
    $ruleName = "$RULE_BASE_NAME-Allow-IP-$currentIP"
    
    # 检查是否已存在针对当前IP的规则
    $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    
    if ($existingRule) {
        Write-Host "IP $currentIP is already in the allowed list" -ForegroundColor Green
    } else {
        Write-Host "Adding IP $currentIP to firewall allowed list..." -ForegroundColor Yellow
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort 8443 -Protocol TCP -RemoteAddress $currentIP -Action Allow | Out-Null
        
        # 保存IP到文件
        if (-not (Test-Path $allowedIPsFilePath)) {
            New-Item -Path $allowedIPsFilePath -ItemType File -Force | Out-Null
        }
        
        Add-Content -Path $allowedIPsFilePath -Value "$currentIP,$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" -Force
        
        Write-Host "IP $currentIP has been added to the allowed list" -ForegroundColor Green
    }
}

# 显示所有允许的IP
function Show-AllowedIPs {
    $rules = Get-NetFirewallRule -DisplayName "$RULE_BASE_NAME-Allow-IP-*" | Where-Object { $_.Enabled -eq $true }
    
    if ($rules.Count -eq 0) {
        Write-Host "No IPs in the allowed list currently" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Currently allowed IPs:" -ForegroundColor Cyan
    $i = 1
    
    foreach ($rule in $rules) {
        $ipAddress = $rule.DisplayName -replace "$RULE_BASE_NAME-Allow-IP-", ""
        $addedTime = "Unknown time"
        
        # 如果有记录文件，尝试查找添加时间
        if (Test-Path $allowedIPsFilePath) {
            $ipRecord = Get-Content $allowedIPsFilePath | Where-Object { $_ -match "^$ipAddress," }
            if ($ipRecord) {
                $addedTime = ($ipRecord -split ",")[1]
            }
        }
        
        Write-Host "[$i] $ipAddress (Added: $addedTime)"
        $i++
    }
}

# 删除IP规则
function Remove-IPRule {
    $rules = Get-NetFirewallRule -DisplayName "$RULE_BASE_NAME-Allow-IP-*" | Where-Object { $_.Enabled -eq $true }
    
    if ($rules.Count -eq 0) {
        Write-Host "No IPs in the allowed list currently" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Select IP to remove:" -ForegroundColor Cyan
    $ipList = @()
    $i = 1
    
    foreach ($rule in $rules) {
        $ipAddress = $rule.DisplayName -replace "$RULE_BASE_NAME-Allow-IP-", ""
        $ipList += $ipAddress
        Write-Host "[$i] $ipAddress"
        $i++
    }
    
    $choice = Read-Host "Enter the number of the IP to remove (or 'all' to remove all)"
    
    if ($choice -eq "all") {
        foreach ($rule in $rules) {
            Remove-NetFirewallRule -DisplayName $rule.DisplayName
            Write-Host "Removed rule: $($rule.DisplayName)" -ForegroundColor Yellow
        }
        
        # 清空IP记录文件
        if (Test-Path $allowedIPsFilePath) {
            Clear-Content $allowedIPsFilePath
        }
        
        Write-Host "All IP rules have been removed" -ForegroundColor Green
    } else {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $ipList.Count) {
            $ipToRemove = $ipList[$index]
            $ruleToRemove = "$RULE_BASE_NAME-Allow-IP-$ipToRemove"
            
            Remove-NetFirewallRule -DisplayName $ruleToRemove
            
            # 从文件中移除记录
            if (Test-Path $allowedIPsFilePath) {
                $content = Get-Content $allowedIPsFilePath | Where-Object { $_ -notmatch "^$ipToRemove," }
                Set-Content -Path $allowedIPsFilePath -Value $content -Force
            }
            
            Write-Host "Removed IP: $ipToRemove" -ForegroundColor Green
        } else {
            Write-Host "Invalid selection" -ForegroundColor Red
        }
    }
}

# 主菜单
function Show-Menu {
    Write-Host "`n===== Glider Port 8443 Firewall Manager =====" -ForegroundColor Cyan
    Write-Host "1. Add current IP to allowed list"
    Write-Host "2. View all allowed IPs"
    Write-Host "3. Remove IP rule"
    Write-Host "4. Exit"
    Write-Host "=================================" -ForegroundColor Cyan
    
    $choice = Read-Host "Enter your choice (1-4)"
    
    switch ($choice) {
        "1" { Add-CurrentIPToFirewall; Show-Menu }
        "2" { Show-AllowedIPs; Show-Menu }
        "3" { Remove-IPRule; Show-Menu }
        "4" { exit }
        default { Write-Host "Invalid option, please try again" -ForegroundColor Red; Show-Menu }
    }
}

# 脚本主函数
function Main {
    Check-Admin
    Initialize-FirewallRules
    Show-Menu
}

# 执行主函数
Main