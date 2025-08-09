# publish htdocs to zip package
param(
    $target_ver = $null,
    [switch]$fullup
)

$wenv_root = (Resolve-Path $PSScriptRoot/../).Path

$site_root = Join-Path $wenv_root 'htdocs'

if (!$target_ver -or $target_ver -eq 'default') {
    throw 'Missing parameter: target_ver'
    return
}

function realpath($path) {
    return $Global:ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
}

Push-Location $site_root

git -C $site_root add .

# $TempBlackList = @(
#     'onlinepay'
#     'certs'
#     'vendor'
#     'password_reset'
# )

# collection files
$BackList = @(
    '.xs'
    '.vs'
    '.vscode'
    'certs/ssl'
    'certs/simdsoft-lcs1.pem'
    '.empty'
    '.gitignore'
    '360navi.txt'
    'autoload.ps1'
    'composer-setup.php'
    'composer.json'
    'composer.lock'
    'composer.phar'
    'curlinfo.php'
    'local'
    '*.log'
    'htdocs-*.zip'
    '*.md'
    '*_test.php'
    '**/gm/**'
    '**/LICENSE'
    '**/.editorconfig'
    '**/appveyor.yml'
    '**/AUTHORS'
    '**/composer.json'
    '**/sandbox/*'
    '*.map'
    '*readme.txt'
)

if($TempBlackList) {
    $BackList += $TempBlackList
}

# $FolderPermission = '100755'
$FileDefaultPermssion = '100644'

$FilePermissionMap = @{
    '.pem' = '100400'
    '.p12' = '100400'
}

$pkg_file_name = "htdocs-$target_ver.zip"
$pkg_file_path = realpath (Join-Path $site_root "../dist/$pkg_file_name")

$deleted_list = @()
$update_list = @()

if(!$fullup) {
    # modified: 
    # new file: 
    # deleted:
    $git_status = $(git status)
    foreach($line in $git_status) {
        if ($line -match 'modified: (.*)') {
            $update_list += $(Join-Path $site_root $matches[1].Trim())
        } elseif ($line -match 'new file: (.*)') {
            $update_list += $(Join-Path $site_root $matches[1].Trim())
        } elseif ($line -match 'deleted: (.*)') {
            $deleted_list += $matches[1].Trim()
        } elseif ($line -match "renamed:\s+(.*?)\s+->\s+(.*)") {
            $update_list += $matches[2].Trim()
            $deleted_list += $Matches[1].Trim()
        }
    }
} else {
    $update_list += $site_root
}

$main_pkg_compress_args = @{
    Path             = $update_list
    CompressionLevel = 'SmallestSize'
    DestinationPath  = $pkg_file_path
    RelativeBasePath = $site_root
    Exclude          = $BackList
    Prefix           = "htdocs-$target_ver"
}

function Compress-ArchiveEx() {
    param(
        $Path,
        $CompressionLevel = 'Optimal',
        $DestinationPath,
        $Exclude,
        $Prefix = '',
        $RelativeBasePath = ''
    )

    $Script:S_IFREG = 0x8000
    # $Script:S_IFDIR = 0x4000

    if ($RelativeBasePath) {
        Push-Location $RelativeBasePath
    }

    # remove old zip file
    if (Test-Path $DestinationPath -PathType Leaf) { Remove-Item $DestinationPath -ErrorAction Stop }

    #create zip file
    if (!([System.Management.Automation.PSTypeName]'System.IO.Compression').Type) {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }

    # import VersionEx
    . (Join-Path $PSScriptRoot 'extensions.ps1')

    if (([VersionEx]$PSVersionTable.PSVersion.ToString() -ge [VersionEx]'7.0') -and $IsWindows) {

        if (-not ([System.Management.Automation.PSTypeName]'UnixFileStream').Type) {
            Add-Type -TypeDefinition @"
// A hack to create unix style .zip on windows
// refers:
//  - https://github.com/dotnet/runtime/blob/main/src/libraries/System.IO.Compression/src/System/IO/Compression/ZipVersion.cs#L24
//  - https://github.com/dotnet/runtime/blob/main/src/libraries/System.IO.Compression/src/System/IO/Compression/ZipArchiveEntry.cs#L529C26-L529C50

using System.Text;
using System.IO;
using System.IO.Compression;

public class MyZipFile : ZipArchive
{
    public UnixFileStream Stream { get; set; }
    public MyZipFile(UnixFileStream stream, ZipArchiveMode mode, bool leaveOpen) : base(stream, mode, leaveOpen)
    {
        Stream = stream;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            Stream.IsDisposing = true;
        base.Dispose(disposing);
    }
}

public class UnixFileStream : FileStream
{
    internal enum ZipVersionMadeByPlatform : byte
    {
        Windows = 0,
        Unix = 3
    }

    // public const uint DirectoryFileHeaderSignatureConstant = 0x02014B50;
    // public const uint LocalFileHeaderSignatureConstant = 0x04034B50;
    int m_hints = -1;
    int m_hints2 = -1;

    public UnixFileStream(string path, FileMode mode, FileAccess access, FileShare share, int bufferSize, bool useAsync) : base(path, mode, access, share, bufferSize, useAsync)
    {
    }

    public override void WriteByte(byte value)
    {
        if (m_hints2 != -1) ++m_hints;
        if (IsDisposing)
        {
            if (m_hints != -1) ++m_hints;

            if (m_hints == 2)
            { // hint: CurrentZipPlatform:  hack set to unix
                value = (byte)ZipVersionMadeByPlatform.Unix;
            }
        }
        base.WriteByte(value);
    }

    public override void Write(byte[] array, int offset, int count)
    {
        if (IsDisposing)
        {  // hint: entryHeaderSignature
            if ((count == 4 && array[0] == 0x50 && array[1] == 0x4b && array[2] == 0x01 && array[3] == 0x02) || m_hints != -1)
                ++m_hints;

            if (m_hints == 17) // hint: filepath
            {
                var path = Encoding.UTF8.GetString(array);
                array = Encoding.UTF8.GetBytes(path.Replace('\\', '/'));
                m_hints = -1;
            }
        }

        if ((count == 4 && array[0] == 0x50 && array[1] == 0x4b && array[2] == 0x03 && array[3] == 0x04) || m_hints2 != -1)
            ++m_hints2;

        if (m_hints2 == 10) {
            var path = Encoding.UTF8.GetString(array);
            array = Encoding.UTF8.GetBytes(path.Replace('\\', '/'));
            m_hints2 = -1;
        }

        base.Write(array, offset, count);
    }

    public bool IsDisposing { set; get; } = false;

    public static ZipArchive CreateUnixZipFile(string archiveFileName)
    {
        var fs = new UnixFileStream(archiveFileName, FileMode.CreateNew, FileAccess.Write, FileShare.None, bufferSize: 0x1000, useAsync: false);
        try
        {
            return new MyZipFile(fs, ZipArchiveMode.Create, leaveOpen: false);
        }
        catch
        {
            fs.Dispose();
            throw;
        }
    }
}
"@
        }

        $archive = [UnixFileStream]::CreateUnixZipFile($DestinationPath)
    }
    else {
        $archive = [System.IO.Compression.ZipFile]::Open($DestinationPath, [System.IO.Compression.ZipArchiveMode]::Create)
    }
    $compressionLevelValue = @{
        'Optimal'       = [System.IO.Compression.CompressionLevel]::Optimal 
        'Fastest'       = [System.IO.Compression.CompressionLevel]::Fastest
        'NoCompression' = [System.IO.Compression.CompressionLevel]::NoCompression
        'SmallestSize'  = [System.IO.Compression.CompressionLevel]::SmallestSize
    }[$CompressionLevel]

    [array]$Excludes = $Exclude
    [array]$Paths = $Path
    $_is_exclude = {
        param($uxpath)
        foreach ($exclude in $Excludes) {
            if ($uxpath -like $exclude) {
                return $true
            }
        }
        return $false
    }

    $Script:total = 0

    $_zip_add = {
        param($archive, $path, $compressionLevel, $prefix)
        if (!$path.LinkType) {
            # -RelativeBasePath add in powershell 7.4 which github ci is 7.2 not support
            $rname = $(Resolve-Path -Path $path -Relative).Replace('\', '/')
            if ($rname.StartsWith('./')) { $rname = $rname.TrimStart('./') }
            $excluded = (&$_is_exclude -uxpath $rname)
            if (!$excluded) {
                if (!$path.PSIsContainer) {
                    Write-Host "a $rname"
                    # preserve unix file permissions mode
                    # refer https://github.com/PowerShell/Microsoft.PowerShell.Archive/pull/146/files
                    $uxmode = $null
                    $fileext = Split-Path $rname -Extension
                    if ($path.UnixStat) {
                        $uxmode = $path.UnixStat.Mode
                    } 
                    else {
                        if (!$fileext -or $rname.EndsWith('.sh')) {
                            $filestatus = $(git -C $site_root ls-files -s $rname)
                            if ($filestatus) {
                                $uxmode = [Convert]::ToInt32($filestatus.Split(' ')[0], 8)
                            }
                        }
                    }

                    if ($FilePermissionMap.Contains($fileext)) {
                        $uxmode = [Convert]::ToInt32($FilePermissionMap[$fileext], 8)
                    } else {
                        $uxmode = [Convert]::ToInt32($FileDefaultPermssion, 8)
                    }
		    
                    if ($prefix) { 
                        $rname = Join-Path $prefix $rname 
                    }
                    $zentry = $archive.CreateEntry($rname)
                    $zentry.ExternalAttributes = (($Script:S_IFREG -bor $uxmode) -shl 16)
                    $zentryWriter = New-Object -TypeName System.IO.BinaryWriter $zentry.Open()
                    $zentryWriter.Write([System.IO.File]::ReadAllBytes($path))
                    $zentryWriter.Flush()
                    $zentryWriter.Close()
                    
                    ++$Script:total
                }
                else {
                    $sub_paths = Get-ChildItem $path
                    foreach ($sub_path in $sub_paths) {
                        &$_zip_add $archive $sub_path $compressionLevel $prefix
                    }
                }
            }
            else {
                Write-Host "x $rname"
            }
        }
        else {
            Write-Host "x $rname, LinkType=$($Path.LinkType)"
        }
    }

    # write entries with relative paths as names
    foreach ($path in $Paths) {
        if ($path.GetType() -eq [string]) {
            $path = Get-Item $path
        }
        &$_zip_add $archive $path $compressionLevelValue $Prefix
    }

    # release zip file
    $archive.Dispose()

    if ($RelativeBasePath) {
        Pop-Location
    }

    return $Script:total
}

Write-Host "Creating main package $pkg_file_path ..."
$total = Compress-ArchiveEx @main_pkg_compress_args
$md5_digest = (Get-FileHash $pkg_file_path -Algorithm MD5).Hash
Write-Host "Create main package $pkg_file_path done, ${total} files found, MD5: $md5_digest"

if ($deleted_list) {
    $deleted_list_path = realpath (Join-Path $site_root "../dist/deleted-$target_ver.json")
    Set-Content -Path $deleted_list_path -Value $(ConvertTo-Json $deleted_list)
}

git -C $site_root commit -m "Version $target_ver"
# git -C $site_root push

Pop-Location
