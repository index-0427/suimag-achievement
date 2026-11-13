-- 標準実績。追加担当者は同じフォルダに作者別の .lua ファイルを作成してください。
-- ファイル名順、その中の記載順で表示します。追加例: docs/adding-achievements.md
-- 公開済みの id / target は保存済みの進捗に影響するため変更しないでください。
return {
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
