(function () {
    var plugin_id = "clipboard_lampa";
    console.log(`[${plugin_id}] Плагин запущен`);

    var lastQuery = ""; // Последнее значение буфера

    function checkClipboard() {
        navigator.clipboard.readText().then(query => {
            if (query && query !== lastQuery) {
                console.log(`[${plugin_id}] Найден новый текст в буфере: ${query}`);
                lastQuery = query;
                searchMovie(query);
            }
        }).catch(err => console.error(`[${plugin_id}] Ошибка чтения буфера:`, err));
    }

    function searchMovie(query) {
        console.log(`[${plugin_id}] Запускаем поиск: ${query}`);
        Lampa.Activity.backward();
        setTimeout(() => {
            Lampa.Controller.toggle("search");
            setTimeout(() => {
                let searchInput = document.querySelector(".search__input");
                if (searchInput) {
                    console.log(`[${plugin_id}] Вставляем текст: ${query}`);
                    searchInput.value = query;
                    searchInput.dispatchEvent(new Event("input", { bubbles: true }));

                    // Эмулируем нажатие "Enter"
                    let enterEvent = new KeyboardEvent("keydown", { key: "Enter", bubbles: true });
                    searchInput.dispatchEvent(enterEvent);
                } else {
                    console.log(`[${plugin_id}] Поле поиска не найдено!`);
                }
            }, 1500);
        }, 1000);
    }

    setInterval(checkClipboard, 3000); // Проверяем буфер каждые 3 секунды

    console.log(`[${plugin_id}] Плагин успешно загружен!`);
})();
