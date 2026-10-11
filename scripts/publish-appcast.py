#!/usr/bin/env python3
"""Publish the feed only after upload; never replace it with an older release."""
import base64
import json
import subprocess
import sys
import xml.etree.ElementTree as ET

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def newest_version(data):
    root = ET.fromstring(data)
    versions = [int(item.text) for item in root.iter(SPARKLE + 'version')]
    return max(versions, default=0)


def publish(path):
    endpoint = 'repos/bhanurp/arta/contents/updates/appcast.xml'
    existing = json.loads(subprocess.check_output(['gh', 'api', endpoint + '?ref=main']))
    previous = base64.b64decode(existing['content'])
    with open(path, 'rb') as source:
        updated = source.read()
    if newest_version(updated) <= newest_version(previous):
        print('Feed already contains this version or a newer version; left unchanged.')
        return
    payload = dict(message='Publish signed Arta update feed', branch='main',
                   sha=existing['sha'], content=base64.b64encode(updated).decode())
    subprocess.run(['gh', 'api', '--method', 'PUT', endpoint, '--input', '-'],
                   input=json.dumps(payload).encode(), stdout=subprocess.DEVNULL, check=True)
    print('Published signed update feed.')


if __name__ == '__main__':
    publish(sys.argv[1])
