# -*- coding: utf-8 -*-
"""
1. 一覧ページを1ページ取得するごとに box_raw.csv へ追記（途中経過）
2. 全部終わったら box_raw.csv を読み込み、
   空白除外 → 敬称なし除外 → 敬称除去 → 重複排除 → 除外キーワード → box_cmp.csv を出力
"""
import os
import re
import time
from urllib import request
from urllib.parse import urljoin

import pandas as pd
from bs4 import BeautifulSoup

BASE_URL = "https://xn--pckua2a7gp15o89zb.com"
RAW_FILE = 'box_raw.csv'
CMP_FILE = 'box_cmp.csv'
PREFIXES = ["合資会社", "株式会社", "合同会社", "社会福祉法人", "有限会社"]
DEL_WORDS = ["派遣"]
KEY_LEN = 8
HEADER = ['company', 'tel', 'address', 'url', 'url_2', 'mail', 'title',
          'industry', 'first_name', 'other', 'other2', 'other3']
FILTER_COLS = ['company', 'address', 'title', 'other', 'other2', 'other3']
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"}


def has_honorific(name: str) -> bool:
    name = name.strip()
    return any(name.startswith(p) or name.endswith(p) for p in PREFIXES)


def clean_company(name: str) -> str:
    name = name.strip()
    for p in PREFIXES:
        if name.startswith(p):
            return name[len(p):].strip()
    return name


def scrape_page(url: str):
    try:
        with request.urlopen(request.Request(url, headers=UA), timeout=10) as resp:
            html = resp.read()
    except Exception as e:
        print(f"[ERROR] URL取得失敗: {e} -> {url}")
        return [], ''
    soup = BeautifulSoup(html, 'html.parser')

    nxt = soup.select_one('a.c-pager_btn--next')
    next_page = urljoin(url, nxt['href']) if nxt and nxt.get('href') else ''

    rows = []
    for card in soup.select('section.p-result_card'):
        item = dict.fromkeys(HEADER, '')
        c = card.select_one('p.p-result_companyName') or card.select_one('p.p-result_company')
        if c: item['company'] = c.get_text(strip=True)
        a = card.select_one('li.p-result_area')
        if a: item['address'] = a.get_text(strip=True)
        u = card.select_one('a.p-result_title_link')
        if u: item['url_2'] = urljoin(BASE_URL, u['href'])
        t = card.select_one('span.p-result_name')
        if t: item['title'] = t.get_text(strip=True)
        e = card.select_one('li.p-result_employType')
        if e: item['other'] = e.get_text(strip=True)
        ud = card.select_one('p.p-result_updatedAt_hyphen')
        if ud: item['other2'] = ud.get_text(strip=True)
        ps = card.select_one('p.p-result_source')
        if ps: item['other3'] = ps.get_text(strip=True)
        item['industry'] = '深夜業務（業種問わず）'
        if item['company']:
            rows.append(item)
    return rows, next_page


def append_raw(records):
    records = [r for r in records if str(r.get('company', '')).strip()]
    if not records:
        return
    df = pd.DataFrame(records, columns=HEADER)
    first = not os.path.exists(RAW_FILE)
    df.to_csv(RAW_FILE, mode='w' if first else 'a', header=first, index=False,
              encoding='utf-8-sig' if first else 'utf-8')  # BOMは先頭に1回だけ


def main():
    try:
        df_urls = pd.read_csv('box_url.csv', encoding='utf-8')
        print(f"[INFO] 起点URLを {len(df_urls)} 件読み込み")
    except Exception:
        print("[ERROR] 起点CSVが読み込めません。box_url.csv を確認してください。")
        return

    # ── 1. スクレイピング（1ページごとに途中経過へ追記） ──
    if os.path.exists(RAW_FILE):
        os.remove(RAW_FILE)
    total = 0
    for idx, start_url in enumerate(df_urls['url'], start=1):
        print(f"[INFO] {idx}/{len(df_urls)}: 開始 URL -> {start_url}")
        next_url = start_url
        page_no = 1
        while next_url:
            records, next_url = scrape_page(next_url)
            if records:
                append_raw(records)
            total += len(records)
            print(f"    [PAGE{page_no}] {len(records)} 件取得 (累計 {total}) --> 次ページ: {next_url or 'なし'}")
            page_no += 1
            time.sleep(1)

    if total == 0:
        print("[WARN] データが取得できませんでした。処理を終了します。")
        return
    print(f"[INFO] 途中経過を {RAW_FILE} に保存: {total} 件")

    # ── 2. 途中経過ファイルから CMP を作成 ──
    df = pd.read_csv(RAW_FILE, encoding='utf-8-sig', dtype=str, keep_default_na=False)
    before = len(df)
    df = df[df['company'].str.strip() != ''].copy()
    print(f"[INFO] 空白除外: {before} -> {len(df)} 件")
    before = len(df)
    df = df[df['company'].map(has_honorific)].copy()
    print(f"[INFO] 敬称なし除外: {before} -> {len(df)} 件")
    df['company_clean'] = df['company'].map(clean_company)

    # 重複排除
    before = len(df)
    seen, keep = set(), []
    for comp, url2 in zip(df['company_clean'], df['url_2']):
        key = comp[:KEY_LEN] or url2
        keep.append(not key or key not in seen)
        seen.add(key)
    df = df[keep].copy()
    print(f"[INFO] 重複排除完了: {before} -> {len(df)} 件")

    # 除外キーワード（空文字は全行マッチするので除外）
    words = [w for w in DEL_WORDS if w]
    if words:
        pattern = "|".join(map(re.escape, words))
        before = len(df)
        hit = pd.Series(False, index=df.index)
        for col in FILTER_COLS:
            m = df[col].str.contains(pattern, regex=True, na=False)
            print(f"    [FILTER] {col}: {int(m.sum())} 件ヒット")
            hit |= m
        df = df[~hit].copy()
        print(f"[INFO] キーワードフィルタ完了: {before} -> {len(df)} 件")

    df = df.drop(columns=['company_clean'])
    df.to_csv(CMP_FILE, index=False, encoding='utf-8-sig')
    print(f"[INFO] 完了: {CMP_FILE} に {len(df)} 件を出力しました。")


if __name__ == '__main__':
    main()