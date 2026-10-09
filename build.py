from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent
DIST = ROOT / 'dist'
ARTIFACTS = ROOT / 'artifacts'
FRAMEWORK = Path('C:/Windows/Microsoft.NET/Framework64/v4.0.30319')
for directory in (DIST, ARTIFACTS):
    directory.mkdir(exist_ok=True)
version = re.search(r'ManagerVersion = "([0-9.]+)"', (ROOT / 'Program.cs').read_text()).group(1)
metadata = json.loads((ROOT / 'Assets/bmm-public.json').read_text(encoding='utf-8'))
assert metadata['version'] == version
assert metadata['update']['TagPrefix'] == 'bmm-v'
assert metadata['update']['ManifestAsset'] == 'bmm-update.json'
assert json.loads((ROOT / 'Assets/ba-public.json').read_text(encoding='utf-8'))['version'] == '1.0.5'

references = ['System.dll', 'System.Core.dll', 'System.Xaml.dll', 'System.Web.Extensions.dll',
              'System.Windows.Forms.dll', 'System.Drawing.dll', 'System.Net.Http.dll',
              'System.IO.Compression.dll', 'System.IO.Compression.FileSystem.dll']
refs = ['/reference:' + str(FRAMEWORK / name) for name in references]
refs += ['/reference:' + str(FRAMEWORK / 'WPF' / name) for name in
         ['WindowsBase.dll', 'PresentationCore.dll', 'PresentationFramework.dll']]
exe = DIST / 'Beyond Mod Manager.exe'
resources = {'MainWindow.xaml': ROOT / 'MainWindow.xaml'}
resources.update({p.name: p for p in sorted((ROOT / 'Assets').iterdir()) if p.is_file()})
sources = [ROOT / 'Program.cs', ROOT / 'Core/ModInventory.cs', ROOT / 'Core/Updates.cs', ROOT / 'Tests/UpdatesTests.cs']
command = [str(FRAMEWORK / 'csc.exe'), '/nologo', '/target:winexe', '/optimize+', '/platform:x64',
           '/main:BeyondModManager.Program', '/win32manifest:' + str(ROOT / 'app.manifest'),
           '/win32icon:' + str(ROOT / 'Assets/bmm-icon.ico'), '/out:' + str(exe)]
command += refs + ['/resource:' + str(path) + ',' + name for name, path in resources.items()] + [str(path) for path in sources]
subprocess.run(command, check=True, cwd=ROOT)
subprocess.run([str(exe), '--self-test', str(ARTIFACTS / 'self-test.txt')], check=True, cwd=ROOT)
print((ARTIFACTS / 'self-test.txt').read_text())
if '--skip-previews' not in sys.argv:
    for page, width, height in [('Mods', 1240, 840), ('Settings', 1240, 840), ('Creators', 1004, 681), ('Mods', 1004, 681), ('Import', 1004, 681)]:
        subprocess.run([str(exe), '--preview', str(ARTIFACTS / ('preview-' + page.lower() + '-' + str(width) + '.png')), page, str(width), str(height)], check=True, cwd=ROOT)

archive = DIST / ('Beyond-Mod-Manager-' + version + '.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.write(exe, 'Beyond Mod Manager.exe')
with zipfile.ZipFile(archive) as z:
    assert z.namelist() == ['Beyond Mod Manager.exe']
    assert z.testzip() is None
    assert hashlib.sha256(z.read('Beyond Mod Manager.exe')).digest() == hashlib.sha256(exe.read_bytes()).digest()
manifest = {'schema': 1, 'version': version, 'channel': 'stable', 'asset': archive.name,
            'size': archive.stat().st_size, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
            'notes': metadata['notes']}
(DIST / 'bmm-update.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
(ARTIFACTS / 'build-report.json').write_text(json.dumps({'version': version, 'exeSha256': hashlib.sha256(exe.read_bytes()).hexdigest(),
                                                       'zip': manifest, 'resources': list(resources), 'zipEntries': ['Beyond Mod Manager.exe']}, indent=2), encoding='utf-8')
print('BUILT', archive, 'bytes', manifest['size'])
