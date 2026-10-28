Config = {}

-- 全キャラクターの実績取得率を再集計する間隔（分）。
Config.StatisticsRefreshMinutes = 120

-- id は保存キーです。公開後は変更しないでください。
-- auto: 'join' = 初ログイン、'playtime' = 累計接続時間（分）。
-- auto を省略した実績は、他のサーバースクリプトから加算します。
Config.Achievements = {
    {
        id = 'welcome',
        name = 'はじめの一歩',
        description = 'この街で、新しい生活を始める。',
        title = '新しい住民',
        target = 1,
        auto = 'join',
    },
    {
        id = 'one_hour',
        name = '街に馴染んで',
        description = 'この街で合計1時間を過ごす。',
        title = '街の住民',
        target = 60,
        auto = 'playtime',
        unit = '分',
    },
    {
        id = 'ten_hours',
        name = 'いつもの街角',
        description = 'この街で合計10時間を過ごす。',
        title = '街の常連',
        target = 600,
        auto = 'playtime',
        unit = '分',
    },
}
