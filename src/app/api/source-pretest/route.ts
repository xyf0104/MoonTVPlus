/**
 * 播放源预测速 API 端点
 * 用于搜索页面在搜索的同时对各个源进行 ping 测速
 * 通过服务端代理请求源 API 来测量延迟，避免浏览器跨域限制
 */
import { NextRequest, NextResponse } from 'next/server';

import { getConfig } from '@/lib/config';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const sourceKey = searchParams.get('source');

  if (!sourceKey) {
    return NextResponse.json({ error: 'Missing source parameter' }, { status: 400 });
  }

  try {
    const config = await getConfig();
    const sourceConfig = config.SourceConfig.find((s) => s.key === sourceKey);

    if (!sourceConfig || !sourceConfig.api) {
      return NextResponse.json({ pingTime: -1, error: 'Source not found' });
    }

    // 构造最轻量级的请求（只获取列表第一页）
    const testUrl = sourceConfig.api.includes('?')
      ? `${sourceConfig.api}&ac=videolist&pg=1`
      : `${sourceConfig.api}?ac=videolist&pg=1`;

    const startTime = performance.now();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);

    const response = await fetch(testUrl, {
      signal: controller.signal,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        Accept: 'application/json',
      },
    });

    clearTimeout(timeout);
    const pingTime = Math.round(performance.now() - startTime);

    if (!response.ok) {
      return NextResponse.json({ pingTime: -1, status: response.status });
    }

    return NextResponse.json({
      pingTime,
      source: sourceKey,
      status: response.status,
    });
  } catch (error) {
    return NextResponse.json({
      pingTime: -1,
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
}
