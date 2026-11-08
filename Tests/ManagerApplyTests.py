"""Run the actual updater helper in disposable processes, without opening BMM's UI."""
from pathlib import Path
import hashlib
import subprocess
import time
import uuid

root = Path(__file__).resolve().parents[1]
work = root / 'artifacts' / ('apply-fixture-' + uuid.uuid4().hex[:8])
work.mkdir(parents=True)
framework = Path('C:/Windows/Microsoft.NET/Framework64/v4.0.30319')
refs = ['/reference:' + str(framework / f) for f in ['System.dll', 'System.Core.dll', 'System.Net.Http.dll', 'System.Web.Extensions.dll', 'System.IO.Compression.dll', 'System.IO.Compression.FileSystem.dll']]
core = [str(p) for p in sorted((root / 'Core').glob('*.cs'))]
probe = work / 'Probe.cs'
probe.write_text('''using System;using System.Diagnostics;using System.IO;using BeyondModManager;
class ApplyProbe { static void Main(string[] args) {
var exe=Path.Combine(Path.GetFullPath(args[0]),Updates.ManagerExecutableName);
var staged=new StagedManagerUpdate{ExecutablePath=exe,WorkDirectory=Path.GetFullPath(args[0]),Sha256=Updates.HashFile(exe),Version="1.0.10"};
Updates.BeginManagerUpdate(staged,Process.GetCurrentProcess().MainModule.FileName);
System.Threading.Thread.Sleep(Int32.Parse(args[1]));
} }''')
replacement = work / 'Replacement.cs'
replacement.write_text('''using System;using System.IO;
class Replacement {static void Main(){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"replacement-started.txt"),"ok");}}''')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

lines = []
for label, pause in [('immediate', 0), ('wait-for-exit', 1500), ('rollback', 0)]:
    fail = label == 'rollback'
    case = work / label
    stage = case / 'staged'
    stage.mkdir(parents=True)
    target = case / 'Beyond Mod Manager.exe'
    candidate = stage / target.name
    subprocess.run([str(framework / 'csc.exe'), '/nologo', '/target:exe', '/platform:x64', '/main:ApplyProbe', '/out:' + str(target), *refs, *core, str(probe)], check=True, cwd=root)
    original = sha(target)
    if fail:
        candidate.write_bytes(b'MZ' + b'not a runnable program' * 10)
    else:
        subprocess.run([str(framework / 'csc.exe'), '/nologo', '/target:winexe', '/platform:x64', '/out:' + str(candidate), str(replacement)], check=True)
    subprocess.run([str(target), str(stage), str(pause)], check=True, timeout=15, creationflags=subprocess.CREATE_NO_WINDOW)
    result = stage / 'update-error.txt' if fail else case / 'replacement-started.txt'
    end = time.monotonic() + 25
    while not result.exists() and time.monotonic() < end:
        time.sleep(.1)
    assert result.exists(), f'Updater helper did not complete: {case}'
    if fail:
        assert sha(target) == original, 'Launch failure did not restore original executable'
        assert list(case.glob('*.failed')), 'Failed candidate not retained for diagnosis'
        lines.append('PASS actual updater restores original EXE when replacement cannot launch')
    else:
        assert sha(target) == sha(candidate), 'Helper installed different executable'
        backup = list(case.glob('*.previous'))
        assert len(backup) == 1 and sha(backup[0]) == original
        lines.append('PASS actual updater replaces and verifies EXE, keeps recovery copy and launches replacement: ' + label)
lines.append('Fixture: ' + str(work))
report = '\n'.join(lines) + '\n'
(root / 'artifacts' / 'manager-apply-tests.txt').write_text(report)
print(report)
