"""make_avds.py - create emulator definitions for the old-Android test runs (API 24, 30, 34) from an existing API 37 one.

  python tools/android/make_avds.py [source_avd_name]

Needs the system images installed first (sdkmanager "system-images;android-24;default;x86_64" ...) and a source AVD
(default: rightmix37) in ~/.android/avd. Each new AVD gets a small 2 GB data partition.
"""
import os
import sys

avd_home = os.environ.get('ANDROID_AVD_HOME') or os.path.join(os.path.expanduser('~'), '.android', 'avd')
source = sys.argv[1] if len(sys.argv) > 1 else 'rightmix37'
base = open(os.path.join(avd_home, source + '.avd', 'config.ini')).read()
sep = os.sep
for api, tag, disp in ((24, 'default', 'Default Android System Image'), (30, 'google_apis', 'Google APIs'),
                       (34, 'google_apis', 'Google APIs')):
    name = 'rightmix%d' % api
    d = os.path.join(avd_home, name + '.avd')
    os.makedirs(d, exist_ok=True)
    c = base.replace(source, name).replace('android-37.0', 'android-%d' % api)
    c = c.replace('google_apis' + '\\' + 'x86_64', tag + '\\' + 'x86_64').replace('google_apis/x86_64', tag + '/x86_64')
    c = c.replace('tag.id=google_apis', 'tag.id=' + tag).replace('tag.display=Google APIs', 'tag.display=' + disp)
    c = c.replace('disk.dataPartition.size=6G', 'disk.dataPartition.size=2G')
    open(os.path.join(d, 'config.ini'), 'w').write(c)
    with open(os.path.join(avd_home, name + '.ini'), 'w') as f:
        f.write('avd.ini.encoding=UTF-8\npath=%s\npath.rel=avd%s%s.avd\ntarget=android-%d\n' % (d, sep, name, api))
    print('created', name)
