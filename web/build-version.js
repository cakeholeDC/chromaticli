import { readFileSync } from 'node:fs';

export function readVersion(manifestPath, releaseTag) {
  const version = JSON.parse(readFileSync(manifestPath, 'utf8'))?.['.'];
  if (typeof version !== 'string' || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version) || version.trim() !== version) {
    throw new Error('Release manifest must contain a stable X.Y.Z version at key "."');
  }
  if (releaseTag !== undefined && releaseTag !== `v${version}`) {
    throw new Error(`Release tag must match manifest version: expected v${version}`);
  }
  return version;
}
