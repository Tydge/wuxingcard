#!/usr/bin/env python3
"""Export and zip a self-contained Windows playtest using the saved Godot preset."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import re
import zipfile

from build_support import ensure_checks, provenance

ROOT = Path(__file__).resolve().parents[1]

def prepare_project(stage):
    """Make an export-only copy, retaining dynamic ID-based runtime artwork."""
    stage.mkdir(parents=True, exist_ok=False)
    cards = json.loads((ROOT / 'data/cards.json').read_text())
    summons = json.loads((ROOT / 'data/summons.json').read_text())
    artifacts = json.loads((ROOT / 'data/artifacts.json').read_text())
    characters = json.loads((ROOT / 'data/characters.json').read_text())
    runtime = {f"assets/cards/generated/{c['id']}.webp" for c in cards}
    runtime.update(f"assets/cards/elements/{element}.webp" for element in ['metal', 'wood', 'water', 'fire', 'earth'])
    runtime.update(f"assets/summons/standee/{s['id']}.webp" for s in summons)
    runtime.update(f"assets/artifacts/{a['id']}.webp" for a in artifacts)
    runtime.update(f"assets/artifacts/{a['id']}_standee.webp" for a in artifacts if a['slot'] == 'implement')
    for actor in characters:
        runtime.update([f"assets/characters/{actor['id']}.webp", f"assets/characters/{actor['id']}_standee.webp"])
    runtime.update(['assets/backgrounds/arena.webp', 'assets/backgrounds/mountain_gate.webp'])
    # Keep literal references as well as the artwork loaded dynamically by ID.
    for directory in ['ui', 'battle', 'data', 'audio']:
        for source in (ROOT / directory).rglob('*'):
            if source.suffix in ['.gd', '.tscn']:
                runtime.update(p for p in re.findall(r'res://(assets/[^"\s]+)', source.read_text()) if '%' not in p)
        shutil.copytree(ROOT / directory, stage / directory)
    for filename in ['project.godot', 'export_presets.cfg']:
        shutil.copy2(ROOT / filename, stage / filename)
        runtime.update(p for p in re.findall(r'res://(assets/[^"\s]+)', (ROOT / filename).read_text()) if '%' not in p)
    for filename in sorted(runtime):
        source = ROOT / filename
        if not source.is_file():
            raise FileNotFoundError(f'Required runtime resource is missing: {filename}')
        target = stage / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        sidecar = source.with_name(source.name + '.import')
        if sidecar.is_file():
            shutil.copy2(sidecar, target.with_name(target.name + '.import'))
    all_images = {p.relative_to(ROOT).as_posix() for p in (ROOT / 'assets').rglob('*.webp')}
    omitted = sorted(all_images - runtime)
    plan = {
        'quality': 0.95,
        'images': sorted(all_images & runtime),
        'excluded_images': omitted,
        'excluded_source_bytes': sum((ROOT / p).stat().st_size for p in omitted),
    }
    (stage / 'work').mkdir()
    report = stage / 'work/export_art_report.json'
    report.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n')
    return report

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='/Users/wangtaizhi/Desktop/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--checks-report', type=Path, help='Reuse a passing --suite full report for the same runtime, tests and engine')
    args = parser.parse_args()
    source_snapshot, checks = ensure_checks(args.godot, args.checks_report)
    built = datetime.now().astimezone()
    stamp = built.strftime('%Y-%m-%d_%H%M%S')
    stage = ROOT / 'work' / f'windows-export-{stamp}'
    report = prepare_project(stage)
    subprocess.run([args.godot, '--headless', '--path', str(stage), '--script', str(ROOT / 'tools/prepare_export_art.gd'), '--', str(report)], check=True)
    subprocess.run([args.godot, '--headless', '--path', str(stage), '--editor', '--import', '--quit'], check=True)
    subprocess.run([args.godot, '--headless', '--path', str(stage), '--script', str(ROOT / 'tools/verify_export_art.gd'), '--', str(report)], check=True)
    art_report = json.loads(report.read_text())
    folder = ROOT / 'dist' / f'WuxingMingpan-Windows-{stamp}'
    folder.mkdir(parents=True, exist_ok=False)
    executable = folder / 'WuxingMingpan.exe'
    subprocess.run([args.godot, '--headless', '--path', str(stage), '--export-release', 'Windows Desktop', str(executable)], check=True)
    pack = executable.with_suffix('.pck')
    if not executable.is_file() or not pack.is_file():
        raise RuntimeError('Windows export did not produce both the executable and resource pack')
    subprocess.run([args.godot, '--headless', '--main-pack', str(pack), '--script', str(ROOT / 'tools/verify_export_pack.gd')], check=True, cwd=stage)
    card_count = len(json.loads((ROOT / 'data' / 'cards.json').read_text()))
    instructions = f'''五行 · 命盘 — Windows 试玩版

启动：解压整个文件夹，双击 WuxingMingpan.exe。
无需安装 Godot。请让 WuxingMingpan.exe 与 WuxingMingpan.pck 保持在同一文件夹。
适用于 64 位 Windows 10 / 11；需要支持 OpenGL 3.3 的显卡驱动。

玩法
1. 点击“测试模式”选择随机或自建卡组后开战；双方生命 80，随机牌组各 25 张，同名最多 2 张。
2. 鼠标悬停手牌查看详情；停留半秒后显示状态关键词说明。
3. 将伤害牌拖到对手或其召唤物；召唤牌拖到我方空槽位。
4. 其他牌拖到手牌区域上方释放；点“结束回合”让敌人行动。
5. “卡牌一览”收录当前 {card_count} 张卡牌，可以按属性筛选、点击放大，点击旁边收回。
6. 悬停五行能量查看抗性，点击“规则”查看说明、“记录”查看或导出战报。
7. 肉鸽、竞技、无尽模式暂未开放。当前版本为单机测试模式。

反馈问题时，附上截图、刚刚使用的卡牌和发生问题前的操作。
运行日志：%APPDATA%\\Godot\\app_userdata\\五行 · 命盘\\logs\\godot.log

内置开源中文字体及 Godot 引擎的授权说明见 licenses 文件夹。
'''
    (folder / '试玩说明.txt').write_text(instructions, encoding='utf-8-sig')
    licenses = folder / 'licenses'
    licenses.mkdir(exist_ok=True)
    for name in ['NotoSansCJK-LICENSE.txt', 'NotoSerifCJK-LICENSE.txt']:
        shutil.copy2(ROOT / 'assets' / 'fonts' / name, licenses / name)
    for name in ['Godot-LICENSE.txt', 'Godot-COPYRIGHT.txt']:
        shutil.copy2(ROOT / 'licenses' / name, licenses / name)
    for source in sorted((ROOT / 'assets/audio/licenses').glob('*.txt')):
        shutil.copy2(source, licenses / f'Kenney-{source.name}')
    build_source = provenance(source_snapshot)
    manifest = {'built':built.isoformat(), **build_source, 'engine':subprocess.check_output([args.godot, '--version'],text=True).strip(), 'platform':'Windows x86_64', 'cards':card_count, 'summons':len(json.loads((ROOT / 'data/summons.json').read_text())), 'art':art_report, 'files':[]}
    (folder / 'source_manifest.json').write_text(json.dumps(source_snapshot, ensure_ascii=False, indent=2) + '\n')
    (folder / 'checks.json').write_text(json.dumps(checks, ensure_ascii=False, indent=2) + '\n')
    for path in sorted(folder.rglob('*')):
        if not path.is_file() or path.name == 'build_info.json': continue
        manifest['files'].append({'path':path.relative_to(folder).as_posix(), 'bytes':path.stat().st_size, 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    (folder / 'build_info.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    archive = ROOT / 'dist' / f'五行命盘_Windows_x64_试玩版_{stamp}.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for path in sorted(folder.rglob('*')):
            if path.is_file(): z.write(path,path.relative_to(folder.parent))
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None: raise RuntimeError('Archive verification failed')
    print(f'Windows playtest: {archive} ({archive.stat().st_size/1024/1024:.1f} MiB)')

if __name__ == '__main__':
    main()
