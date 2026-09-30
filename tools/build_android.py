#!/usr/bin/env python3
"""Build a signed ARM64 Android playtest with the same optimized art as Windows."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

from build_support import ensure_checks, provenance

from build_windows import ROOT, prepare_project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='/Users/wangtaizhi/Desktop/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--sdk', default=str(Path.home() / 'Library/Android/sdk'))
    parser.add_argument('--java', default='/Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home')
    parser.add_argument('--signing', type=Path, default=Path.home() / '.config/wuxingcard/android-signing.json')
    parser.add_argument('--version-code', type=int)
    parser.add_argument('--checks-report', type=Path, help='Reuse a passing check_project.py report for this exact source')
    args = parser.parse_args()
    source_snapshot, checks = ensure_checks(args.godot, args.checks_report)
    if not args.signing.is_file():
        raise SystemExit('Android signing configuration is missing; see README Android export instructions.')
    signing = json.loads(args.signing.read_text())
    env = os.environ.copy()
    env.update(JAVA_HOME=args.java, GODOT_ANDROID_KEYSTORE_RELEASE_PATH=signing['keystore'],
               GODOT_ANDROID_KEYSTORE_RELEASE_USER=signing['alias'],
               GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=signing['password'])
    built = datetime.now().astimezone()
    stamp = built.strftime('%Y-%m-%d_%H%M%S')
    stage = ROOT / 'work' / f'android-export-{stamp}'
    report = prepare_project(stage)
    shutil.copytree(ROOT / 'licenses', stage / 'licenses')
    for source in sorted((ROOT / 'assets/audio/licenses').glob('*.txt')):
        shutil.copy2(source, stage / 'licenses' / f'Kenney-{source.name}')
    for name in ['NotoSansCJK-LICENSE.txt', 'NotoSerifCJK-LICENSE.txt']:
        shutil.copy2(ROOT / 'assets/fonts' / name, stage / 'licenses' / name)
    # Increment release versions locally so subsequent APKs can update in place.
    version_file = args.signing.parent / 'android-version.txt'
    version = args.version_code or (int(version_file.read_text()) + 1 if version_file.exists() else 1)
    if version <= 0:
        raise SystemExit('Android version code must be positive.')
    preset = stage / 'export_presets.cfg'
    version_name = json.loads((ROOT / 'data/version.json').read_text())['version']
    preset.write_text(preset.read_text().replace('version/code=1', f'version/code={version}')
                      .replace('version/name="0.1"', f'version/name="{version_name}"'))

    def run(*arguments):
        subprocess.run([args.godot, '--headless', '--path', str(stage), *map(str, arguments)],
                       check=True, env=env, cwd=stage)

    run('--script', ROOT / 'tools/prepare_export_art.gd', '--', report)
    run('--editor', '--import', '--quit')
    run('--script', ROOT / 'tools/verify_export_art.gd', '--', report)
    pack = stage / 'work/android-verified.pck'
    run('--export-pack', 'Android', pack)
    subprocess.run([args.godot, '--headless', '--main-pack', str(pack), '--script',
                    str(ROOT / 'tools/verify_export_pack.gd')], check=True, env=env, cwd=stage)
    folder = ROOT / 'dist' / f'WuxingMingpan-Android-{stamp}'
    folder.mkdir(parents=True)
    apk = folder / f'五行命盘_Android_ARM64_试玩版_{stamp}.apk'
    run('--export-release', 'Android', apk)
    signer = Path(args.sdk) / 'build-tools/36.0.0/apksigner'
    subprocess.run([str(signer), 'verify', '--verbose', str(apk)], check=True, env=env)
    aapt = Path(args.sdk) / 'build-tools/36.0.0/aapt'
    details = subprocess.check_output([str(aapt), 'dump', 'badging', str(apk)], env=env, text=True)
    if "package: name='com.tydge.wuxingcard'" not in details or "native-code: 'arm64-v8a'" not in details:
        raise RuntimeError('APK package or architecture verification failed')
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('APK ZIP resource verification failed')
        names = archive.namelist()
        if not any('licenses/Godot-LICENSE.txt' in name for name in names):
            raise RuntimeError('Required engine license was not embedded in the APK')
    version_file.write_text(str(version) + '\n')
    instructions = '''五行 · 命盘 — Android 试玩版

安装：将 APK 发到安卓设备，打开并允许该来源安装应用。
适用于 Android 7.0 及以上、支持 OpenGL ES 3.0 的 ARM64 设备；横屏游玩。
无需安装 Godot。卡组保存在本机，联网权限未开启。

操作
轻点手牌查看详情；按住沿手牌左右滑动换牌。
向上拖出手牌，拖到目标后松手释放；拖回手牌取消。
预计伤害显示在手指旁上方。召唤牌拖到我方空槽位。
轻点五行能量、召唤物或状态图标查看说明，点空白处收起。
点击“规则”查看玩法，“记录”查看或导出本局战报。
卡组页点 ＋ 入组，轻点已携带的牌查看，点 − 移除。
保存卡组后可配三件法宝：轻点法宝下方 ＋ 装备，或拖至右侧对应槽位；轻点卡面查看详情。
系统返回键优先收起详情，再返回上一层；对战中返回会询问是否回到山门。

测试模式双方生命 80；随机卡组 25 张，同名最多 2 张。
肉鸽、竞技、无尽模式暂未开放。
本版本为单机试玩；清除应用数据或卸载会删除本机卡组。
以后同签名的新版本可直接覆盖安装，保留卡组。
'''
    (folder / '试玩说明.txt').write_text(instructions, encoding='utf-8-sig')
    shutil.copytree(stage / 'licenses', folder / 'licenses')
    manifest = {
        'built': built.isoformat(), **provenance(source_snapshot),
        'engine': subprocess.check_output([args.godot, '--version'], text=True).strip(),
        'platform': 'Android ARM64', 'package': 'com.tydge.wuxingcard', 'version_code': version,
        'cards': len(json.loads((ROOT / 'data/cards.json').read_text())),
        'summons': len(json.loads((ROOT / 'data/summons.json').read_text())),
        'art': json.loads(report.read_text()), 'bytes': apk.stat().st_size,
        'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
    }
    (folder / 'source_manifest.json').write_text(json.dumps(source_snapshot, ensure_ascii=False, indent=2) + '\n')
    (folder / 'checks.json').write_text(json.dumps(checks, ensure_ascii=False, indent=2) + '\n')
    (folder / 'build_info.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    (folder / 'apk_manifest.txt').write_text(details)
    bundle = folder.with_suffix('.zip')
    with zipfile.ZipFile(bundle, 'w', zipfile.ZIP_DEFLATED) as archive:
        for item in folder.rglob('*'):
            if item.is_file(): archive.write(item, item.relative_to(folder.parent))
    print(f'Android playtest: {apk} ({apk.stat().st_size / 1024 / 1024:.1f} MiB)', flush=True)


if __name__ == '__main__':
    main()
