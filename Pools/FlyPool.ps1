﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Wallets,
    [PSCustomObject]$Params,
    [alias("WorkerName")]
    [String]$Worker,
    [TimeSpan]$StatSpan,
    [String]$DataWindow = "estimate_current",
    [Bool]$InfoOnly = $false,
    [Bool]$AllowZero = $false,
    [String]$StatAverage = "Minute_10"
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

[hashtable]$Pool_RegionsTable = @{}
@("eu","us","asia") | Foreach-Object {$Pool_RegionsTable.$_ = Get-Region $_}

$Pools_Data = @(
    [PSCustomObject]@{regions = @("asia","eu","us"); host = "1-zcash.flypool.org"; rpc = "api-zcash.flypool.org"; coin = "Zcash"; algo = "Equihash";     symbol = "ZEC"; port = @(3333,3443); fee = 1; divisor = 1}
    [PSCustomObject]@{regions = @("asia","eu","us"); host = "1-ycash.flypool.org"; rpc = "api-ycash.flypool.org"; coin = "Ycash"; algo = "Equihash24x7"; symbol = "YEC"; port = @(3333,3443); fee = 1; divisor = 1}
)

$Pool_Currencies = $Pools_Data.symbol | Select-Object -Unique | Where-Object {$Wallets.$_ -or $InfoOnly}
if (-not $Pool_Currencies -and -not $InfoOnly) {return}

$Pools_Data | Where-Object {$Wallets."$($_.symbol)" -or $InfoOnly} | ForEach-Object {
    $Pool_Ports = $_.port
    $Pool_Algorithm = $_.algo
    $Pool_Algorithm_Norm = Get-Algorithm $_.algo
    $Pool_Currency = $_.symbol

    $Pool_Request = [PSCustomObject]@{}

    if (-not $InfoOnly) {
        try {
            $Pool_Request = Invoke-RestMethodAsync "https://$($_.rpc)/poolStats" -tag $Name -cycletime 120
            if ($Pool_Request.status -ne "OK") {throw}
        }
        catch {
            if ($Error.Count){$Error.RemoveAt(0)}
            Write-Log -Level Warn "Pool API ($Name) has failed. "
        }

        $Stat = Set-Stat -Name "$($Name)_$($Pool_Currency)_Profit" -Value 0 -Duration $StatSpan -ChangeDetection $false -HashRate $Pool_Request.data.poolStats.hashRate -BlockRate (24*$Pool_Request.data.poolStats.blocksPerHour) -Quiet
    }
    
    if ($Pool_Algorithm_Norm -ne "Equihash" -and $Pool_Algorithm_Norm -like "Equihash*") {$Pool_Algorithm_All = @($Pool_Algorithm_Norm,"$Pool_Algorithm_Norm-$Pool_Currency")} else {$Pool_Algorithm_All = @($Pool_Algorithm_Norm)}

    $Pool_TSL = if ($Pool_Request.data.minedBlocks) {(Get-UnixTimestamp)-($Pool_Request.data.minedBlocks.time | Measure-Object -Maximum).Maximum}

    foreach($Pool_Region in $_.regions) {
        $Ssl = $false
        foreach($Pool_Port in $Pool_Ports) {
            foreach($Pool_Algorithm_Norm in $Pool_Algorithm_All) {
                [PSCustomObject]@{
                    Algorithm     = $Pool_Algorithm_Norm
                    CoinName      = $_.coin
                    CoinSymbol    = $Pool_Currency
                    Currency      = $Pool_Currency
                    Price         = 0
                    StablePrice   = 0
                    MarginOfError = 0
                    Protocol      = "stratum+$(if ($Ssl) {"ssl"} else {"tcp"})"
                    Host          = "$($Pool_Region)$($_.host)"
                    Port          = $_.port
                    User          = "$($Wallets.$Pool_Currency).{workername:$Worker}"
                    Wallet        = $Wallets.$Pool_Currency
                    Worker        = "{workername:$Worker}"
                    Pass          = "x"
                    Region        = $Pool_RegionsTable.$Pool_Region
                    SSL           = $Ssl
                    Updated       = (Get-Date).ToUniversalTime()
                    PoolFee       = $_.fee
                    DataWindow    = $DataWindow
                    Workers       = $Pool_Request.data.poolStats.workers
                    Hashrate      = $Stat.HashRate_Live
                    TSL           = $Pool_TSL
                    BLK           = $Stat.BlockRate_Average
                    WTM           = $true
                    EthMode       = if ($Pool_Algorithm_Norm -match "^(Ethash|ProgPow)") {"qtminer"} else {$null}
                }
            }
            $Ssl = $true
        }
    }
}