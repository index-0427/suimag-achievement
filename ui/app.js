(() => {
    'use strict';

    const $ = (selector) => document.querySelector(selector);
    const message = $('#message');
    let state = null;
    let busy = false;
    let refreshPending = false;

    function showMessage(text, error = false) {
        message.textContent = text;
        message.classList.toggle('error', error);
        message.hidden = !text;
    }

    function setBusy(value) {
        busy = value;
        $('#refresh').disabled = value;
        $('#clear-title').disabled = value;
        $('#content').setAttribute('aria-busy', String(value));
        document.querySelectorAll('.select-button').forEach((button) => {
            button.disabled = value || button.dataset.available !== 'true';
        });
    }

    function render() {
        const entries = state.achievements;
        const statistics = state.statistics;
        if (statistics) {
            const minutes = statistics.refreshMinutes;
            const interval = minutes % 60 === 0 ? (minutes / 60) + '時間' : minutes + '分';
            const updated = new Date(statistics.updatedAt * 1000).toLocaleString('ja-JP', {
                month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit',
            });
            $('#statistics-info').textContent = '取得率は全キャラクター対象・約' + interval + 'ごとに更新\n最終集計 ' + updated;
        } else {
            $('#statistics-info').textContent = '取得率は初回集計を待っています。';
        }
        const unlocked = entries.filter((entry) => entry.unlocked).length;
        $('#unlocked-count').textContent = unlocked;
        $('#total-count').textContent = entries.length;
        $('#overall-progress').max = entries.length || 1;
        $('#overall-progress').value = unlocked;
        const selected = entries.find((entry) => entry.id === state.selected && entry.unlocked);
        $('#equipped-title').textContent = selected ? selected.title : '設定していません';
        $('#clear-title').hidden = !selected;

        const list = $('#achievements');
        list.replaceChildren();
        entries.forEach((entry, index) => {
            const card = $('#achievement-template').content.firstElementChild.cloneNode(true);
            const equipped = entry.id === state.selected;
            card.classList.toggle('unlocked', entry.unlocked);
            card.querySelector('.achievement-number').textContent = String(index + 1).padStart(2, '0');
            card.querySelector('.badge').textContent = entry.unlocked ? '達成済み' : '挑戦中';
            card.querySelector('h3').textContent = entry.name;
            card.querySelector('.description').textContent = entry.description;
            card.querySelector('.progress-text').textContent =
                entry.progress.toLocaleString('ja-JP') + ' / ' + entry.target.toLocaleString('ja-JP') + ' ' + entry.unit;
            const time = card.querySelector('time');
            if (entry.unlocked && entry.unlockedAt) {
                const date = new Date(entry.unlockedAt * 1000);
                time.dateTime = date.toISOString();
                time.textContent = date.toLocaleDateString('ja-JP');
            }
            const progress = card.querySelector('progress');
            progress.max = entry.target;
            progress.value = entry.progress;
            progress.setAttribute('aria-label', entry.name + 'の進捗');
            const rateLabel = card.querySelector('.acquisition-rate');
            if (statistics && Number.isInteger(entry.unlockedCount)) {
                const total = statistics.totalPlayers;
                const rate = total > 0 ? entry.unlockedCount / total * 100 : 0;
                rateLabel.textContent = '取得率 ' + rate.toFixed(1) + '%（'
                    + entry.unlockedCount.toLocaleString('ja-JP') + ' / '
                    + total.toLocaleString('ja-JP') + '人）';
            } else {
                rateLabel.textContent = '取得率 集計待ち';
            }
            card.querySelector('.reward-title').textContent = '称号「' + entry.title + '」';
            const button = card.querySelector('button');
            button.textContent = equipped ? '表示中' : entry.unlocked ? '称号にする' : '未獲得';
            button.classList.toggle('selected', equipped);
            button.dataset.available = String(entry.unlocked && !equipped);
            button.disabled = !entry.unlocked || equipped;
            button.addEventListener('click', () => request('selectTitle', { id: entry.id }));
            list.append(card);
        });
        $('#empty').hidden = entries.length > 0;
        $('#content').hidden = false;
    }

    async function request(event = 'getAchievements', data = {}) {
        if (busy) return;
        setBusy(true);
        showMessage(state ? '' : '実績を読み込んでいます…');
        let timeout;
        try {
            if (typeof globalThis.fetchNui !== 'function') {
                throw new Error('LB Phoneに接続できません。アプリを開き直してください。');
            }
            const response = await Promise.race([
                globalThis.fetchNui(event, data),
                new Promise((_, reject) => {
                    timeout = setTimeout(() => reject(new Error('通信がタイムアウトしました。更新ボタンで再試行できます。')), 12000);
                }),
            ]);
            // Some FiveM JSON versions encode an empty Lua array as an object.
            if (response?.ok && response.achievements && !Array.isArray(response.achievements)
                && typeof response.achievements === 'object' && Object.keys(response.achievements).length === 0) {
                response.achievements = [];
            }
            if (!response?.ok || !Array.isArray(response.achievements)) {
                throw new Error(response?.error || '実績を読み込めませんでした。');
            }
            state = response;
            render();
            showMessage('');
        } catch (error) {
            // A failed character load must not leave another character's data visible.
            if (event === 'getAchievements') {
                state = null;
                $('#content').hidden = true;
            }
            showMessage(error.message || '通信に失敗しました。', true);
        } finally {
            clearTimeout(timeout);
            setBusy(false);
            if (refreshPending) {
                refreshPending = false;
                request();
            }
        }
    }

    $('#refresh').addEventListener('click', () => request());
    $('#clear-title').addEventListener('click', () => request('selectTitle', { id: '' }));
    window.addEventListener('message', (event) => {
        if (event.data?.type === 'achievementsChanged') {
            if (busy) refreshPending = true;
            else request();
        }
    });

    function applyTheme(settings) {
        if (settings?.display?.theme) document.documentElement.dataset.theme = settings.display.theme;
    }

    // LB Phone injects its bridge into the iframe after loading the document.
    async function start() {
        for (let attempt = 0; attempt < 100 && typeof globalThis.fetchNui !== 'function'; attempt++) {
            await new Promise((resolve) => setTimeout(resolve, 100));
        }
        applyTheme(globalThis.settings);
        if (typeof globalThis.onSettingsChange === 'function') globalThis.onSettingsChange(applyTheme);
        request();
    }
    start();
})();
