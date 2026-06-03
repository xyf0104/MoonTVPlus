/**
 * 搜索时预测速模块（完整版）
 * 在搜索页面流式搜索结果到来时，同步对各个播放源进行真正的视频测速，
 * 测试内容包括：网速（秒开能力）、清晰度、延迟
 * 将结果缓存到 sessionStorage，播放页面直接使用预测速结果跳过优选等待。
 */

import { getVideoResolutionFromM3u8 } from '@/lib/utils';

// NOTE: 预测速结果的缓存键前缀，与搜索缓存区分
const PRETEST_CACHE_PREFIX = 'source_pretest_';

export interface SourcePretestResult {
  /** 源标识 (source key，如 "ikun") */
  sourceKey: string;
  /** 源+ID 的复合键 (如 "ikun-12345")，用于播放页精确匹配 */
  sourceIdKey: string;
  /** 延迟时间 (ms)，-1 表示不可达 */
  pingTime: number;
  /** 清晰度（如 "1080p", "720p"） */
  quality: string;
  /** 下载速度（如 "2.5 MB/s"） */
  loadSpeed: string;
  /** 码率（如 "2.5 Mbps"） */
  bitrate: string;
  /** 综合评分（网速50% + 清晰度30% + 延迟20%） */
  score: number;
  /** 测速时间戳 */
  testedAt: number;
}

export interface PretestCachePayload {
  query: string;
  results: SourcePretestResult[];
  updatedAt: number;
}

/**
 * 计算源的综合评分
 * 优先级：秒开（网速） > 清晰度 > 延迟
 */
function calculatePretestScore(
  quality: string,
  loadSpeed: string,
  pingTime: number,
  allSpeeds: number[],
  allPings: number[]
): number {
  // 网速评分（50% 权重）—— 秒开是最重要的
  const speedScore = (() => {
    if (loadSpeed === '未知' || loadSpeed === '测量中...' || loadSpeed === '直连') return 50;
    const match = loadSpeed.match(/^([\d.]+)\s*(KB\/s|MB\/s)$/);
    if (!match) return 30;
    const value = parseFloat(match[1]);
    const unit = match[2];
    const speedKBps = unit === 'MB/s' ? value * 1024 : value;
    const maxSpeed = allSpeeds.length > 0 ? Math.max(...allSpeeds) : 1024;
    return maxSpeed > 0 ? Math.min(100, (speedKBps / maxSpeed) * 100) : 50;
  })();

  // 清晰度评分（30% 权重）
  const qualityScore = (() => {
    switch (quality) {
      case '4K': return 100;
      case '2K': return 85;
      case '1080p': return 75;
      case '720p': return 60;
      case '480p': return 40;
      case 'SD': return 20;
      case '原生画质': return 70;
      default: return 0;
    }
  })();

  // 延迟评分（20% 权重）
  const pingScore = (() => {
    if (pingTime <= 0) return 0;
    const minPing = allPings.length > 0 ? Math.min(...allPings) : 50;
    const maxPing = allPings.length > 0 ? Math.max(...allPings) : 1000;
    if (maxPing === minPing) return 100;
    return Math.min(100, Math.max(0, ((maxPing - pingTime) / (maxPing - minPing)) * 100));
  })();

  return speedScore * 0.5 + qualityScore * 0.3 + pingScore * 0.2;
}

/**
 * 解析速度值为 KB/s
 */
function parseSpeedKBps(loadSpeed: string): number {
  if (!loadSpeed || loadSpeed === '未知' || loadSpeed === '测量中...' || loadSpeed === '直连') return 0;
  const match = loadSpeed.match(/^([\d.]+)\s*(KB\/s|MB\/s)$/);
  if (!match) return 0;
  const value = parseFloat(match[1]);
  return match[2] === 'MB/s' ? value * 1024 : value;
}

/**
 * 对搜索结果中的唯一源进行真正的视频测速
 * 使用 HLS.js 加载视频分片，测试实际网速、清晰度和延迟
 */
export async function pretestSources(
  results: Array<{ source: string; id: string; source_name: string; episodes?: string[]; proxyMode?: boolean }>,
  query: string,
  onProgress?: (result: SourcePretestResult) => void
): Promise<SourcePretestResult[]> {
  // 每个源只测一次（取第一个搜索结果的 episodes）
  const sourceMap = new Map<string, { source: string; id: string; episodes?: string[]; proxyMode?: boolean }>();
  results.forEach((r) => {
    if (!sourceMap.has(r.source) && r.episodes && r.episodes.length > 0) {
      sourceMap.set(r.source, r);
    }
  });

  // 排除不需要测速的源类型
  const excludedPrefixes = ['openlist', 'emby', 'xiaoya', 'script:', 'directplay', 'netdisk'];
  const sourcesToTest = Array.from(sourceMap.entries()).filter(([source]) =>
    !excludedPrefixes.some((prefix) => source === prefix || source.startsWith(prefix))
  );

  if (sourcesToTest.length === 0) {
    return [];
  }

  // 并发视频测速，最大并发数 4（视频测速比 ping 更重，降低并发）
  const MAX_CONCURRENCY = 4;
  const testResults: SourcePretestResult[] = [];
  let nextIndex = 0;

  const worker = async () => {
    while (nextIndex < sourcesToTest.length) {
      const currentIndex = nextIndex++;
      const [source, sourceData] = sourcesToTest[currentIndex];

      try {
        // 取第一或第二集的 URL 用于测速
        const episodes = sourceData.episodes || [];
        let episodeUrl = episodes.length > 1 ? episodes[1] : episodes[0];

        if (!episodeUrl) {
          throw new Error('no episode url');
        }

        // 处理需要代理的 m3u8 URL
        const isM3u8 = episodeUrl.toLowerCase().includes('.m3u') ||
          !episodeUrl.toLowerCase().match(/\.(mp4|flv|webm|mkv|avi|mov)(\?.*)?$/);
        if (sourceData.proxyMode && isM3u8) {
          episodeUrl = `/api/proxy/vod/m3u8?url=${encodeURIComponent(episodeUrl)}&source=${encodeURIComponent(source)}`;
        }

        // NOTE: 使用 HLS.js 进行真正的视频测速（网速 + 清晰度 + 延迟）
        // 超时设为 4 秒，确保搜索体验流畅
        const testResult = await getVideoResolutionFromM3u8(episodeUrl, 4000);

        const result: SourcePretestResult = {
          sourceKey: source,
          sourceIdKey: `${source}-${sourceData.id}`,
          pingTime: testResult.pingTime,
          quality: testResult.quality,
          loadSpeed: testResult.loadSpeed,
          bitrate: testResult.bitrate,
          score: 0, // 稍后统一计算
          testedAt: Date.now(),
        };

        testResults.push(result);
        onProgress?.(result);
      } catch {
        // 测速失败的源标记为不可达
        const result: SourcePretestResult = {
          sourceKey: source,
          sourceIdKey: `${source}-${sourceData.id}`,
          pingTime: -1,
          quality: '未知',
          loadSpeed: '未知',
          bitrate: '未知',
          score: -1,
          testedAt: Date.now(),
        };
        testResults.push(result);
        onProgress?.(result);
      }
    }
  };

  await Promise.all(
    Array.from({ length: Math.min(MAX_CONCURRENCY, sourcesToTest.length) }, () => worker())
  );

  // 统一计算综合评分（需要所有结果的网速和延迟来做归一化）
  const allSpeeds = testResults
    .map((r) => parseSpeedKBps(r.loadSpeed))
    .filter((s) => s > 0);
  const allPings = testResults
    .map((r) => r.pingTime)
    .filter((p) => p > 0);

  testResults.forEach((r) => {
    if (r.pingTime === -1) {
      r.score = -1;
    } else {
      r.score = calculatePretestScore(r.quality, r.loadSpeed, r.pingTime, allSpeeds, allPings);
    }
  });

  // 按综合评分排序后缓存
  testResults.sort((a, b) => b.score - a.score);
  savePretestCache(query, testResults);

  console.log('[Pretest] 视频测速完成:');
  testResults.forEach((r, i) => {
    console.log(`  ${i + 1}. ${r.sourceKey}: 评分=${r.score.toFixed(1)}, 网速=${r.loadSpeed}, 清晰度=${r.quality}, 延迟=${r.pingTime}ms`);
  });

  return testResults;
}

/**
 * 将预测速结果保存到 sessionStorage
 */
export function savePretestCache(query: string, results: SourcePretestResult[]): void {
  if (typeof window === 'undefined') return;

  try {
    const cacheKey = `${PRETEST_CACHE_PREFIX}${query.trim()}`;
    const payload: PretestCachePayload = {
      query: query.trim(),
      results,
      updatedAt: Date.now(),
    };
    sessionStorage.setItem(cacheKey, JSON.stringify(payload));
  } catch (error) {
    console.error('[Pretest] 保存预测速缓存失败:', error);
  }
}

/**
 * 从 sessionStorage 读取预测速结果
 */
export function readPretestCache(query: string): PretestCachePayload | null {
  if (typeof window === 'undefined' || !query.trim()) return null;

  try {
    const cacheKey = `${PRETEST_CACHE_PREFIX}${query.trim()}`;
    const cached = sessionStorage.getItem(cacheKey);
    if (!cached) return null;

    const parsed = JSON.parse(cached) as PretestCachePayload;

    // 缓存有效期 5 分钟
    if (Date.now() - parsed.updatedAt > 5 * 60 * 1000) {
      sessionStorage.removeItem(cacheKey);
      return null;
    }

    return parsed;
  } catch {
    return null;
  }
}

/**
 * 根据预测速综合评分对搜索源进行排序
 * 评分最高的排在前面（网速优先 > 清晰度 > 延迟）
 */
export function sortSourcesByPretest<T extends { source: string }>(
  sources: T[],
  pretestResults: SourcePretestResult[]
): T[] {
  const scoreMap = new Map(pretestResults.map((r) => [r.sourceKey, r.score]));

  return [...sources].sort((a, b) => {
    const scoreA = scoreMap.get(a.source) ?? -Infinity;
    const scoreB = scoreMap.get(b.source) ?? -Infinity;

    // 不可达的排最后
    if (scoreA === -1 && scoreB !== -1) return 1;
    if (scoreA !== -1 && scoreB === -1) return -1;
    if (scoreA === -1 && scoreB === -1) return 0;

    // 评分高的排前面
    return scoreB - scoreA;
  });
}
