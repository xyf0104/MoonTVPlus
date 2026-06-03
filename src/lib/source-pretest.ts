/**
 * 搜索时预测速模块
 * 在搜索页面流式搜索结果到来时，同步对各个播放源进行延迟测速，
 * 将结果缓存到 sessionStorage，播放页面直接使用预测速结果跳过优选等待。
 */

// NOTE: 预测速结果的缓存键前缀，与搜索缓存区分
const PRETEST_CACHE_PREFIX = 'source_pretest_';

export interface SourcePretestResult {
  /** 源标识 (source-id) */
  sourceKey: string;
  /** 延迟时间 (ms)，-1 表示不可达 */
  pingTime: number;
  /** 测速时间戳 */
  testedAt: number;
}

export interface PretestCachePayload {
  query: string;
  results: SourcePretestResult[];
  updatedAt: number;
}

/**
 * 对单个源的 API 端点进行 ping 测速
 * 通过请求源的 vod API 首页来测量响应延迟
 */
async function pingSource(apiUrl: string, timeout = 5000): Promise<number> {
  const startTime = performance.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);

  try {
    // 只请求首页数据量最小的接口来测延迟
    const testUrl = apiUrl.includes('?')
      ? `${apiUrl}&ac=videolist&pg=1`
      : `${apiUrl}?ac=videolist&pg=1`;

    const response = await fetch(`/api/source-pretest?url=${encodeURIComponent(testUrl)}`, {
      signal: controller.signal,
      cache: 'no-store',
    });

    clearTimeout(timer);

    if (!response.ok) {
      return -1;
    }

    const data = await response.json();
    // 优先使用服务端测量的延迟（更准确），否则用本地端到端延迟
    return data.pingTime ?? Math.round(performance.now() - startTime);
  } catch {
    clearTimeout(timer);
    return -1;
  }
}

/**
 * 批量对搜索结果中的唯一源进行预测速
 * 在搜索的同时调用，不阻塞搜索结果的展示
 */
export async function pretestSources(
  results: Array<{ source: string; id: string; source_name: string }>,
  query: string,
  onProgress?: (result: SourcePretestResult) => void
): Promise<SourcePretestResult[]> {
  // 去重：同一个 source 只测一次
  const uniqueSources = new Map<string, string>();
  results.forEach((r) => {
    if (!uniqueSources.has(r.source)) {
      uniqueSources.set(r.source, r.source_name);
    }
  });

  // 排除不需要测速的源类型
  const excludedPrefixes = ['openlist', 'emby', 'xiaoya', 'script:', 'directplay', 'netdisk'];
  const sourcesToTest = Array.from(uniqueSources.entries()).filter(([source]) =>
    !excludedPrefixes.some((prefix) => source === prefix || source.startsWith(prefix))
  );

  if (sourcesToTest.length === 0) {
    return [];
  }

  // 并发测速，最大并发数 6
  const MAX_CONCURRENCY = 6;
  const testResults: SourcePretestResult[] = [];
  let nextIndex = 0;

  const worker = async () => {
    while (nextIndex < sourcesToTest.length) {
      const currentIndex = nextIndex++;
      const [source] = sourcesToTest[currentIndex];

      try {
        // 使用轻量级 ping 测速：直接测 API 代理端点的延迟
        const startTime = performance.now();
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 5000);

        const response = await fetch(
          `/api/source-pretest?source=${encodeURIComponent(source)}`,
          { signal: controller.signal, cache: 'no-store' }
        );

        clearTimeout(timer);

        const pingTime = response.ok
          ? Math.round(performance.now() - startTime)
          : -1;

        const result: SourcePretestResult = {
          sourceKey: source,
          pingTime,
          testedAt: Date.now(),
        };

        testResults.push(result);
        onProgress?.(result);
      } catch {
        const result: SourcePretestResult = {
          sourceKey: source,
          pingTime: -1,
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

  // 缓存到 sessionStorage
  savePretestCache(query, testResults);

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
 * 根据预测速结果对搜索源进行排序，延迟最低的排在前面
 */
export function sortSourcesByPretest<T extends { source: string }>(
  sources: T[],
  pretestResults: SourcePretestResult[]
): T[] {
  const pingMap = new Map(pretestResults.map((r) => [r.sourceKey, r.pingTime]));

  return [...sources].sort((a, b) => {
    const pingA = pingMap.get(a.source) ?? Infinity;
    const pingB = pingMap.get(b.source) ?? Infinity;

    // 不可达的排最后
    if (pingA === -1 && pingB !== -1) return 1;
    if (pingA !== -1 && pingB === -1) return -1;
    if (pingA === -1 && pingB === -1) return 0;

    return pingA - pingB;
  });
}
