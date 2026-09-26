#!/usr/bin/env python3
"""Export and zip a self-contained Windows playtest using the saved Godot preset."""
import argparse
from datetime import date
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='/Users/wangtaizhi/Desktop/Godot.app/Contents/MacOS/Godot')
    args = parser.parse_args()
    stamp = date.today().isoformat()
    folder = ROOT / 'dist' / f'WuxingMingpan-Windows-{stamp}'
    folder.mkdir(parents=True, exist_ok=True)
    executable = folder / 'WuxingMingpan.exe'
    subprocess.run([args.godot, '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'], check=True)
    subprocess.run([args.godot, '--headless', '--path', str(ROOT), '--export-release', 'Windows Desktop', str(executable)], check=True)
    pack = executable.with_suffix('.pck')
    if not executable.is_file() or not pack.is_file():
        raise RuntimeError('Windows export did not produce both the executable and resource pack')
    instructions = '''五行 · 命盘 — Windows 试玩版

启动：解压整个文件夹，双击 WuxingMingpan.exe。
无需安装 Godot。请让 WuxingMingpan.exe 与 WuxingMingpan.pck 保持在同一文件夹。
适用于 64 位 Windows 10 / 11；需要支持 OpenGL 3.3 的显卡驱动。

玩法
1. 点击“测试模式”直接对战；双方生命 80，随机牌组各 25 张，同名最多 3 张。
2. 鼠标悬停手牌查看详情；停留半秒后显示状态关键词说明。
3. 将伤害牌拖到敌方角色或召唤物；召唤牌拖到我方空槽位。
4. 其他牌拖到手牌区域上方释放；点“结束回合”让敌人行动。
5. “卡牌一览”收录当前 39 张卡牌，可以按属性筛选、点击放大，点击旁边收回。
6. 肉鸽、竞技、无尽模式暂未开放。当前版本为单机测试模式。

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
    card_count = len(json.loads((ROOT / 'data' / 'cards.json').read_text()))
    manifest = {'built':stamp, 'engine':subprocess.check_output([args.godot, '--version'],text=True).strip(), 'platform':'Windows x86_64', 'cards':card_count, 'files':[]}
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
