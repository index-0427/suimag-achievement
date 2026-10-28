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

`config.lua` の `Config.Achievements` に定義を追加します。順番がアプリの表示順です。

```lua
{
    id = 'delivery_10',
    name = '配達の達人',
    description = '配達を10回完了する。',
    title = '配達人',
    target = 10,
    unit = '回',
},
```

`auto = 'join'` は導入後の初ログインで達成、`auto = 'playtime'` はキャラクターで接続していた合計時間（分）を数えます。離席時間も含みます。オフライン中・キャラクター選択中は加算しません。導入前の時間は遡って集計しません。

`auto` のない実績は、達成条件を検証した**サーバースクリプト**から呼び出してください。

```lua
-- 配達完了をサーバー側で確認した処理の中で実行
local ok, reason = exports['suimag-achievement']:AddProgress(source, 'delivery_10', 1)

-- 特定の実績を一度に達成させる
local ok, reason = exports['suimag-achievement']:Unlock(source, 'delivery_10')
```

対象はオンライン中のキャラクターです。`AddProgress` の加算値は正の整数（省略時1）、進捗は目標値で止まります。同じ実績を再達成しても達成日は変わりません。成功時は `true`、失敗時は `false, reason` を返します。理由は `unknown_achievement` / `invalid_amount` / `player_unavailable` です。

クライアントから実績を付与するネットイベントはありません。外部スクリプトもクライアントから送られた達成申告をそのまま exports に渡さず、条件と対象をサーバーで確認してください。

設定変更後はこのリソースを再起動してください。公開済みの `id` と `target` は原則固定にし、新しい条件は別IDで追加します。削除したIDの保存記録は残りますが、一覧や称号には使用しません。

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
lua tests/server_spec.lua
lua tests/client_spec.lua
node --check ui/app.js
```

UI は `python3 -m http.server 8765 --bind 127.0.0.1` をリポジトリ直下で実行し、`http://127.0.0.1:8765/tests/preview.html` でモック表示できます。プレビューとテストは FiveM に配信するファイルに含めていません。ライト／ダーク、称号選択／解除、エラー、空の一覧を確認できます。

実機確認: アプリ登録、達成済み称号の選択・解除、他プレイヤーからの表示、再接続、キャラクター切替、両リソース再起動後の表示を確認してください。LuaテストはFiveM/QboxのAPIをモック化しており、ゲーム内描画やLB Phone本体の挙動は実機での確認が必要です。

## 参照

- [LB Phone Custom Apps](https://docs.lbscripts.com/phone/custom-apps/)
- [Qbox Server Exports](https://docs.qbox.re/resources/qbx_core/exports/server)
- [Qbox Server Events](https://docs.qbox.re/resources/qbx_core/events/server)
