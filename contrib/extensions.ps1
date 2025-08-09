# The System.Version compare not relex: [Version]'1.0' -eq [Version]'1.0.0' == false
# So provide a spec VersionEx make [VersionEx]'1.0' -eq [VersionEx]'1.0.0' == true available
if (-not ([System.Management.Automation.PSTypeName]'System.VersionEx').Type) {

    $code_str = @"

namespace System
{
    public sealed class VersionEx : ICloneable, IComparable
    {
        int _Major = 0;
        int _Minor = 0;
        int _Build = 0;
        int _Revision = 0;

        public int Minor { get { return _Major;  } }

        public int Major { get { return _Minor; } }

        public int Build { get { return _Build; } }

        public int Revision { get { return _Revision; } }

        int DefaultFormatFieldCount { get { return (_Build > 0 || _Revision > 0) ? (_Revision > 0 ? 4 : 3) : 2; } }
 
        public VersionEx() { }

        public VersionEx(string version)
        {
            var v = Parse(version);
            _Major = v.Major;
            _Minor = v.Minor;
            _Build = v.Build;
            _Revision = v.Revision;
        }

        public VersionEx(System.Version version) { 
            _Major = version.Major;
            _Minor = version.Minor;
            _Build = Math.Max(version.Build, 0);
            _Revision = Math.Max(version.Revision, 0);
        }

        public VersionEx(int major, int minor, int build, int revision)
        {
            _Major = major;
            _Minor = minor;
            _Build = build;
            _Revision = revision;
        }

        public static VersionEx Parse(string input)
        {
            var versionNums = input.Split('.');
            int major = 0;
            int minor = 0;
            int build = 0;
            int revision = 0;
            for (int i = 0; i < versionNums.Length; ++i)
            {
                switch (i)
                {
                    case 0:
                        major = int.Parse(versionNums[i]);
                        break;
                    case 1:
                        minor = int.Parse(versionNums[i]);
                        break;
                    case 2:
                        build = int.Parse(versionNums[i]);
                        break;
                    case 3:
                        revision = int.Parse(versionNums[i]);
                        break;
                }
            }
            return new VersionEx(major, minor, build, revision);
        }

        public static bool TryParse(string input, out VersionEx result)
        {
            try
            {
                result = VersionEx.Parse(input);
                return true;
            }
            catch (Exception)
            {
                result = null;
                return false;
            }
        }

        public object Clone()
        {
            return new VersionEx(Major, Minor, Build, Revision);
        }

        public int CompareTo(object obj)
        {
            if (obj is VersionEx)
            {
                return CompareTo((VersionEx)obj);
            }
            else if (obj is Version)
            {
                var rhs = (Version)obj;
                return _Major != rhs.Major ? (_Major > rhs.Major ? 1 : -1) :
                _Minor != rhs.Minor ? (_Minor > rhs.Minor ? 1 : -1) :
                _Build != rhs.Build ? (_Build > rhs.Build ? 1 : -1) :
                _Revision != rhs.Revision ? (_Revision > rhs.Revision ? 1 : -1) :
                0;
            }
            else return 1;
        }

        public int CompareTo(VersionEx obj)
        {
            return
                 ReferenceEquals(obj, this) ? 0 :
                 ReferenceEquals(obj, null) ? 1 :
                 _Major != obj._Major ? (_Major > obj._Major ? 1 : -1) :
                 _Minor != obj._Minor ? (_Minor > obj._Minor ? 1 : -1) :
                 _Build != obj._Build ? (_Build > obj._Build ? 1 : -1) :
                 _Revision != obj._Revision ? (_Revision > obj._Revision ? 1 : -1) :
                 0;
        }

        public bool Equals(VersionEx obj)
        {
            return CompareTo(obj) == 0;
        }

        public override bool Equals(object obj)
        {
            return CompareTo(obj) == 0;
        }

        public override string ToString()
        {
            return ToString(DefaultFormatFieldCount);
        }

        public string ToString(int fieldCount)
        {
            switch (fieldCount)
            {
                case 2:
                    return string.Format("{0}.{1}", _Major, _Minor);
                case 3:
                    return string.Format("{0}.{1}.{2}", _Major, _Minor, _Build);
                case 4:
                    return string.Format("{0}.{1}.{2}.{3}", _Major, _Minor, _Build, _Revision);
                default:
                    return "0.0.0.0";
            }
        }

        public override int GetHashCode()
        {
            // Let's assume that most version numbers will be pretty small and just
            // OR some lower order bits together.

            int accumulator = 0;

            accumulator |= (_Major & 0x0000000F) << 28;
            accumulator |= (_Minor & 0x000000FF) << 20;
            accumulator |= (_Build & 0x000000FF) << 12;
            accumulator |= (_Revision & 0x00000FFF);

            return accumulator;
        }

        public static bool operator ==(VersionEx v1, VersionEx v2)
        {
            return v1.Equals(v2);
        }

        public static bool operator !=(VersionEx v1, VersionEx v2)
        {
            return !v1.Equals(v2);
        }

        public static bool operator <(VersionEx v1, VersionEx v2)
        {
            return v1.CompareTo(v2) < 0;
        }

        public static bool operator >(VersionEx v1, VersionEx v2)
        {
            return v1.CompareTo(v2) > 0;
        }

        public static bool operator <=(VersionEx v1, VersionEx v2)
        {
            return v1.CompareTo(v2) <= 0;
        }

        public static bool operator >=(VersionEx v1, VersionEx v2)
        {
            return v1.CompareTo(v2) >= 0;
        }
    }

    public static class ExtensionMethods
    {
        public static string TrimLast(this Management.Automation.PSObject thiz, string separator)
        {
            var str = thiz.BaseObject as string;
            var index = str.LastIndexOf(separator);
            if (index != -1)
                return str.Substring(0, index);
            return str;
        }
    }
}
"@

    Add-Type -TypeDefinition $code_str
    $TrimLastMethod = [ExtensionMethods].GetMethod('TrimLast')
    Update-TypeData -TypeName System.String -MemberName TrimLast -MemberType CodeMethod -Value $TrimLastMethod
}


function ConvertFrom-Props {
    param(
        [Parameter(Mandatory=$true)]
        $InputObject
    )

    $props = @{}

    foreach($_ in $InputObject) {
        if ($_ -match "^#.*$") {
            continue
        }
        if ($_ -match "^(.+?)\s*=\s*(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $props[$key] = $value
        }
    }

    return $props
}


function fuzzy_match($path, $filters) {
    foreach ($filter in $filters) {
        if ($path -like $filter) { return $true }
    }
    return $false
}

function recreate_symlink($path, $target) {
    if (Test-Path $path -PathType Leaf) {
        $item = Get-Item $path
        if ($item.Target -ne $target) {
            New-Item  -ItemType SymbolicLink -Path $dest -Target $item.Target -Force 1>$null
        }
    }
    else { 
        New-Item  -ItemType SymbolicLink -Path $dest -Target $item.Target -Force 1>$null 
    }
}
function  copy_tree_impl($path, $options) {
    # process include/exclude filters
    $relative_path = if ($options.level -gt 0) { $path.Substring($options.source_root.Length + 1) } else { '' }
    if ($Global:IsWin) {
        $relative_path = $relative_path.Replace('\', '/')
    }
    if ($options.include -and !(fuzzy_match $relative_path $options.include)) {
        println "Skip copy for $path which is not match with include: $($options.include)"
        return
    }

    if ($options.exclude -and (fuzzy_match $relative_path $options.exclude)) {
        println "Skip copy for $path which is matched with exclude: $($options.exclude)"
        return
    }

    # process copy
    $item = Get-Item $path
    if (!$item.PSIsContainer) {
        # copy file
        # resolve dest path
        $dest = Join-Path $options.dest_root $relative_path
        $dest_dir = Split-Path $dest -Parent
        if (!(Test-Path $dest_dir -PathType Container)) {
            New-Item -ItemType Directory $dest_dir 1>$null
        }
        if (!$item.Target) {
            if (!$options.quiet) {
                println "Copy file: $path ==> $dest"
            }
            Copy-Item $path $dest -Force
        }
        else {
            # recreate symlink if system and scm support
            println "Symlink file $path ==> $($item.Target)"
            recreate_symlink $dest $item.Target
        }
    }
    else {
        if (!$item.Target) {
            # process non symlink folder
            ++$options.level
            $citems = Get-ChildItem $path
            foreach ($citem in $citems) {
                copy_tree_impl $citem.FullName $options
            }
        }
        else {
            println "!Skip symlink folder $path"
        }
    }
}

# due to both Copy-Item and unix cp command not support symlink,
# we implment ourself

function copy_tree($path, $dest, $include = @(), $exclude = @(), $quiet = $false) {

    $options = @{
        source_root = $path
        dest_root   = $dest
        include     = $include
        exclude     = $exclude
        level       = 0
        quiet       = $quiet
    }
    copy_tree_impl $path $options
}
