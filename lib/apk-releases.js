const API = 'https://api.github.com/repos/vuanh97nd/Kinnect/releases';
const PREFIX = 'https://github.com/vuanh97nd/Kinnect/releases/download/';
const version = value => {
  const match = /^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})$/.exec(String(value || ''));
  return match ? match.slice(1).map(Number) : null;
};

export function selectPublishedApk(releases) {
  const choices = [];
  for (const release of releases) {
    const parts = version(release?.tag_name);
    if (!parts || release.draft || !Array.isArray(release.assets)) continue;
    for (const asset of release.assets) {
      const name = /^Kinnect-(\d+\.\d+\.\d+)-(?:native|debug)\.apk$/.exec(asset.name || '');
      if (!name || !version(name[1])?.every((n, i) => n === parts[i]) || !(asset.size > 0) || (asset.state && asset.state !== 'uploaded')) continue;
      const expected = PREFIX + encodeURIComponent(release.tag_name) + '/' + encodeURIComponent(asset.name);
      if (asset.browser_download_url !== expected) continue;
      choices.push({ url: asset.browser_download_url, version: release.tag_name, parts, stable: !release.prerelease });
      break;
    }
  }
  choices.sort((a, b) => b.parts[0] - a.parts[0] || b.parts[1] - a.parts[1] || b.parts[2] - a.parts[2] || Number(b.stable) - Number(a.stable));
  return choices[0] || null;
}

export async function publishedApk(fetchImpl = fetch) {
  // GitHub's collection is ordered by creation time; /latest finds a stable release
  // even when a new version points at an older commit and falls down that collection.
  const results = await Promise.allSettled([API + '/latest', API + '?per_page=100'].map(async url => {
    const response = await fetchImpl(url, {
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'Kinnect-Server' },
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw Error('GitHub ' + response.status);
    const data = await response.json();
    return Array.isArray(data) ? data : [data];
  }));
  const releases = results.flatMap(result => result.status === 'fulfilled' ? result.value : []);
  const selected = selectPublishedApk(releases);
  if (!selected) throw Error('Không có APK phát hành hợp lệ');
  return selected;
}
