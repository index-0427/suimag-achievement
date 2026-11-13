# suimag-achievement

FiveM / Qbox 向けの LB Phone 実績アプリ。ビルド不要の Lua + HTML/CSS/JavaScript です。

- 実績一覧、進捗、達成日を表示
- 各実績の取得率・取得人数／全プレイヤー数を約2時間ごとに集計
- 達成済みの称号を選択・解除
- suimag-playernames-improved の名前の前に称号を表示
- citizenid ごとに進捗と選択した称号をサーバーの KVP へ保存
- 初ログイン、累計1時間、累計10時間の3実績を同梱
- 他リソース用のサーバー exports（進捗加算・即時達成）

報酬配布、ランキング、管理画面、ジョブ固有の判定は含みません。

## 導入

依存: `qbx_core` / `ox_lib` / `oxmysql` / `lb-phone` / `suimag-playernames-improved`。

1. このフォルダを `resources/[suimag]/suimag-achievement` に配置します。
2. `server.cfg` に次の設定を追加します。依存リソースを既に起動している場合は重複追加不要です。

```cfg
ensure oxmysql
ensure ox_lib
ensure qbx_core
ensure lb-phone

# 称号表示に必要。既存の設定がある場合はその行を置き換えます。
set playerNames_template "{{achievementPrefix or ''}}{{name}}"
ensure suimag-playernames-improved
ensure suimag-achievement
```

3. 再起動後、LB Phone の「実績」を開きます。「はじめの一歩」の称号を選択し、ネームタグに表示されることを確認します。

`suimag-playernames-improved` は既存の `playernames:extendContext` と `playernames:configure` を使用するため、ソースの変更は不要です。独自の名前テンプレートがある場合は、その先頭に `{{achievementPrefix or ''}}` を追加してください。称号は名前と同じ行・同じ色で表示されます。ネームタグ側の表示設定・表示距離に従い、自分で確認する場合は自分の名前表示も有効にしてください。

ネームタグ設定画面の「実績（coming soon）」は使用しません。称号の変更はスマホの実績アプリで行います。

## 実績の追加

**`achievements/` 直下に、作者ごとの `.lua` ファイルを追加します。** 1ファイルにその人が作った実績を複数まとめられます。起動時に全ファイルを自動で読み込むため、追加のたびに `fxmanifest.lua` や本体・UIを編集する必要はありません。

```text
achievements/
├── 00_default.lua   # 同梱の標準3実績
├── 10_author_a.lua  # Aさんの実績一式（追加例）
└── 20_author_b.lua  # Bさんの実績一式（追加例）
```

各ファイルは `return { ... }` で定義の一覧を返します。表示順はファイル名の昇順、その中の記載順です。ファイル間でも実績IDの重複を検出し、両方のファイル名・位置をエラーに表示します。

- 初ログイン・累計接続時間の実績: 定義ファイルの追加だけで動きます。
- 配達回数などの実績: 定義ファイルを追加し、条件を確認した外部リソースのサーバー処理から `AddProgress` / `Unlock` を呼びます。

ファイルの完成例、各項目の説明、外部ジョブとの連携、動作確認は **[実績追加ガイド](docs/adding-achievements.md)** を参照してください。

| ファイル | 用途 |
| --- | --- |
| `achievements/*.lua` | 作者別の実績定義。追加担当者が編集する場所 |
| `config.lua` | 全体設定（取得率の集計間隔） |
| `server/main.lua` | 定義の読み込み・検証、保存・自動加算・取得率・サーバー exports |
| `client/main.lua` / `ui/` | スマホアプリと称号表示 |
| `tests/` | ローカル回帰テスト・UIプレビュー |

旧版の `config.lua` または単一の `achievements.lua` に独自実績がある場合は、更新前に退避し、`achievements/` 内の作者別ファイルへ同じ `id` / `target` で移してください。`Config.Achievements = { ... }` は `return { ... }` に変更します。旧形式のファイルは自動で統合されません。標準3実績と保存形式は維持しており、同じリソース名を使えば保存済みの進捗・称号を引き継げます。

## 実績取得率

各実績に「取得率 12.5%（25 / 200人）」の形式で表示します。

- 全プレイヤー数は Qbox の既存 `players` テーブルに登録された**全キャラクター数**です。オフライン・アプリ未使用のキャラクターも含め、アカウント単位では数えません。
- 取得人数は、その一覧に存在するキャラクターの KVP 進捗が目標に到達している人数です。削除済みキャラクターは分子・分母の両方から除外します。
- DB接続準備完了後のリソース起動時に集計し、その後は `Config.StatisticsRefreshMinutes = 120`（2時間）ごとに再集計します。
- 集計結果はメモリに保持します。画面の更新ボタン・実績取得・再ログインでは全体の再集計を行わず、次回集計まで取得率への反映を待ちます。自身の進捗表示は通常どおり更新します。
- 最終集計時刻を画面に表示します。全プレイヤー数が0なら取得率は0.0%。初回集計前は「集計待ち」、DBエラー・破損データによる失敗時は前回の集計結果と時刻を保持し、次の周期で再試行します。
- 追加SQLやテーブル作成は不要です。`oxmysql` を通じて既存の `players.citizenid` を読み取ります。既存環境ではファイルを更新して `suimag-achievement` を再起動してください。

## 保存

追加SQLの導入は不要です。FiveM のサーバー KVP を使い、リソース名 `suimag-achievement` と `character:<citizenid>` の組み合わせで保存します。移転・バックアップ時はサーバーの KVP データも含めてください。リソース名を変更すると別の保存領域になります。

進捗加算・称号変更は即時保存し、接続時間は約1分ごととログアウト・正常なリソース停止時に保存します。強制終了時は直近約1分の接続時間を失う場合があります。破損した保存データは上書きせず、サーバーログへエラーを出します。

## 開発時の確認

Lua 5.4 と Node.js で実行できます。テストに追加パッケージは不要です。

```bash
node tests/run.js
```

`node tests/run.js` は `achievements/` 内の全Luaファイルを対象に、サーバー・クライアントのテストとUIの構文チェックを実行します。回帰テストは標準3実績を残した構成で利用してください。

UI は `python3 -m http.server 8765 --bind 127.0.0.1` をリポジトリ直下で実行し、`http://127.0.0.1:8765/tests/preview.html` でモック表示できます。プレビューとテストは FiveM に配信するファイルに含めていません。ライト／ダーク、称号選択／解除、エラー、空の一覧を確認できます。

実機確認: アプリ登録、達成済み称号の選択・解除、他プレイヤーからの表示、再接続、キャラクター切替、両リソース再起動後の表示を確認してください。LuaテストはFiveM/QboxのAPIをモック化しており、ゲーム内描画やLB Phone本体の挙動は実機での確認が必要です。

## 参照

- [LB Phone Custom Apps](https://docs.lbscripts.com/phone/custom-apps/)
- [Qbox Server Exports](https://docs.qbox.re/resources/qbx_core/exports/server)
- [Qbox Server Events](https://docs.qbox.re/resources/qbx_core/events/server)
